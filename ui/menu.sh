# shellcheck shell=bash
# Entry point after the bootstrapper: banner, menu and dispatch.

cala_banner() {
  cat <<EOF

${C_BOLD}Calagopus-Installer ${CALA_INSTALLER_VERSION}${C_RESET}
Docker installer for the Calagopus panel and Wings. Unofficial: not affiliated with the Calagopus project.
Docs: https://calagopus.com/docs   Source: https://github.com/Caloptreyx/Calagopus-Installer
EOF
}

cala_menu() {
  cala_choose CALA_ACTION "What do you want to do?" aio \
    "aio|All-in-One: panel and Wings in one container (recommended for one server)" \
    "panel|Panel only (for multi-node setups; add Wings nodes separately)" \
    "wings|Wings node, paired with an existing panel" \
    "extensions|Add Caloptreyx themes/extensions to an installed panel" \
    "update|Update an install (new images, keeps data and keys)" \
    "uninstall|Uninstall" \
    "quit|Quit"
}

cala_main() {
  cala_parse_args "$@"
  cala_require_root
  cala_init_log "action=${CALA_ACTION:-menu} dry_run=${CALA_DRY_RUN:-no}"
  cala_init_tmp
  trap cala_cleanup EXIT
  trap 'cala_on_error $? $LINENO "$BASH_COMMAND"' ERR
  cala_init_io
  cala_banner
  cala_menu
  [[ "$CALA_ACTION" == quit ]] && exit 0

  cala_step "Checking this server"
  cala_check_os
  case "$CALA_ACTION" in
    aio | panel | wings) cala_check_virt ;;
  esac
  cala_install_prerequisites

  case "$CALA_ACTION" in
    aio | panel) cala_install_panel "$CALA_ACTION" ;;
    wings) cala_install_wings ;;
    extensions) cala_extensions_action ;;
    update) cala_update ;;
    uninstall) cala_uninstall ;;
  esac
  exit "$CALA_EXIT_CODE"
}
