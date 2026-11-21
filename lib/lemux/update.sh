# shellcheck shell=bash
# update.sh — update everything in one go: system packages, Flatpak, Snap and AppImages.

cmd_update() {
  local apps_only=0 arg
  for arg in "$@"; do
    case $arg in
      --apps) apps_only=1 ;;
      -h | --help) help_update; return 0 ;;
      *) usage_error "update: unknown option '$arg'" ;;
    esac
  done
  if ((!apps_only)); then
    if [[ $PKG != none ]] && confirm "Upgrade system packages with $PKG?"; then
      section "System packages ($PKG)"
      pkg_upgrade || { err "system upgrade failed"; return 1; }
    fi
    if has flatpak && [[ -n $(flatpak list --columns=application 2>/dev/null) ]]; then
      section "Flatpak"
      flatpak update -y --noninteractive || return 1
    fi
    if has snap && snap list >/dev/null 2>&1; then
      section "Snap"
      as_root snap refresh || return 1
    fi
  fi
  section "AppImages"
  app_update
}

help_update() {
  cat <<'EOF'
Usage: lemux update [--apps]

Updates the system packages (asks first; -y to skip the question), Flatpak and
Snap apps, and the AppImages installed with lemux.

  --apps   only the AppImages
EOF
}
