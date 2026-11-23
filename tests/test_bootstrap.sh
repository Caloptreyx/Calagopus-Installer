# shellcheck shell=bash
# The one-liner's bootstrapper: which tarball it downloads, with a fake curl that serves a stub installer.

# bootstrap_run [VAR=value...]: runs install.sh alone (no lib/ beside it, as the one-liner does) with the
# arguments "aio --dry-run"; prints the requested URL, then the stub installer's output.
bootstrap_run() {
  local dir="$WORK/bootstrap"
  rm -rf "$dir" && mkdir -p "$dir/bin" "$dir/alone" "$dir/stub/Calagopus-Installer-x"
  cp "$CALA_ROOT/install.sh" "$dir/alone/install.sh"
  cat >"$dir/stub/Calagopus-Installer-x/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "stub bootstrapped=$CALA_BOOTSTRAPPED args=$*"
EOF
  tar -czf "$dir/stub.tar.gz" -C "$dir/stub" Calagopus-Installer-x
  cat >"$dir/bin/curl" <<EOF
#!/usr/bin/env bash
echo "url \${*: -1}" >&2
cat "$dir/stub.tar.gz"
EOF
  chmod +x "$dir/bin/curl"
  env "$@" PATH="$dir/bin:$PATH" bash "$dir/alone/install.sh" aio --dry-run 2>&1
}

test_bootstrap_default_ref_is_own_release_tag() {
  local version out
  version="$(sed -n 's/^CALA_INSTALLER_VERSION="\(.*\)"$/\1/p' "$CALA_ROOT/install.sh")"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || fail "no version in install.sh: '$version'"
  out="$(bootstrap_run -u CALA_INSTALLER_REF)"
  assert_contains "$out" "url https://codeload.github.com/Caloptreyx/Calagopus-Installer/tar.gz/v$version"
  assert_contains "$out" "stub bootstrapped=1 args=aio --dry-run"
}

test_bootstrap_ref_override() {
  local out
  out="$(bootstrap_run CALA_INSTALLER_REF=main)"
  assert_contains "$out" "url https://codeload.github.com/Caloptreyx/Calagopus-Installer/tar.gz/main"
  assert_contains "$out" "stub bootstrapped=1"
  out="$(bootstrap_run 'CALA_INSTALLER_REF=main;rm')" && fail "invalid ref accepted"
  assert_contains "$out" "invalid value"
}
