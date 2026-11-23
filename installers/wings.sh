# shellcheck shell=bash
# Wings node in Docker, paired with an existing panel. Follows https://calagopus.com/docs/wings/installation/docker
# and https://calagopus.com/docs/wings/next-steps/configure-node.

cala_wings_questions() {
  cala_step "Wings node settings"
  cala_ask CALA_WINGS_DIR "Install directory" /opt/calagopus-wings cala_valid_install_dir "an absolute directory path"
  if [[ -f "$CALA_WINGS_DIR/compose.yml" ]]; then
    if ((CALA_INTERACTIVE == 1)); then
      local CALA_RUN_UPDATE
      cala_ask_yes_no CALA_RUN_UPDATE "Wings is already installed in $CALA_WINGS_DIR. Update it instead?" y
      if [[ "$CALA_RUN_UPDATE" == yes ]]; then
        cala_update
        exit 0
      fi
    fi
    cala_die "Wings is already installed in $CALA_WINGS_DIR. Use the Update action, or Uninstall first."
  fi
  cala_ask CALA_TIMEZONE "Time zone for the container" "$(cala_detect_timezone)" cala_valid_timezone "a time zone like Europe/Berlin or UTC"

  [[ -n "${CALA_PUBLIC_IP:-}" ]] || CALA_PUBLIC_IP="$(cala_detect_public_ip 4)"
  [[ -n "$CALA_PUBLIC_IP" ]] || CALA_PUBLIC_IP="$(cala_detect_local_ipv4)"

  cala_info ""
  cala_info "Pairing: by default Wings starts without a configuration and prints a pairing code; you then"
  cala_info "use Admin -> Nodes -> Create -> Pair a Waiting Node in the panel."
  cala_info "Or enroll it now: create the node in the panel, open its Configuration tab, click"
  cala_info "Generate Enrollment Command, and paste the Panel URL and code here (valid for 30 minutes)."
  cala_ask CALA_WINGS_PANEL_URL "Panel URL for enrollment (empty to pair later)" "" cala_valid_url_or_empty "a URL like https://panel.example.com"
  if [[ -n "$CALA_WINGS_PANEL_URL" ]]; then
    cala_ask CALA_WINGS_ENROLL_CODE "Enrollment code" "" cala_valid_enroll_code "the code from the enrollment command"
  else
    CALA_WINGS_ENROLL_CODE=""
  fi

  cala_firewall_questions wings
}

cala_install_wings() {
  cala_wings_questions

  cala_step "Summary"
  cala_info "Install:    Wings node"
  cala_info "Directory:  $CALA_WINGS_DIR (config in $CALA_WINGS_DIR/config, game data in /var/lib/calagopus-wings)"
  cala_info "Pairing:    $([[ -n "$CALA_WINGS_PANEL_URL" ]] && echo "enroll with $CALA_WINGS_PANEL_URL" || echo "pairing code, from the panel")"
  cala_info "Firewall:   $([[ "$CALA_FIREWALL" == yes ]] && echo "TCP $(cala_firewall_tcp_ports wings "" "$CALA_SSH_PORT")${CALA_GAME_PORTS:+, games $CALA_GAME_PORTS}" || echo unchanged)"
  cala_check_requirements "$CALA_WINGS_DIR" no
  cala_check_ports_free 8080 2022
  cala_confirm_start

  if cala_truthy "${CALA_DRY_RUN:-no}"; then
    cala_ok "Dry run: stopping before Docker. Nothing was installed besides the prerequisites."
    return 0
  fi

  cala_step "Docker"
  cala_install_docker

  cala_step "Setting up $CALA_WINGS_DIR"
  local compose="$CALA_WINGS_DIR/compose.yml"
  mkdir -p "$CALA_WINGS_DIR/config" "$CALA_WINGS_DIR/logs" /etc/ssl/certs/wings /var/lib/calagopus-wings
  cala_run "Downloading Wings' compose.local.yml" curl -fsSL --retry 3 "$CALA_WINGS_COMPOSE_URL" -o "$compose"
  chmod 600 "$compose"
  cala_compose_set_timezone "$compose" "$CALA_TIMEZONE" || cala_fail "could not set the time zone in compose.yml"
  if [[ -n "$CALA_WINGS_PANEL_URL" ]]; then
    cala_wings_compose_set_enroll "$compose" "$CALA_WINGS_PANEL_URL" "$CALA_WINGS_ENROLL_CODE" ||
      cala_fail "could not add the enrollment variables to compose.yml (did upstream change the file?)"
  fi
  cala_write_state "$CALA_WINGS_DIR" MODE=wings "INSTALLER_VERSION=$CALA_INSTALLER_VERSION" \
    "INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cala_step "Starting Wings"
  cala_run "Pulling the Wings image" cala_compose "$CALA_WINGS_DIR" pull
  cala_run "Starting Wings" cala_compose "$CALA_WINGS_DIR" up -d
  cala_wait_http http://127.0.0.1:8080 180 || {
    cala_compose_logs_to_log "$CALA_WINGS_DIR"
    cala_fail "Wings did not answer on port 8080"
  }
  cala_ok "Wings answers on port 8080"

  local paired=no
  if [[ -n "$CALA_WINGS_PANEL_URL" ]]; then
    local waited=0
    while ((waited < 90)) && [[ ! -s "$CALA_WINGS_DIR/config/config.yml" ]]; do
      sleep 3
      waited=$((waited + 3))
    done
    if [[ -s "$CALA_WINGS_DIR/config/config.yml" ]]; then
      paired=yes
      cala_wings_compose_remove_enroll "$compose"
      cala_run "Removing the used enrollment code from compose.yml" cala_compose "$CALA_WINGS_DIR" up -d
      cala_ok "Enrolled with $CALA_WINGS_PANEL_URL"
    else
      cala_compose_logs_to_log "$CALA_WINGS_DIR"
      cala_warn "Enrollment did not finish (expired or used code, or the panel is unreachable). Wings now waits for pairing."
      cala_wings_compose_remove_enroll "$compose"
    fi
  fi

  if [[ "$CALA_FIREWALL" == yes ]]; then
    cala_step "Firewall"
    cala_configure_firewall "$(cala_firewall_tcp_ports wings "" "$CALA_SSH_PORT")" "${CALA_GAME_PORTS:-}"
  fi

  cala_step "Done"
  if [[ "$paired" == no ]]; then
    local code_lines=""
    for _ in $(seq 1 20); do
      code_lines="$(cala_compose "$CALA_WINGS_DIR" logs --no-color wings 2>/dev/null | grep -i 'pair' | tail -n 3 || true)"
      [[ -n "$code_lines" ]] && break
      sleep 3
    done
    cat <<EOF
  Wings is waiting to be paired. Its pairing code is in its log:
$(printf '%s\n' "${code_lines:-    (not printed yet; run: cd $CALA_WINGS_DIR && sudo docker compose logs wings)}" | sed 's/^/    /')

  In the panel: Admin -> Nodes -> Create -> Pair a Waiting Node
    Node Address:  http://$CALA_PUBLIC_IP:8080   (an address the panel can reach)
    Pairing Code:  the code above (after five wrong tries Wings prints a new one)
EOF
  else
    printf '  Wings is enrolled and connected to %s.\n' "$CALA_WINGS_PANEL_URL"
  fi
  cat <<EOF

  Files:   $CALA_WINGS_DIR (compose.yml, config/config.yml), game data in /var/lib/calagopus-wings
  Logs:    cd $CALA_WINGS_DIR && sudo docker compose logs --tail 80 wings
  Update:  $CALA_ONE_LINER   (choose Update)

  Next steps:
    - Open 8080 (Wings API) and 2022 (SFTP) and your game ports in the provider's firewall.
    - If the panel uses HTTPS, browsers need HTTPS to Wings too: give Wings a certificate
      (https://calagopus.com/docs/wings/next-steps/ssl) or use Wings Proxy Mode.
    - Add allocations: https://calagopus.com/docs/wings/next-steps/setting-up-allocations

  Log of this run: $CALA_LOG_FILE
EOF
}
