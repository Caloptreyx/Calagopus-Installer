# shellcheck shell=bash
# All-in-One (panel + Wings in one container) and standalone panel installs.
# Follows https://calagopus.com/docs/panel/installation/first-vps and /docs/panel/installation/docker.

CALA_PANEL_LOCAL="http://127.0.0.1:8000"

# --- questions -----------------------------------------------------------------------------------

cala_panel_questions() {
  local mode="$1"

  cala_step "Panel settings"
  cala_ask CALA_PANEL_DIR "Install directory" /opt/calagopus-panel cala_valid_install_dir "an absolute directory path"
  if [[ -f "$CALA_PANEL_DIR/compose.yml" ]]; then
    cala_warn "Calagopus is already installed in $CALA_PANEL_DIR. Installing again would replace its encryption key."
    if ((CALA_INTERACTIVE == 1)); then
      local CALA_RUN_UPDATE
      cala_ask_yes_no CALA_RUN_UPDATE "Update the existing install instead?" y
      if [[ "$CALA_RUN_UPDATE" == yes ]]; then
        cala_update
        exit 0
      fi
    fi
    cala_die "refusing to install over an existing panel. Use the Update action, or Uninstall first."
  fi

  cala_ask CALA_TIMEZONE "Time zone for the containers" "$(cala_detect_timezone)" cala_valid_timezone "a time zone like Europe/Berlin or UTC"

  cala_info ""
  cala_info "With a domain, Caddy serves the panel over HTTPS (needs ports 80 and 443 and an A record)."
  cala_info "Without one, the panel is on http://<server-ip>:8000 and passwords cross the internet unencrypted."
  cala_ask CALA_DOMAIN "Domain for the panel (empty for none)" "" cala_valid_domain_or_empty "a domain like panel.example.com, or empty"
  CALA_DOMAIN="${CALA_DOMAIN,,}"

  if [[ -z "${CALA_PUBLIC_IP:-}" ]]; then
    CALA_PUBLIC_IP="$(cala_detect_public_ip 4)"
    [[ -n "$CALA_PUBLIC_IP" ]] || CALA_PUBLIC_IP="$(cala_detect_local_ipv4)"
  fi
  if [[ -z "$CALA_PUBLIC_IP" ]]; then
    unset CALA_PUBLIC_IP
    cala_ask CALA_PUBLIC_IP "Public IPv4 address of this server" "" cala_valid_ipv4 "an IPv4 address"
  fi
  cala_valid_ipv4 "$CALA_PUBLIC_IP" || cala_die "CALA_PUBLIC_IP: '$CALA_PUBLIC_IP' is not an IPv4 address"
  cala_info "Public IPv4: $CALA_PUBLIC_IP"

  if [[ -n "$CALA_DOMAIN" ]]; then
    CALA_APP_URL="https://$CALA_DOMAIN"
    local ipv6
    ipv6="$(cala_detect_public_ip 6)"
    if ! cala_check_dns "$CALA_DOMAIN" "$CALA_PUBLIC_IP" "$ipv6"; then
      cala_info "Caddy can only get a certificate once $CALA_DOMAIN points at this server."
      cala_ask_yes_no CALA_IGNORE_DNS "Continue anyway?" n
      [[ "$CALA_IGNORE_DNS" == yes ]] || cala_die "fix the DNS records (see above), wait for them to update, then run the installer again"
    fi
  else
    CALA_APP_URL="http://$CALA_PUBLIC_IP:8000"
  fi

  cala_step "Administrator account"
  cala_info "The first account becomes the administrator. The installer creates it while the panel only"
  cala_info "listens on 127.0.0.1, so nobody else can claim the panel first."
  cala_ask_yes_no CALA_CREATE_ADMIN "Create the administrator account now?" y
  if [[ "$CALA_CREATE_ADMIN" == yes ]]; then
    cala_ask CALA_ADMIN_EMAIL "Email" "" cala_valid_email "an email address"
    cala_ask CALA_ADMIN_USERNAME "Username (3-48 letters, digits, _)" "" cala_valid_username "3 to 48 letters, digits or underscores"
    cala_ask_secret CALA_ADMIN_PASSWORD "Password (8+ characters)" cala_valid_password "8 to 512 characters"
  else
    cala_warn "The panel will stay on 127.0.0.1 until you create the account yourself (instructions at the end)."
  fi

  cala_firewall_questions "$mode"
  cala_extension_questions
}

cala_firewall_questions() {
  local mode="$1"
  cala_step "Firewall"
  cala_info "The installer can open the ports Calagopus needs in $([[ "$OS_FAMILY" == rhel ]] && echo firewalld || echo ufw) and enable it."
  cala_ask_yes_no CALA_FIREWALL "Configure the host firewall?" n
  [[ "$CALA_FIREWALL" == yes ]] || return 0
  cala_ask CALA_SSH_PORT "SSH port(s) to keep open" "$(cala_detect_ssh_ports)" cala_valid_port_list_spaces "a port number"
  if [[ "$mode" != panel ]]; then
    cala_ask CALA_GAME_PORTS "Game ports to open (e.g. 25565,25570-25580; empty for none)" 25565 cala_valid_port_list_or_empty "ports or ranges like 25565,25570-25580"
  fi
}

cala_valid_port_list_spaces() {
  cala_valid_port_list "${1// /,}"
}

# Prints the TCP ports the firewall opens for a mode: cala_firewall_tcp_ports MODE DOMAIN SSH_PORTS
cala_firewall_tcp_ports() {
  local mode="$1" domain="$2" ssh="$3" ports
  ports="${ssh//,/ }"
  if [[ "$mode" == wings ]]; then
    ports+=" 8080 2022"
  else
    if [[ -n "$domain" ]]; then
      ports+=" 80 443"
    else
      ports+=" 8000"
    fi
    if [[ "$mode" == aio ]]; then
      ports+=" 2022"
    fi
  fi
  printf '%s' "$ports"
}

cala_panel_summary() {
  local mode="$1" heavy="$2"
  cala_step "Summary"
  cala_info "Install:       $([[ "$mode" == aio ]] && echo "All-in-One (panel + Wings)" || echo "Panel only")$([[ "$heavy" == yes ]] && echo ", heavy image (extensions)")"
  cala_info "Directory:     $CALA_PANEL_DIR"
  cala_info "Address:       $CALA_APP_URL"
  cala_info "Time zone:     $CALA_TIMEZONE"
  cala_info "Admin account: $([[ "$CALA_CREATE_ADMIN" == yes ]] && echo "$CALA_ADMIN_USERNAME <$CALA_ADMIN_EMAIL>" || echo "create it yourself later")"
  if [[ "$CALA_FIREWALL" == yes ]]; then
    cala_info "Firewall:      TCP $(cala_firewall_tcp_ports "$mode" "$CALA_DOMAIN" "$CALA_SSH_PORT")${CALA_GAME_PORTS:+, games $CALA_GAME_PORTS}"
  else
    cala_info "Firewall:      unchanged"
  fi
  cala_info "Extensions:    ${CALA_EXTENSION_PICKS[*]:-none}"
}

cala_confirm_start() {
  ((CALA_INTERACTIVE == 1)) || return 0
  local CALA_START
  cala_ask_yes_no CALA_START "Start the installation?" y
  [[ "$CALA_START" == yes ]] || cala_die "cancelled, nothing was changed"
}

cala_check_ports_free() {
  local port
  for port in "$@"; do
    if cala_port_in_use "$port"; then
      cala_die "port $port is already in use on this server (see: ss -ltnp 'sport = :$port'). Free it and run the installer again."
    fi
  done
}

# --- panel API (only ever over 127.0.0.1) --------------------------------------------------------

# cala_panel_api METHOD PATH [BODY_FILE]: prints the HTTP status; the body lands in $CALA_TMP/api-response.
cala_panel_api() {
  local method="$1" path="$2" body="${3:-}" args=()
  [[ -f "$CALA_TMP/cookies" ]] || : >"$CALA_TMP/cookies"
  args=(-sS -o "$CALA_TMP/api-response" -w '%{http_code}' -X "$method" --max-time 30
    -b "$CALA_TMP/cookies" -c "$CALA_TMP/cookies" -H 'Accept: application/json')
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body")
  fi
  curl "${args[@]}" "$CALA_PANEL_LOCAL$path" 2>>"${CALA_LOG_FILE:-/dev/null}" || printf '000'
}

cala_api_error() {
  jq -r '(.errors // [.error // empty]) | join("; ")' "$CALA_TMP/api-response" 2>/dev/null || head -c 300 "$CALA_TMP/api-response"
}

# Waits until the panel serves its settings API, then prints the OOBE step ("register" on a fresh panel).
cala_wait_panel_api() {
  local timeout="$1" waited=0 step
  while ((waited < timeout)); do
    if [[ "$(cala_panel_api GET /api/settings)" == 200 ]] && jq -e 'has("oobe_step")' "$CALA_TMP/api-response" >/dev/null 2>&1; then
      step="$(jq -r '.oobe_step // ""' "$CALA_TMP/api-response")"
      printf '%s' "$step"
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
  done
  return 1
}

cala_webauthn_json() {
  local domain="$1"
  if [[ -n "$domain" ]]; then
    jq -n --arg d "$domain" '{enabled: true, allow_discoverable: true, rp_id: $d, rp_origin: ("https://" + $d), authentication_timeout_seconds: 300, registration_timeout_seconds: 300}'
  else
    jq -n '{enabled: false, allow_discoverable: true, rp_id: "localhost", rp_origin: "http://localhost", authentication_timeout_seconds: 300, registration_timeout_seconds: 300}'
  fi
}

# Creates the first (administrator) account and does the wizard's Configuration step: Application URL,
# registration off, passkeys for a domain. The wizard resumes at Egg Repositories on the real address.
cala_create_admin() {
  local step code
  step="$(cala_wait_panel_api 300)" || cala_fail "the panel's API did not answer on $CALA_PANEL_LOCAL"
  if [[ "$step" != register ]]; then
    cala_warn "the panel already has its first account (setup step: ${step:-finished}); not creating one"
    CALA_CREATE_ADMIN=existing
    return 0
  fi

  jq -n --arg u "$CALA_ADMIN_USERNAME" --arg e "$CALA_ADMIN_EMAIL" --arg p "$CALA_ADMIN_PASSWORD" \
    '{username: $u, email: $e, password: $p}' >"$CALA_TMP/register.json"
  code="$(cala_panel_api POST /api/auth/register "$CALA_TMP/register.json")"
  rm -f "$CALA_TMP/register.json"
  [[ "$code" == 200 ]] || cala_fail "creating the administrator failed (HTTP $code): $(cala_api_error)"
  jq -e '.user.admin == true' "$CALA_TMP/api-response" >/dev/null ||
    cala_fail "the new account is not an administrator; the panel was not fresh"
  cala_ok "Administrator $CALA_ADMIN_USERNAME created"

  jq -n --arg url "$CALA_APP_URL" --argjson webauthn "$(cala_webauthn_json "$CALA_DOMAIN")" \
    '{oobe_step: "repositories", app: {url: $url, registration_enabled: false}, webauthn: $webauthn}' \
    >"$CALA_TMP/settings.json"
  code="$(cala_panel_api PUT /api/admin/settings "$CALA_TMP/settings.json")"
  [[ "$code" == 200 ]] || cala_fail "saving the panel settings failed (HTTP $code): $(cala_api_error)"

  code="$(cala_panel_api GET /api/admin/settings)"
  if [[ "$code" != 200 ]] || ! jq -e --arg url "$CALA_APP_URL" \
    '.settings.app.url == $url and .settings.app.registration_enabled == false' "$CALA_TMP/api-response" >/dev/null; then
    cala_fail "the panel did not keep the Application URL / registration settings (HTTP $code)"
  fi
  cala_ok "Application URL set to $CALA_APP_URL, public registration off"
}

# --- install -------------------------------------------------------------------------------------

cala_install_panel() {
  local mode="$1" heavy=no compose_name compose
  CALA_EXTENSION_PICKS=()

  cala_panel_questions "$mode"
  ((${#CALA_EXTENSION_PICKS[@]} > 0)) && heavy=yes
  cala_panel_summary "$mode" "$heavy"
  cala_check_requirements "$CALA_PANEL_DIR" "$heavy"
  cala_check_ports_free 8000
  [[ "$mode" == aio ]] && cala_check_ports_free 2022
  if [[ -n "$CALA_DOMAIN" ]] && ! command -v caddy >/dev/null 2>&1; then
    cala_check_ports_free 80 443
  fi
  if [[ "$mode" == aio && -f /etc/calagopus-wings/config.yml ]]; then
    cala_warn "/etc/calagopus-wings/config.yml exists: a Wings node seems to be installed on this host. AIO brings its own Wings."
  fi
  cala_confirm_start

  if cala_truthy "${CALA_DRY_RUN:-no}"; then
    cala_ok "Dry run: stopping before Docker. Nothing was installed besides the prerequisites."
    return 0
  fi

  cala_step "Docker"
  cala_install_docker

  if [[ "$heavy" == yes ]]; then
    cala_step "Downloading the extensions"
    cala_extensions_download
  fi

  cala_step "Setting up $CALA_PANEL_DIR"
  compose_name="$(cala_panel_compose_name "$mode" "$heavy")"
  compose="$CALA_PANEL_DIR/compose.yml"
  mkdir -p "$CALA_PANEL_DIR"
  cala_run "Downloading $compose_name" curl -fsSL --retry 3 "$CALA_PANEL_COMPOSE_BASE/$compose_name" -o "$compose"
  if [[ "$mode" == aio ]]; then
    # Must exist as a file before the first start, or Docker creates a directory in its place.
    printf 'app_name: Calagopus\n' >"$CALA_PANEL_DIR/wings-config.yml"
  fi
  chmod 600 "$compose"
  [[ -f "$CALA_PANEL_DIR/wings-config.yml" ]] && chmod 600 "$CALA_PANEL_DIR/wings-config.yml"
  cala_compose_set_key "$compose" "$(openssl rand -hex 16)" || cala_fail "could not set APP_ENCRYPTION_KEY in $compose_name (did upstream change the file?)"
  cala_compose_bind_loopback "$compose" || cala_fail "could not bind port 8000 to 127.0.0.1 in $compose_name"
  cala_compose_set_timezone "$compose" "$CALA_TIMEZONE" || cala_fail "could not set the time zone in $compose_name"
  cala_ok "compose.yml written with a new encryption key, panel bound to 127.0.0.1:8000"
  cala_write_state "$CALA_PANEL_DIR" "MODE=$mode" "DOMAIN=$CALA_DOMAIN" "APP_URL=$CALA_APP_URL" \
    "INSTALLER_VERSION=$CALA_INSTALLER_VERSION" "INSTALLED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  cala_step "Starting Calagopus"
  cala_run "Pulling the images (a few minutes on a fresh server)" cala_compose "$CALA_PANEL_DIR" pull
  cala_run "Starting the containers" cala_compose "$CALA_PANEL_DIR" up -d
  cala_info "Waiting for the panel on 127.0.0.1:8000 (the first start runs the database migrations)"
  if ! cala_wait_http "$CALA_PANEL_LOCAL" "${CALA_PANEL_TIMEOUT:-900}"; then
    cala_compose_logs_to_log "$CALA_PANEL_DIR"
    cala_fail "the panel did not answer on 127.0.0.1:8000 within ${CALA_PANEL_TIMEOUT:-900}s"
  fi
  cala_ok "The panel answers on 127.0.0.1:8000"

  if [[ "$CALA_CREATE_ADMIN" == yes ]]; then
    cala_step "Administrator account"
    cala_create_admin
  fi

  cala_step "Making the panel reachable"
  cala_panel_expose
  if [[ "$CALA_FIREWALL" == yes ]]; then
    cala_step "Firewall"
    cala_configure_firewall "$(cala_firewall_tcp_ports "$mode" "$CALA_DOMAIN" "$CALA_SSH_PORT")" "${CALA_GAME_PORTS:-}"
  fi

  if [[ "$heavy" == yes ]]; then
    # Only now: recreating the container (as exposing the panel does) would interrupt a running build.
    cala_step "Installing the extensions"
    cala_extensions_stage "$CALA_PANEL_DIR" || true
    cala_run "Restarting the panel so it builds the extensions" cala_compose "$CALA_PANEL_DIR" restart web
    cala_extensions_wait_build "$CALA_PANEL_DIR"
  fi

  cala_panel_final_summary "$mode"
}

cala_panel_expose() {
  local compose="$CALA_PANEL_DIR/compose.yml"
  if [[ "$CALA_CREATE_ADMIN" == no ]]; then
    cala_warn "No administrator yet, so the panel stays on 127.0.0.1:8000 (see the end of this output)."
    return 0
  fi
  if [[ -n "$CALA_DOMAIN" ]]; then
    local container gateway
    container="$(cala_compose "$CALA_PANEL_DIR" ps -q web)"
    gateway="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.Gateway}} {{end}}' "$container" | awk '{ print $1 }')"
    cala_valid_ipv4 "$gateway" || cala_fail "could not read the Docker network gateway of the web container"
    cala_compose_set_env "$compose" APP_TRUSTED_PROXIES "$gateway" || cala_fail "could not set APP_TRUSTED_PROXIES"
    cala_run "Restarting the panel to trust Caddy ($gateway)" cala_compose "$CALA_PANEL_DIR" up -d
    cala_wait_http "$CALA_PANEL_LOCAL" 300 || cala_fail "the panel did not come back after the restart"
    cala_install_caddy
    cala_configure_caddy "$CALA_DOMAIN"
    if cala_wait_http "https://$CALA_DOMAIN" 90; then
      cala_ok "https://$CALA_DOMAIN answers"
    else
      cala_warn "https://$CALA_DOMAIN does not answer yet. Check DNS and ports 80/443, and: journalctl -u caddy --no-pager -n 80"
    fi
  else
    cala_compose_bind_public "$compose" || cala_fail "could not publish port 8000"
    cala_run "Publishing the panel on port 8000" cala_compose "$CALA_PANEL_DIR" up -d
    cala_wait_http "$CALA_PANEL_LOCAL" 300 || cala_fail "the panel did not come back after the restart"
    cala_ok "The panel listens on port 8000 on all addresses"
  fi
}

cala_panel_final_summary() {
  local mode="$1"
  cala_step "Done"
  if [[ "$CALA_CREATE_ADMIN" == no ]]; then
    cat <<EOF
  The panel runs, but only on 127.0.0.1:8000 until you create the administrator account:
    1. On your computer: ssh -N -L 127.0.0.1:8000:127.0.0.1:8000 <user>@$CALA_PUBLIC_IP
    2. Open http://localhost:8000, click Get Started and create your account. Set Application URL to
       $CALA_APP_URL and leave Enable Registration off.
    3. Make it reachable as in https://calagopus.com/docs/panel/installation/first-vps#_4-make-the-panel-reachable
EOF
  else
    cat <<EOF
  Panel:        $CALA_APP_URL
  Sign in as:   $CALA_ADMIN_USERNAME. The setup wizard resumes at Egg Repositories: Skip there and on
                Location, then Go to Dashboard.
EOF
    if [[ -z "$CALA_DOMAIN" ]]; then
      cat <<EOF
  Without HTTPS your password crosses the internet in plain text. Allow TCP 8000 in your provider's
  firewall (only from your IP if you can) and enable two-factor authentication under Account.
EOF
    fi
  fi
  cat <<EOF

  Files:        $CALA_PANEL_DIR (compose.yml, data/, postgres/)$([[ "$mode" == aio ]] && printf '\n                /etc/calagopus-wings and /var/lib/calagopus-wings (Wings config and game data)')
  Logs:         cd $CALA_PANEL_DIR && sudo docker compose logs --tail 80 web
  Update:       $CALA_ONE_LINER   (choose Update)

  ${C_BOLD}Back up $CALA_PANEL_DIR/compose.yml now.${C_RESET} It holds the encryption key; without it the stored secrets
  can't be decrypted. Keep a copy off this server, together with a database dump:
    https://calagopus.com/docs/panel/installation/first-vps#back-up-your-vps

  Next steps:
EOF
  if [[ "$mode" == aio ]]; then
    cat <<EOF
    - Admin -> Nodes -> Integrated Node: set Memory/Disk, then add an allocation (IP 0.0.0.0, alias
      $CALA_PUBLIC_IP, your game port).
    - Add an egg (Admin -> Egg Repositories) and create a server: https://calagopus.com/docs/panel/installation/first-vps
    - Open your game ports and 2022 (SFTP) in your provider's firewall.
EOF
  else
    cat <<EOF
    - Add a node: run this installer on the node host and choose "Wings node", then pair it under
      Admin -> Nodes -> Create -> Pair a Waiting Node.
    - Add an egg and a server: https://calagopus.com/docs/panel/installation/first-vps
EOF
  fi
  printf '\n  Log of this run: %s\n' "$CALA_LOG_FILE"
}
