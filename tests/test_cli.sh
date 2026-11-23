# shellcheck shell=bash
# shellcheck disable=SC2030,SC2031,SC2153 # values are set inside $(...) on purpose
# Option parsing and the prompt helpers in non-interactive mode.

test_option_names() {
  assert_eq "$(cala_option_name --panel-dir)" PANEL_DIR
  assert_eq "$(cala_option_name --domain)" DOMAIN
  assert_ok cala_is_setting ADMIN_PASSWORD
  assert_fails cala_is_setting NOPE
}

test_parse_args() {
  local out
  out="$(
    unset CALA_DOMAIN CALA_ACTION
    cala_parse_args wings --domain panel.example.com --game-ports=25565,25566 -y
    printf '%s|%s|%s|%s' "$CALA_ACTION" "$CALA_DOMAIN" "$CALA_GAME_PORTS" "$CALA_NONINTERACTIVE"
  )"
  assert_eq "$out" "wings|panel.example.com|25565,25566|1"
  out="$(cala_parse_args --bogus x 2>&1)" && fail "unknown option accepted"
  assert_contains "$out" "unknown option --bogus"
  out="$(cala_parse_args --domain 2>&1)" && fail "missing value accepted"
  out="$(cala_parse_args --version)"
  assert_contains "$out" "Calagopus-Installer"
  out="$(cala_parse_args --help)"
  assert_contains "$out" CALA_EXTENSIONS
}

test_every_setting_is_documented() {
  local help setting
  help="$(cala_usage)"
  for setting in "${CALA_SETTINGS[@]}"; do
    case "$setting" in
      NONINTERACTIVE | DRY_RUN) continue ;;
    esac
    [[ "$help" == *"CALA_$setting"* ]] || fail "CALA_$setting is missing from --help"
  done
}

test_ask_noninteractive() {
  local out
  out="$(
    CALA_INTERACTIVE=0
    CALA_X=panel.example.com
    cala_ask CALA_X "Domain" "" cala_valid_domain_or_empty "a domain"
    printf '%s' "$CALA_X"
  )"
  assert_eq "$out" panel.example.com
  out="$(
    CALA_INTERACTIVE=0
    unset CALA_X
    cala_ask CALA_X "Domain" "" cala_valid_domain_or_empty "a domain"
    printf '[%s]' "$CALA_X"
  )"
  assert_eq "$out" "[]"
  out="$(
    CALA_INTERACTIVE=0
    unset CALA_X
    cala_ask CALA_X "Dir" /opt/calagopus-panel cala_valid_install_dir "a dir"
    printf '%s' "$CALA_X"
  )"
  assert_eq "$out" /opt/calagopus-panel
  out="$(
    CALA_INTERACTIVE=0
    unset CALA_X
    cala_ask CALA_X "Email" "" cala_valid_email "an email address" 2>&1
  )" && fail "missing required value accepted"
  assert_contains "$out" "CALA_X is required"
  out="$(
    CALA_INTERACTIVE=0
    CALA_X="not an email"
    cala_ask CALA_X "Email" "" cala_valid_email "an email address" 2>&1
  )" && fail "invalid value accepted"
}

test_ask_yes_no_and_choose() {
  local out
  out="$(
    CALA_INTERACTIVE=0
    CALA_Y=TRUE
    cala_ask_yes_no CALA_Y "Q" n
    unset CALA_Z
    cala_ask_yes_no CALA_Z "Q" y
    printf '%s %s' "$CALA_Y" "$CALA_Z"
  )"
  assert_eq "$out" "yes yes"
  out="$(
    CALA_INTERACTIVE=0
    CALA_Y=maybe
    cala_ask_yes_no CALA_Y "Q" n 2>&1
  )" && fail "maybe accepted"
  out="$(
    CALA_INTERACTIVE=0
    unset CALA_C
    cala_choose CALA_C "Q" aio "aio|A" "panel|P"
    printf '%s' "$CALA_C"
  )"
  assert_eq "$out" aio
  out="$(
    CALA_INTERACTIVE=0
    CALA_C=nope
    cala_choose CALA_C "Q" aio "aio|A" "panel|P" 2>&1
  )" && fail "unknown choice accepted"
}

test_secret_required_noninteractive() {
  local out
  out="$(
    CALA_INTERACTIVE=0
    unset CALA_P
    cala_ask_secret CALA_P "Password" cala_valid_password "8+ characters" 2>&1
  )" && fail "missing password accepted"
  assert_contains "$out" "CALA_P is required"
  out="$(
    CALA_INTERACTIVE=0
    CALA_P=short
    cala_ask_secret CALA_P "Password" cala_valid_password "8+ characters" 2>&1
  )" && fail "short password accepted"
  [[ "$out" != *short* ]] || fail "the password was echoed in the error"
}
