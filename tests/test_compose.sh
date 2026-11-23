# shellcheck shell=bash
# Compose edits against copies of the upstream compose files (tests/fixtures), Caddyfile handling, state.

fixture() {
  cp "$FIXTURES/$1" "$WORK/$1"
  printf '%s' "$WORK/$1"
}

test_compose_names() {
  assert_eq "$(cala_panel_compose_name aio no)" compose.aio.yml
  assert_eq "$(cala_panel_compose_name aio yes)" compose.heavy.aio.yml
  assert_eq "$(cala_panel_compose_name panel no)" compose.yml
  assert_eq "$(cala_panel_compose_name panel yes)" compose.heavy.yml
  assert_fails cala_panel_compose_name wings no
}

test_compose_key_and_loopback() {
  local name file
  for name in compose.aio.yml compose.heavy.aio.yml compose.yml compose.heavy.yml; do
    file="$(fixture "$name")"
    assert_ok cala_compose_set_key "$file" 0123456789abcdef0123456789abcdef
    assert_file_contains "$file" '- APP_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef$'
    assert_file_lacks "$file" CHANGEME
    assert_fails cala_compose_set_key "$file" ffff
    assert_ok cala_compose_bind_loopback "$file"
    assert_ok cala_compose_is_loopback "$file"
    assert_file_contains "$file" '^      - 127\.0\.0\.1:8000:8000$'
    assert_ok cala_compose_bind_public "$file"
    assert_fails cala_compose_is_loopback "$file"
    assert_file_contains "$file" '^      - 8000:8000$'
  done
  file="$(fixture compose.aio.yml)"
  cala_compose_bind_loopback "$file"
  assert_file_contains "$file" '- 2022:2022 # sftp'
}

test_compose_timezone() {
  local file
  file="$(fixture compose.aio.yml)"
  assert_ok cala_compose_set_timezone "$file" America/New_York
  assert_file_lacks "$file" Europe/Berlin
  assert_eq "$(grep -c 'America/New_York' "$file")" 3
  file="$(fixture wings.compose.local.yml)"
  assert_ok cala_compose_set_timezone "$file" UTC
  assert_file_contains "$file" 'TZ: "UTC"'
}

test_compose_trusted_proxies_after_key() {
  local file
  file="$(fixture compose.aio.yml)"
  assert_ok cala_compose_set_env "$file" APP_TRUSTED_PROXIES 172.18.0.1
  assert_eq "$(grep -A1 'APP_ENCRYPTION_KEY=' "$file" | tail -n1)" "      - APP_TRUSTED_PROXIES=172.18.0.1"
  assert_ok cala_compose_set_env "$file" APP_TRUSTED_PROXIES 172.19.0.1
  assert_eq "$(grep -c APP_TRUSTED_PROXIES "$file")" 1
  assert_file_contains "$file" 'APP_TRUSTED_PROXIES=172\.19\.0\.1$'
}

test_compose_image_detection() {
  assert_eq "$(cala_compose_panel_image "$FIXTURES/compose.aio.yml")" calagopus/panel:aio
  assert_ok cala_compose_is_aio "$FIXTURES/compose.aio.yml"
  assert_ok cala_compose_is_aio "$FIXTURES/compose.heavy.aio.yml"
  assert_fails cala_compose_is_aio "$FIXTURES/compose.heavy.yml"
  assert_ok cala_compose_is_heavy "$FIXTURES/compose.heavy.yml"
  assert_ok cala_compose_is_heavy "$FIXTURES/compose.heavy.aio.yml"
  assert_fails cala_compose_is_heavy "$FIXTURES/compose.aio.yml"
  local file
  file="$(fixture compose.aio.yml)"
  sed -i 's#calagopus/panel:aio#calagopus/panel:heavy-aio#' "$file"
  assert_fails cala_compose_is_heavy "$file" # retagged without the extension mounts
}

test_wings_enrollment_vars() {
  local file
  file="$(fixture wings.compose.local.yml)"
  assert_ok cala_wings_compose_set_enroll "$file" https://panel.example.com Code_123
  assert_eq "$(grep -A2 'WINGS_USERNAME:' "$file" | tail -n2)" "$(printf '      WINGS_ENROLL_PANEL_URL: "https://panel.example.com"\n      WINGS_ENROLL_CODE: "Code_123"')"
  cala_wings_compose_remove_enroll "$file"
  assert_file_lacks "$file" WINGS_ENROLL
  assert_eq "$(cat "$file")" "$(cat "$FIXTURES/wings.compose.local.yml")"
}

test_caddyfile_handling() {
  local file="$WORK/Caddyfile" CALA_CADDY_MARKER="# Managed by Calagopus-Installer"
  printf ':80 {\n\troot * /usr/share/caddy\n\tfile_server\n}\n' >"$file"
  assert_ok cala_caddyfile_is_default "$file"
  {
    printf 'other.example.com {\n    reverse_proxy 127.0.0.1:3000\n}\n\n'
    cala_caddy_site panel.example.com
  } >"$file"
  assert_fails cala_caddyfile_is_default "$file"
  assert_file_contains "$file" '^panel\.example\.com \{$'
  assert_file_contains "$file" 'reverse_proxy 127\.0\.0\.1:8000'
  cala_caddyfile_without_ours "$file" >"$WORK/Caddyfile.out"
  assert_file_lacks "$WORK/Caddyfile.out" 'panel\.example\.com|request_body|127\.0\.0\.1:8000'
  assert_file_contains "$WORK/Caddyfile.out" 'reverse_proxy 127\.0\.0\.1:3000'
  assert_eq "$(grep -c '}' "$WORK/Caddyfile.out")" 1
}

test_state_and_find_installs() {
  local CALA_REGISTRY="$WORK/registry" panel="$WORK/panel" wings="$WORK/wings" out
  mkdir -p "$panel" "$wings"
  cp "$FIXTURES/compose.aio.yml" "$panel/compose.yml"
  cp "$FIXTURES/wings.compose.local.yml" "$wings/compose.yml"
  cala_write_state "$panel" MODE=aio DOMAIN=panel.example.com
  cala_write_state "$panel" MODE=aio DOMAIN=panel.example.com
  assert_eq "$(grep -c . "$CALA_REGISTRY")" 1
  assert_eq "$(cala_state_value "$panel" DOMAIN)" panel.example.com
  printf '%s\n' "$wings" >>"$CALA_REGISTRY"
  out="$(cala_find_installs)"
  assert_contains "$out" "aio $panel"
  assert_contains "$out" "wings $wings"
  cala_unregister "$panel"
  assert_eq "$(cat "$CALA_REGISTRY")" "$wings"
}

test_uninstall_data_paths() {
  assert_eq "$(cala_data_paths panel /opt/calagopus-panel)" /opt/calagopus-panel
  assert_contains "$(cala_data_paths aio /opt/calagopus-panel)" /var/lib/calagopus-wings
  assert_contains "$(cala_data_paths aio /opt/calagopus-panel)" /etc/calagopus-wings
  assert_eq "$(cala_data_paths wings /opt/w)" "$(printf '/opt/w\n/var/lib/calagopus-wings')"
}
