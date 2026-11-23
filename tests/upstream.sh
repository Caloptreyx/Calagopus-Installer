#!/usr/bin/env bash
# Applies the installer's compose edits to the live upstream compose files, so CI notices when
# calagopus/panel or calagopus/wings change a line the installer relies on. Needs network.
set -euo pipefail

CALA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/core.sh
source "$CALA_ROOT/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "$CALA_ROOT/lib/checks.sh"
# shellcheck source=../lib/compose.sh
source "$CALA_ROOT/lib/compose.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

check() {
  if "$@"; then
    printf '  ok   %s\n' "${*:1:1} ${2##*/}"
  else
    printf '  FAIL %s\n' "$*"
    failed=1
  fi
}

for name in compose.aio.yml compose.heavy.aio.yml compose.yml compose.heavy.yml; do
  file="$work/$name"
  curl -fsSL --retry 3 "$CALA_PANEL_COMPOSE_BASE/$name" -o "$file"
  check cala_compose_set_key "$file" 0123456789abcdef0123456789abcdef
  check cala_compose_bind_loopback "$file"
  check cala_compose_bind_public "$file"
  check cala_compose_set_timezone "$file" UTC
  check cala_compose_set_env "$file" APP_TRUSTED_PROXIES 172.18.0.1
  [[ -n "$(cala_compose_panel_image "$file")" ]] || {
    echo "  FAIL no calagopus/panel image in $name"
    failed=1
  }
  case "$name" in
    *heavy*) check cala_compose_is_heavy "$file" ;;
  esac
  case "$name" in
    *aio*) check cala_compose_is_aio "$file" ;;
  esac
done

file="$work/wings.yml"
curl -fsSL --retry 3 "$CALA_WINGS_COMPOSE_URL" -o "$file"
check cala_compose_set_timezone "$file" UTC
check cala_wings_compose_set_enroll "$file" https://panel.example.com code123
if ! grep -q '8080:8080' "$file" || ! grep -q '2022:2022' "$file" || ! grep -q './config/:/etc/calagopus-wings/' "$file"; then
  echo "  FAIL wings compose no longer publishes 8080/2022 or mounts ./config"
  failed=1
fi

exit "$failed"
