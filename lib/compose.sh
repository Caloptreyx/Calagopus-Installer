# shellcheck shell=bash
# Compose files (download and edits), docker compose helpers, install state.

CALA_PANEL_COMPOSE_BASE="https://raw.githubusercontent.com/calagopus/panel/refs/heads/main"
CALA_WINGS_COMPOSE_URL="https://raw.githubusercontent.com/calagopus/wings/refs/heads/main/compose.local.yml"
CALA_STATE_FILE=".calagopus-installer.env"
CALA_REGISTRY="/etc/calagopus-installer/installs"

# cala_panel_compose_name MODE(aio|panel) HEAVY(yes|no)
cala_panel_compose_name() {
  case "$1:$2" in
    aio:no) printf compose.aio.yml ;;
    aio:yes) printf compose.heavy.aio.yml ;;
    panel:no) printf compose.yml ;;
    panel:yes) printf compose.heavy.yml ;;
    *) return 1 ;;
  esac
}

# --- edits (each one checks that it changed what it meant to) ------------------------------------

cala_compose_set_key() {
  local file="$1" key="$2"
  grep -q 'APP_ENCRYPTION_KEY=CHANGEME' "$file" || return 1
  sed -i "s/APP_ENCRYPTION_KEY=CHANGEME/APP_ENCRYPTION_KEY=$key/" "$file"
  grep -q "APP_ENCRYPTION_KEY=$key" "$file"
}

cala_compose_bind_loopback() {
  local file="$1"
  sed -i -E 's/^([[:space:]]*-[[:space:]]*)8000:8000([[:space:]]|$)/\1127.0.0.1:8000:8000\2/' "$file"
  grep -qE '^[[:space:]]*-[[:space:]]*127\.0\.0\.1:8000:8000([[:space:]]|$)' "$file"
}

cala_compose_bind_public() {
  local file="$1"
  sed -i -E 's/^([[:space:]]*-[[:space:]]*)127\.0\.0\.1:8000:8000([[:space:]]|$)/\18000:8000\2/' "$file"
  grep -qE '^[[:space:]]*-[[:space:]]*8000:8000([[:space:]]|$)' "$file"
}

cala_compose_is_loopback() {
  grep -qE '^[[:space:]]*-[[:space:]]*127\.0\.0\.1:8000:8000([[:space:]]|$)' "$1"
}

# Sets TZ in list form (- TZ=Europe/Berlin) and map form (TZ: Europe/Berlin or TZ: "Europe/Berlin").
cala_compose_set_timezone() {
  local file="$1" tz="$2"
  sed -i -E \
    -e "s#^([[:space:]]*-[[:space:]]*TZ=)[A-Za-z0-9_/+-]+#\\1$tz#" \
    -e "s#^([[:space:]]*TZ:[[:space:]]*\"?)[A-Za-z0-9_/+-]+#\\1$tz#" "$file"
  grep -qE "TZ(=|:[[:space:]]*\"?)$tz" "$file"
}

# Sets KEY=VALUE in the web service's environment list, after APP_ENCRYPTION_KEY like the docs do.
cala_compose_set_env() {
  local file="$1" key="$2" value="$3"
  if grep -qE "^[[:space:]]*-[[:space:]]*$key=" "$file"; then
    sed -i -E "s#^([[:space:]]*-[[:space:]]*$key=).*#\\1$value#" "$file"
  else
    awk -v line="$key=$value" '
      { print }
      /^[[:space:]]*-[[:space:]]*APP_ENCRYPTION_KEY=/ && !done {
        match($0, /^[[:space:]]*-[[:space:]]*/)
        print substr($0, 1, RLENGTH) line
        done = 1
      }
    ' "$file" >"$file.tmp"
    cat "$file.tmp" >"$file"
    rm -f "$file.tmp"
  fi
  grep -qE "^[[:space:]]*-[[:space:]]*$key=$value\$" "$file"
}

# Adds map-form environment variables to the wings service, after WINGS_USERNAME.
cala_wings_compose_set_enroll() {
  local file="$1" url="$2" code="$3"
  awk -v url="$url" -v code="$code" '
    { print }
    /^[[:space:]]*WINGS_USERNAME:/ && !done {
      match($0, /^[[:space:]]*/)
      indent = substr($0, 1, RLENGTH)
      print indent "WINGS_ENROLL_PANEL_URL: \"" url "\""
      print indent "WINGS_ENROLL_CODE: \"" code "\""
      done = 1
    }
  ' "$file" >"$file.tmp"
  cat "$file.tmp" >"$file"
  rm -f "$file.tmp"
  grep -q 'WINGS_ENROLL_CODE:' "$file"
}

cala_wings_compose_remove_enroll() {
  sed -i -E '/^[[:space:]]*WINGS_ENROLL_(PANEL_URL|CODE):/d' "$1"
}

# Prints the panel image of a compose file (calagopus/panel:aio, ghcr.io/calagopus/panel:heavy, ...).
cala_compose_panel_image() {
  awk '$1 == "image:" && $2 ~ /calagopus\/panel:/ { print $2; exit }' "$1"
}

cala_compose_is_heavy() {
  local file="$1"
  [[ "$(cala_compose_panel_image "$file")" == *heavy* ]] && grep -q ':/app/extensions' "$file"
}

cala_compose_is_aio() {
  [[ "$(cala_compose_panel_image "$1")" == *aio* ]]
}

# --- docker compose ------------------------------------------------------------------------------

cala_compose() {
  local dir="$1"
  shift
  (cd "$dir" && docker compose "$@")
}

# Waits until URL answers with any HTTP status. cala_wait_http URL TIMEOUT_SECONDS
cala_wait_http() {
  local url="$1" timeout="$2" waited=0 code
  while ((waited < timeout)); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != 000 ]]; then
      return 0
    fi
    sleep 3
    waited=$((waited + 3))
    if ((waited % 60 == 0)); then
      cala_info "still waiting for $url (${waited}s)"
    fi
  done
  return 1
}

cala_compose_logs_to_log() {
  local dir="$1"
  cala_log "docker compose ps / logs for $dir:"
  cala_compose "$dir" ps >>"${CALA_LOG_FILE:-/dev/null}" 2>&1 || true
  cala_compose "$dir" logs --tail 80 >>"${CALA_LOG_FILE:-/dev/null}" 2>&1 || true
}

# --- install state -------------------------------------------------------------------------------

# cala_write_state DIR KEY=VALUE ...
cala_write_state() {
  local dir="$1"
  shift
  printf '%s\n' "$@" >"$dir/$CALA_STATE_FILE"
  chmod 600 "$dir/$CALA_STATE_FILE"
  mkdir -p "$(dirname "$CALA_REGISTRY")"
  touch "$CALA_REGISTRY"
  grep -qxF "$dir" "$CALA_REGISTRY" || printf '%s\n' "$dir" >>"$CALA_REGISTRY"
}

cala_state_value() {
  local file="$1/$CALA_STATE_FILE"
  [[ -r "$file" ]] || return 0
  cala_os_release_value "$file" "$2"
}

cala_unregister() {
  local dir="$1"
  [[ -f "$CALA_REGISTRY" ]] || return 0
  grep -vxF "$dir" "$CALA_REGISTRY" >"$CALA_REGISTRY.tmp" || true
  cat "$CALA_REGISTRY.tmp" >"$CALA_REGISTRY"
  rm -f "$CALA_REGISTRY.tmp"
}

# Prints "kind dir" for every install found: kind is aio, panel or wings.
cala_find_installs() {
  local candidates=() dir kind seen=" "
  [[ -f "$CALA_REGISTRY" ]] && mapfile -t candidates <"$CALA_REGISTRY"
  candidates+=(/opt/calagopus-panel /opt/calagopus-wings)
  [[ -n "${CALA_PANEL_DIR:-}" ]] && candidates+=("$CALA_PANEL_DIR")
  [[ -n "${CALA_WINGS_DIR:-}" ]] && candidates+=("$CALA_WINGS_DIR")
  for dir in "${candidates[@]}"; do
    [[ -n "$dir" && -f "$dir/compose.yml" && "$seen" != *" $dir "* ]] || continue
    seen+="$dir "
    kind="$(cala_state_value "$dir" MODE)"
    if [[ -z "$kind" ]]; then
      if grep -q 'calagopus/wings:' "$dir/compose.yml"; then
        kind=wings
      elif cala_compose_is_aio "$dir/compose.yml"; then
        kind=aio
      elif [[ -n "$(cala_compose_panel_image "$dir/compose.yml")" ]]; then
        kind=panel
      else
        continue
      fi
    fi
    printf '%s %s\n' "$kind" "$dir"
  done
}
