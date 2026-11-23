#!/usr/bin/env bash
# Calagopus-Installer: one-command Docker installer for the Calagopus panel and Wings.
# Unofficial, not affiliated with the Calagopus project.
#
#   bash <(curl -sSL https://install.caloptreyx.com)
#
# Run from a checkout, this script uses the files beside it. Run on its own (the one-liner), it downloads the
# installer at CALA_INSTALLER_REF as one tarball, so every file comes from the same commit, and runs the
# install.sh inside it. The default ref is this script's own release tag (v$CALA_INSTALLER_VERSION), so the
# script install.caloptreyx.com serves (the latest release) runs that release's files; CALA_INSTALLER_REF=main
# runs the development branch instead.
set -Eeuo pipefail

CALA_INSTALLER_VERSION="0.1.0"
CALA_INSTALLER_REPO="Caloptreyx/Calagopus-Installer"

cala_self_dir() {
  local source="${BASH_SOURCE[0]:-}"
  [[ -f "$source" ]] || return 1
  (cd "$(dirname "$source")" && pwd)
}

cala_bootstrap() {
  local ref="${CALA_INSTALLER_REF:-v${CALA_INSTALLER_VERSION}}"
  if [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "CALA_INSTALLER_REF has an invalid value: $ref" >&2
    exit 1
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "The installer needs curl and tar to download itself. Install them first, for example:" >&2
    echo "  apt-get install -y curl tar    or    dnf install -y curl tar" >&2
    exit 1
  fi
  local tmp
  tmp="$(mktemp -d /tmp/calagopus-installer.XXXXXX)"
  trap 'rm -rf "$tmp"' EXIT
  if ! curl -fsSL --retry 3 "https://codeload.github.com/${CALA_INSTALLER_REPO}/tar.gz/${ref}" |
    tar -xz -C "$tmp" --strip-components=1 || [[ ! -f "$tmp/install.sh" ]]; then
    echo "Could not download the installer (${CALA_INSTALLER_REPO} at ${ref})." >&2
    [[ -n "${CALA_INSTALLER_REF:-}" ]] || echo "To run the development branch instead: CALA_INSTALLER_REF=main" >&2
    exit 1
  fi
  CALA_BOOTSTRAPPED=1 bash "$tmp/install.sh" "$@"
}

main() {
  local dir
  if dir="$(cala_self_dir)" && [[ -f "$dir/lib/core.sh" ]]; then
    CALA_ROOT="$dir"
    # shellcheck source=lib/core.sh
    source "$CALA_ROOT/lib/core.sh"
    # shellcheck source=lib/checks.sh
    source "$CALA_ROOT/lib/checks.sh"
    # shellcheck source=lib/system.sh
    source "$CALA_ROOT/lib/system.sh"
    # shellcheck source=lib/compose.sh
    source "$CALA_ROOT/lib/compose.sh"
    # shellcheck source=installers/panel.sh
    source "$CALA_ROOT/installers/panel.sh"
    # shellcheck source=installers/wings.sh
    source "$CALA_ROOT/installers/wings.sh"
    # shellcheck source=installers/extensions.sh
    source "$CALA_ROOT/installers/extensions.sh"
    # shellcheck source=installers/update.sh
    source "$CALA_ROOT/installers/update.sh"
    # shellcheck source=installers/uninstall.sh
    source "$CALA_ROOT/installers/uninstall.sh"
    # shellcheck source=ui/menu.sh
    source "$CALA_ROOT/ui/menu.sh"
    cala_main "$@"
  elif [[ "${CALA_BOOTSTRAPPED:-0}" == 1 ]]; then
    echo "The downloaded installer is incomplete (lib/core.sh is missing)." >&2
    exit 1
  else
    cala_bootstrap "$@"
  fi
}

main "$@"
