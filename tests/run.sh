#!/usr/bin/env bash
# Unit tests for the installer's pure functions. No root, network or Docker needed.
#   bash tests/run.sh            run every test_* function in tests/test_*.sh
#   bash tests/run.sh dns        only tests whose name contains "dns"
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALA_ROOT="$(dirname "$TESTS_DIR")"
# shellcheck disable=SC2034 # used by the sourced test files
FIXTURES="$TESTS_DIR/fixtures"
CALA_INSTALLER_VERSION="test"

# shellcheck source=../lib/core.sh
source "$CALA_ROOT/lib/core.sh"
# shellcheck source=../lib/checks.sh
source "$CALA_ROOT/lib/checks.sh"
# shellcheck source=../lib/system.sh
source "$CALA_ROOT/lib/system.sh"
# shellcheck source=../lib/compose.sh
source "$CALA_ROOT/lib/compose.sh"
# shellcheck source=../installers/panel.sh
source "$CALA_ROOT/installers/panel.sh"
# shellcheck source=../installers/extensions.sh
source "$CALA_ROOT/installers/extensions.sh"
# shellcheck source=../installers/uninstall.sh
source "$CALA_ROOT/installers/uninstall.sh"

FAILURES=0
CURRENT=""

fail() {
  printf '    FAIL %s: %s\n' "$CURRENT" "$*"
  FAILURES=$((FAILURES + 1))
}

assert_ok() {
  "$@" >/dev/null 2>&1 || fail "expected success: $*"
}

assert_fails() {
  ! "$@" >/dev/null 2>&1 || fail "expected failure: $*"
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "expected output to contain '$2', got: $1"
}

assert_file_contains() {
  grep -qE -- "$2" "$1" || fail "$1 does not match /$2/"
}

assert_file_lacks() {
  ! grep -qE -- "$2" "$1" || fail "$1 unexpectedly matches /$2/"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for file in "$TESTS_DIR"/test_*.sh; do
  # shellcheck source=/dev/null
  source "$file"
done

filter="${1:-}"
count=0
failed=0
while read -r name; do
  [[ -z "$filter" || "$name" == *"$filter"* ]] || continue
  CURRENT="$name"
  count=$((count + 1))
  # Each test runs in a subshell, so a test that exits (cala_die) fails instead of ending the run.
  if (
    FAILURES=0
    "$name"
    ((FAILURES == 0))
  ); then
    printf '  ok   %s\n' "$name"
  else
    printf '  FAILED %s\n' "$name"
    failed=$((failed + 1))
  fi
done < <(declare -F | awk '$3 ~ /^test_/ { print $3 }')

printf '\n%d tests, %d failed\n' "$count" "$failed"
((failed == 0))
