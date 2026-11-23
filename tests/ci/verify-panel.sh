#!/usr/bin/env bash
# CI: checks a finished AIO/panel install. Run as root with the same CALA_* variables the install used.
set -euo pipefail

dir="${CALA_PANEL_DIR:-/opt/calagopus-panel}"
base=http://127.0.0.1:8000
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$(stat -c %a "$dir/compose.yml")" == 600 ]] || fail "compose.yml is not mode 600"
grep -q 'APP_ENCRYPTION_KEY=[0-9a-f]\{32\}$' "$dir/compose.yml" || fail "no generated 32-hex-character encryption key"
grep -q CHANGEME "$dir/compose.yml" && fail "CHANGEME left in compose.yml"
grep -qE '^\s*-\s*8000:8000' "$dir/compose.yml" || fail "port 8000 was not opened after the admin was created"
ss -Hltn 'sport = :8000' | grep -qE '0\.0\.0\.0:8000|\*:8000|\[::\]:8000' || fail "nothing listens publicly on 8000"
echo "ok: compose.yml (mode 600, key, port 8000 published)"

settings="$(curl -fsS "$base/api/settings")"
url="$(jq -r '.app.url' <<<"$settings")"
[[ "$url" == "http://${CALA_PUBLIC_IP:-}"*":8000" || "$url" == https://* ]] || fail "unexpected Application URL $url"
jq -e '.app.registration_enabled == false' <<<"$settings" >/dev/null || fail "public registration is still on"
jq -e '.oobe_step == "repositories"' <<<"$settings" >/dev/null || fail "setup wizard not at Egg Repositories: $(jq -r .oobe_step <<<"$settings")"
echo "ok: Application URL $url, registration off, wizard at repositories"

jq -n --arg u "$CALA_ADMIN_USERNAME" --arg p "$CALA_ADMIN_PASSWORD" '{user: $u, password: $p}' |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$base/api/auth/login" >/tmp/login.json ||
  fail "login as $CALA_ADMIN_USERNAME failed"
jq -e '.type == "completed" and .user.admin == true' /tmp/login.json >/dev/null || fail "login did not return an admin: $(cat /tmp/login.json)"
echo "ok: $CALA_ADMIN_USERNAME logs in and is an administrator"

code="$(jq -n '{username: "intruder", email: "intruder@example.com", password: "intruder-password"}' |
  curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$base/api/auth/register")"
[[ "$code" == 400 ]] || fail "registration of a second account returned HTTP $code"
echo "ok: registering another account is refused"

grep -q "^MODE=" "$dir/.calagopus-installer.env" || fail "no installer state file"
grep -qxF "$dir" /etc/calagopus-installer/installs || fail "install not in the registry"
echo "ok: state file and registry"
