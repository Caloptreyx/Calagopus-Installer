# shellcheck shell=bash
# Update: pull new images and recreate the containers, keeping compose.yml (and its key) and all data.
# https://calagopus.com/docs/panel/installation/first-vps#updating-later

# Lets the user pick one of the installs found, or all. Fills CALA_TARGETS with "kind dir" entries.
cala_pick_installs() {
  local purpose="$1" installs=() options=() line i
  mapfile -t installs < <(cala_find_installs)
  ((${#installs[@]} > 0)) || cala_die "no Calagopus install found (looked in /opt/calagopus-panel, /opt/calagopus-wings and $CALA_REGISTRY; set CALA_PANEL_DIR or CALA_WINGS_DIR)"
  CALA_TARGETS=("${installs[@]}")
  ((${#installs[@]} > 1)) || return 0
  for i in "${!installs[@]}"; do
    line="${installs[$i]}"
    options+=("$i|${line%% *} in ${line#* }")
  done
  options+=("all|all of them")
  local CALA_PICK
  cala_choose CALA_PICK "Which install do you want to $purpose?" all "${options[@]}"
  [[ "$CALA_PICK" == all ]] || CALA_TARGETS=("${installs[$CALA_PICK]}")
}

cala_backup_database() {
  local dir="$1" file
  if [[ -z "$(cala_compose "$dir" ps -q --status running db 2>/dev/null)" ]]; then
    cala_warn "the database container is not running, so no backup was taken"
    return 0
  fi
  mkdir -p "$dir/backups"
  chmod 700 "$dir/backups"
  file="$dir/backups/panel-$(date +%Y%m%d-%H%M%S).backup"
  install -m 600 /dev/null "$file"
  if cala_compose "$dir" exec -T db pg_dump -U panel -d panel -F c >"$file" 2>>"${CALA_LOG_FILE:-/dev/null}"; then
    cala_ok "Database backed up to $file ($(du -h "$file" | cut -f1))"
  else
    rm -f "$file"
    cala_fail "the database backup failed; nothing was updated (set CALA_UPDATE_BACKUP=no to update without one)"
  fi
}

cala_update_one() {
  local kind="$1" dir="$2"
  cala_step "Updating $kind in $dir"
  if [[ "$kind" != wings ]]; then
    cala_ask_yes_no CALA_UPDATE_BACKUP "Back up the database before updating?" y
    if [[ "$CALA_UPDATE_BACKUP" == yes ]]; then
      cala_backup_database "$dir"
    fi
  fi
  cala_run "Pulling new images" cala_compose "$dir" pull
  cala_run "Recreating the containers" cala_compose "$dir" up -d
  if [[ "$kind" == wings ]]; then
    sleep 3
    [[ -n "$(cala_compose "$dir" ps -q --status running wings)" ]] || {
      cala_compose_logs_to_log "$dir"
      cala_fail "Wings is not running after the update"
    }
    cala_ok "Wings updated and running"
    return 0
  fi
  cala_info "Waiting for the panel on 127.0.0.1:8000 (database migrations run first)"
  if ! cala_wait_http "$CALA_PANEL_LOCAL" "${CALA_PANEL_TIMEOUT:-900}"; then
    cala_compose_logs_to_log "$dir"
    cala_fail "the panel did not answer after the update"
  fi
  cala_compose "$dir" ps >>"${CALA_LOG_FILE:-/dev/null}" 2>&1 || true
  cala_ok "Panel updated and answering"
  if cala_compose_is_heavy "$dir/compose.yml" && compgen -G "$dir/build/extensions/*.c7s.zip" >/dev/null; then
    cala_info "Extensions are compiled again against the new version in the background (several minutes)."
    cala_info "Progress: Admin -> Extensions. Read the release notes in case an extension needs an update first."
  fi
}

cala_update() {
  cala_step "Update"
  cala_info "Read the release notes first: https://calagopus.com/docs/releases"
  local target
  cala_pick_installs update
  cala_confirm_start
  if cala_truthy "${CALA_DRY_RUN:-no}"; then
    cala_ok "Dry run: would update ${CALA_TARGETS[*]}"
    return 0
  fi
  cala_docker_ready || cala_die "Docker is not running"
  for target in "${CALA_TARGETS[@]}"; do
    cala_update_one "${target%% *}" "${target#* }"
  done
  cala_step "Done"
  cala_info "Updated. Your compose.yml files and data were kept."
}
