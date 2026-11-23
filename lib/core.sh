# shellcheck shell=bash
# Output, logging, error handling, prompts and option parsing. Sourcing this file has no side effects.

CALA_DOCS_TROUBLESHOOTING="https://calagopus.com/docs/additional/troubleshooting"
CALA_ONE_LINER="bash <(curl -sSL https://install.caloptreyx.com)"
CALA_ONE_LINER_FALLBACK="bash <(curl -sSL https://raw.githubusercontent.com/Caloptreyx/Calagopus-Installer/main/install.sh)"

# Every setting the installer reads. `--some-name value` on the command line sets CALA_SOME_NAME.
CALA_SETTINGS=(
  ACTION NONINTERACTIVE DRY_RUN LOG_FILE
  PANEL_DIR WINGS_DIR TIMEZONE PUBLIC_IP
  DOMAIN IGNORE_DNS
  CREATE_ADMIN ADMIN_EMAIL ADMIN_USERNAME ADMIN_PASSWORD
  FIREWALL SSH_PORT GAME_PORTS
  EXTENSIONS THEME LOW_MEMORY_OK EXTENSION_TIMEOUT
  WINGS_PANEL_URL WINGS_ENROLL_CODE
  UPDATE_BACKUP
  UNINSTALL_CONFIRM REMOVE_DATA REMOVE_DATA_CONFIRM
  SKIP_OS_CHECK SKIP_REQUIREMENTS PANEL_TIMEOUT INSTALLER_REF
)

CALA_INTERACTIVE=0
CALA_TMP=""

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_CYAN=$'\e[36m'
else
  C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
fi

# --- logging and output --------------------------------------------------------------------------

cala_log() {
  if [[ -n "${CALA_LOG_FILE:-}" && -w "${CALA_LOG_FILE}" ]]; then
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$CALA_LOG_FILE"
  fi
  return 0
}

cala_print() {
  printf '%s\n' "$*"
  cala_log "$*"
}

cala_step() {
  printf '\n%s==> %s%s\n' "$C_BOLD$C_CYAN" "$*" "$C_RESET"
  cala_log "==> $*"
}

cala_info() {
  printf '  %s\n' "$*"
  cala_log "INFO $*"
}

cala_ok() {
  printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"
  cala_log "OK   $*"
}

cala_warn() {
  printf '  %s! %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2
  cala_log "WARN $*"
}

cala_error() {
  printf '%sError: %s%s\n' "$C_RED$C_BOLD" "$*" "$C_RESET" >&2
  cala_log "ERROR $*"
}

cala_log_tail() {
  if [[ -n "${CALA_LOG_FILE:-}" && -r "${CALA_LOG_FILE}" ]]; then
    printf '\nLast lines of %s:\n' "$CALA_LOG_FILE" >&2
    tail -n "${1:-25}" "$CALA_LOG_FILE" | sed 's/^/  | /' >&2
  fi
}

cala_help_footer() {
  printf '\nFull log: %s\nTroubleshooting: %s\n' "${CALA_LOG_FILE:-not written}" "$CALA_DOCS_TROUBLESHOOTING" >&2
}

# Stops the installer with a message. Use for expected failures (bad input, unsupported system).
cala_die() {
  cala_error "$*"
  exit 1
}

# Stops the installer after a command failed, with the log tail and where to get help.
cala_fail() {
  cala_error "$*"
  cala_log_tail 25
  cala_help_footer
  exit 1
}

cala_on_error() {
  local code="$1" line="$2" command="$3"
  trap - ERR
  cala_error "unexpected failure (exit $code) at line $line: $command"
  cala_log_tail 25
  cala_help_footer
  exit "$code"
}

cala_cleanup() {
  if [[ -n "$CALA_TMP" && -d "$CALA_TMP" ]]; then
    rm -rf "$CALA_TMP"
  fi
  return 0
}

# Runs a command with its output in the log only. The description is shown and logged, the arguments are not
# (they can hold secrets).
cala_run() {
  local description="$1"
  shift
  cala_info "$description"
  cala_log "RUN  $description"
  if ! "$@" >>"${CALA_LOG_FILE:-/dev/null}" 2>&1; then
    cala_fail "$description failed"
  fi
}

cala_init_log() {
  CALA_LOG_FILE="${CALA_LOG_FILE:-/var/log/calagopus-installer.log}"
  mkdir -p "$(dirname "$CALA_LOG_FILE")"
  touch "$CALA_LOG_FILE"
  chmod 600 "$CALA_LOG_FILE"
  cala_log "---- Calagopus-Installer ${CALA_INSTALLER_VERSION:-?} started: $*"
}

cala_init_tmp() {
  CALA_TMP="$(mktemp -d /tmp/calagopus-installer.XXXXXX)"
  chmod 700 "$CALA_TMP"
}

# --- option parsing ------------------------------------------------------------------------------

cala_is_setting() {
  local name="$1" setting
  for setting in "${CALA_SETTINGS[@]}"; do
    if [[ "$setting" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

# Turns `--panel-dir` into `PANEL_DIR`.
cala_option_name() {
  local raw="${1#--}"
  raw="${raw//-/_}"
  printf '%s' "${raw^^}"
}

cala_parse_args() {
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        cala_usage
        exit 0
        ;;
      -V | --version)
        printf 'Calagopus-Installer %s\n' "$CALA_INSTALLER_VERSION"
        exit 0
        ;;
      -y | --yes | --non-interactive)
        CALA_NONINTERACTIVE=1
        ;;
      --dry-run)
        CALA_DRY_RUN=1
        ;;
      --*=*)
        local name value
        name="$(cala_option_name "${1%%=*}")"
        value="${1#*=}"
        cala_is_setting "$name" || cala_die "unknown option ${1%%=*} (see --help)"
        printf -v "CALA_$name" '%s' "$value"
        export "CALA_$name"
        ;;
      --*)
        local name
        name="$(cala_option_name "$1")"
        cala_is_setting "$name" || cala_die "unknown option $1 (see --help)"
        (($# >= 2)) || cala_die "option $1 needs a value"
        printf -v "CALA_$name" '%s' "$2"
        export "CALA_$name"
        shift
        ;;
      aio | panel | wings | update | uninstall | extensions)
        CALA_ACTION="$1"
        ;;
      *)
        cala_die "unknown argument $1 (see --help)"
        ;;
    esac
    shift
  done
}

cala_usage() {
  cat <<EOF
Calagopus-Installer ${CALA_INSTALLER_VERSION}: Docker installer for the Calagopus panel and Wings (unofficial).

Usage: $CALA_ONE_LINER
       install.sh [action] [options]

Actions: aio (default), panel, wings, update, uninstall, extensions

Options:
  -y, --non-interactive   never prompt; take every answer from options or CALA_* variables
      --dry-run           detect the system and install prerequisites, then stop before Docker
  -V, --version           print the installer version
  -h, --help              this text
  --<name> <value>        any setting below, e.g. --domain panel.example.com (same as CALA_DOMAIN=...)

Settings (environment variable, or the option without the CALA_ prefix):
  CALA_ACTION             aio | panel | wings | update | uninstall | extensions
  CALA_PANEL_DIR          panel directory (default /opt/calagopus-panel)
  CALA_WINGS_DIR          Wings directory for a node (default /opt/calagopus-wings)
  CALA_TIMEZONE           container time zone (default: the host's)
  CALA_DOMAIN             domain for HTTPS with Caddy; empty = no domain, panel on port 8000
  CALA_PUBLIC_IP          public IPv4 of this server (default: detected)
  CALA_IGNORE_DNS         yes = continue when the domain's DNS does not point here
  CALA_CREATE_ADMIN       yes (default) = create the first admin; no = keep the panel on 127.0.0.1
  CALA_ADMIN_EMAIL, CALA_ADMIN_USERNAME, CALA_ADMIN_PASSWORD
  CALA_FIREWALL           yes | no: configure ufw (Debian/Ubuntu) or firewalld (RHEL family)
  CALA_SSH_PORT           SSH port to keep open (default: detected)
  CALA_GAME_PORTS         game ports to open, e.g. 25565,25570-25580 (empty = none)
  CALA_EXTENSIONS         Caloptreyx extensions to install: comma list of keys, "all" or "none"
  CALA_THEME              theme to keep when CALA_EXTENSIONS names more than one
  CALA_LOW_MEMORY_OK      yes = build extensions with less than 4 GB RAM + swap
  CALA_EXTENSION_TIMEOUT  seconds to wait for the extension build (default 3600)
  CALA_WINGS_PANEL_URL, CALA_WINGS_ENROLL_CODE
                          enroll a new Wings node automatically (else it waits for pairing)
  CALA_UPDATE_BACKUP      yes (default) | no: dump the database before an update
  CALA_UNINSTALL_CONFIRM  yes = really uninstall (required with --non-interactive)
  CALA_REMOVE_DATA        yes = also delete data; needs CALA_REMOVE_DATA_CONFIRM=DELETE
  CALA_SKIP_OS_CHECK      yes = run on an unsupported OS
  CALA_SKIP_REQUIREMENTS  yes = run below the minimum RAM/disk
  CALA_PANEL_TIMEOUT      seconds to wait for the panel to answer (default 900)
  CALA_INSTALLER_REF      installer branch or tag the one-liner downloads (default main)
  CALA_LOG_FILE           log file (default /var/log/calagopus-installer.log)
EOF
}

# --- prompts -------------------------------------------------------------------------------------

cala_init_io() {
  if cala_truthy "${CALA_NONINTERACTIVE:-0}"; then
    CALA_INTERACTIVE=0
  elif [[ -t 0 ]]; then
    CALA_INTERACTIVE=1
    exec 3<&0
  elif { exec 3</dev/tty; } 2>/dev/null; then
    CALA_INTERACTIVE=1
  else
    CALA_INTERACTIVE=0
  fi
}

cala_truthy() {
  case "${1,,}" in
    y | yes | true | 1 | on) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints yes, no, or nothing for an unrecognised answer.
cala_yes_no_value() {
  case "${1,,}" in
    y | yes | true | 1 | on) printf yes ;;
    n | no | false | 0 | off) printf no ;;
  esac
}

cala_is_set() {
  [[ -n "${!1+x}" ]]
}

cala_read() {
  local prompt="$1" reply=""
  printf '%s' "$prompt" >&2
  IFS= read -r reply <&3 || true
  printf '%s' "$reply"
}

cala_read_secret() {
  local prompt="$1" reply=""
  printf '%s' "$prompt" >&2
  IFS= read -rs reply <&3 || true
  printf '\n' >&2
  printf '%s' "$reply"
}

# cala_ask VAR "Question" "default" validator "what is expected"
# Uses $VAR when it is set (an empty value counts as set), else asks, else takes the default.
cala_ask() {
  local var="$1" question="$2" default="$3" validator="${4:-}" expected="${5:-a valid value}"
  local value
  if cala_is_set "$var"; then
    value="${!var}"
    if [[ -n "$validator" ]] && ! "$validator" "$value"; then
      cala_die "$var: '$value' is not $expected"
    fi
    printf -v "$var" '%s' "$value"
    return 0
  fi
  if ((CALA_INTERACTIVE == 0)); then
    if [[ -n "$default" ]] || { [[ -n "$validator" ]] && "$validator" ""; }; then
      printf -v "$var" '%s' "$default"
      return 0
    fi
    cala_die "$var is required in non-interactive mode ($expected)"
  fi
  while true; do
    local suffix=""
    [[ -n "$default" ]] && suffix=" [$default]"
    value="$(cala_read "  $question$suffix: ")"
    [[ -z "$value" ]] && value="$default"
    if [[ -z "$validator" ]] || "$validator" "$value"; then
      printf -v "$var" '%s' "$value"
      return 0
    fi
    cala_warn "that is not $expected, try again"
  done
}

# cala_ask_yes_no VAR "Question" y|n   ->  VAR=yes|no
cala_ask_yes_no() {
  local var="$1" question="$2" default="$3" answer
  if cala_is_set "$var"; then
    answer="$(cala_yes_no_value "${!var}")"
    [[ -n "$answer" ]] || cala_die "$var: '${!var}' is not yes or no"
    printf -v "$var" '%s' "$answer"
    return 0
  fi
  if ((CALA_INTERACTIVE == 0)); then
    printf -v "$var" '%s' "$(cala_yes_no_value "$default")"
    return 0
  fi
  local hint="[y/N]"
  [[ "$default" == y ]] && hint="[Y/n]"
  while true; do
    answer="$(cala_read "  $question $hint: ")"
    [[ -z "$answer" ]] && answer="$default"
    answer="$(cala_yes_no_value "$answer")"
    if [[ -n "$answer" ]]; then
      printf -v "$var" '%s' "$answer"
      return 0
    fi
    cala_warn "answer y or n"
  done
}

# cala_ask_secret VAR "Question" validator "what is expected"   (asks twice, never echoes or logs)
cala_ask_secret() {
  local var="$1" question="$2" validator="$3" expected="$4" first second
  if cala_is_set "$var"; then
    "$validator" "${!var}" || cala_die "$var is not $expected"
    return 0
  fi
  ((CALA_INTERACTIVE == 1)) || cala_die "$var is required in non-interactive mode ($expected)"
  while true; do
    first="$(cala_read_secret "  $question: ")"
    if ! "$validator" "$first"; then
      cala_warn "that is not $expected, try again"
      continue
    fi
    second="$(cala_read_secret "  Repeat it: ")"
    if [[ "$first" == "$second" ]]; then
      printf -v "$var" '%s' "$first"
      return 0
    fi
    cala_warn "the two entries differ, try again"
  done
}

# cala_choose VAR "Question" default "key|Label" ...
cala_choose() {
  local var="$1" question="$2" default="$3"
  shift 3
  local options=("$@") keys=() option i
  for option in "${options[@]}"; do
    keys+=("${option%%|*}")
  done
  if cala_is_set "$var"; then
    for option in "${keys[@]}"; do
      if [[ "$option" == "${!var}" ]]; then
        return 0
      fi
    done
    cala_die "$var: '${!var}' is not one of: ${keys[*]}"
  fi
  if ((CALA_INTERACTIVE == 0)); then
    printf -v "$var" '%s' "$default"
    return 0
  fi
  printf '\n  %s\n' "$question" >&2
  for i in "${!options[@]}"; do
    local marker=" "
    [[ "${keys[$i]}" == "$default" ]] && marker="*"
    printf '  %s %d) %s\n' "$marker" "$((i + 1))" "${options[$i]#*|}" >&2
  done
  while true; do
    local answer
    answer="$(cala_read "  Choose 1-${#options[@]}: ")"
    if [[ -z "$answer" && -n "$default" ]]; then
      printf -v "$var" '%s' "$default"
      return 0
    fi
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#options[@]})); then
      printf -v "$var" '%s' "${keys[$((answer - 1))]}"
      return 0
    fi
    cala_warn "pick a number from the list"
  done
}
