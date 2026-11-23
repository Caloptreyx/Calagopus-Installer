# shellcheck shell=bash
# Uninstall: stop and remove the containers; optionally delete all data after a second, typed confirmation.

# Prints the paths that hold data for an install: cala_data_paths KIND DIR
cala_data_paths() {
  local kind="$1" dir="$2"
  printf '%s\n' "$dir"
  case "$kind" in
    aio) printf '%s\n' /etc/calagopus-wings /var/lib/calagopus-wings /var/log/calagopus-wings ;;
    wings) printf '%s\n' /var/lib/calagopus-wings ;;
  esac
}

cala_uninstall_one() {
  local kind="$1" dir="$2" remove_data="$3" domain
  cala_step "Uninstalling $kind in $dir"
  domain="$(cala_state_value "$dir" DOMAIN)"
  if [[ "$remove_data" == yes ]]; then
    cala_run "Stopping and removing the containers and their images" cala_compose "$dir" down --remove-orphans --rmi all
  else
    cala_run "Stopping and removing the containers" cala_compose "$dir" down --remove-orphans
  fi
  if [[ -n "$domain" ]]; then
    cala_remove_caddy_site
  fi
  if [[ "$remove_data" == yes ]]; then
    local path
    while IFS= read -r path; do
      [[ -n "$path" && "$path" != / && -e "$path" ]] || continue
      rm -rf --one-file-system "$path"
      cala_ok "Deleted $path"
    done < <(cala_data_paths "$kind" "$dir")
    cala_unregister "$dir"
  else
    cala_ok "Containers removed. Data kept in $dir$([[ "$kind" != panel ]] && printf ' and /var/lib/calagopus-wings')"
    cala_info "To start it again: cd $dir && sudo docker compose up -d"
  fi
  if [[ "$kind" != panel ]]; then
    cala_info "Game server containers that Wings created are not removed; list them with: docker ps -a"
  fi
}

cala_uninstall() {
  cala_step "Uninstall"
  cala_pick_installs uninstall
  local target

  cala_warn "This stops and removes the Calagopus containers of: ${CALA_TARGETS[*]}"
  cala_ask_yes_no CALA_UNINSTALL_CONFIRM "Uninstall?" n
  [[ "$CALA_UNINSTALL_CONFIRM" == yes ]] || cala_die "cancelled, nothing was changed (without prompts, set CALA_UNINSTALL_CONFIRM=yes)"

  cala_info "Data: the database, panel files, compose.yml with the encryption key, Wings' configuration and"
  cala_info "every game server's files. Without it, a reinstall starts from scratch."
  cala_ask_yes_no CALA_REMOVE_DATA "Also DELETE all data? This cannot be undone." n
  if [[ "$CALA_REMOVE_DATA" == yes ]]; then
    cala_warn "These paths will be deleted permanently:"
    for target in "${CALA_TARGETS[@]}"; do
      cala_data_paths "${target%% *}" "${target#* }" | sed 's/^/      /' >&2
    done
    cala_ask CALA_REMOVE_DATA_CONFIRM "Type DELETE to confirm" "" cala_is_delete "the word DELETE"
  fi

  if cala_truthy "${CALA_DRY_RUN:-no}"; then
    cala_ok "Dry run: would uninstall ${CALA_TARGETS[*]} (delete data: $CALA_REMOVE_DATA)"
    return 0
  fi
  for target in "${CALA_TARGETS[@]}"; do
    cala_uninstall_one "${target%% *}" "${target#* }" "$CALA_REMOVE_DATA"
  done
  cala_step "Done"
  cala_info "Docker, Caddy's package and firewall rules were left in place."
}

cala_is_delete() {
  [[ "$1" == DELETE ]]
}
