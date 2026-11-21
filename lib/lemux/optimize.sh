# shellcheck shell=bash
# optimize.sh — refresh caches and maintenance services. Dry run unless --apply.

# description|condition function|action function
opt_tasks() {
  printf '%s\n' \
    'Flush the DNS cache (systemd-resolved)|opt_has_resolved|opt_dns' \
    'Rebuild the application menu database|opt_has_menu|opt_menu' \
    'Rebuild your MIME type database|opt_has_mime|opt_mime' \
    'Refresh your icon cache|opt_has_icons|opt_icons' \
    'Rebuild the font cache|opt_has_fonts|opt_fonts' \
    'TRIM mounted SSDs (no fstrim timer is active)|opt_needs_trim|opt_trim'
}
opt_has_resolved() { has resolvectl && systemctl is-active -q systemd-resolved 2>/dev/null; }
opt_dns() { as_root resolvectl flush-caches; }
opt_has_menu() { has update-desktop-database && [[ -d $XDG_DATA_HOME/applications ]]; }
opt_menu() { update-desktop-database "$XDG_DATA_HOME/applications"; }
opt_has_mime() { has update-mime-database && [[ -d $XDG_DATA_HOME/mime/packages ]]; }
opt_mime() { update-mime-database "$XDG_DATA_HOME/mime"; }
opt_has_icons() { has gtk-update-icon-cache && [[ -f $XDG_DATA_HOME/icons/hicolor/index.theme ]]; }
opt_icons() { gtk-update-icon-cache -f -t "$XDG_DATA_HOME/icons/hicolor"; }
opt_has_fonts() { has fc-cache; }
opt_fonts() { fc-cache -f; }
opt_needs_trim() {
  has fstrim && ! systemctl is-active -q fstrim.timer 2>/dev/null &&
    lsblk -dno ROTA 2>/dev/null | grep -qx '0'
}
opt_trim() { as_root fstrim -av; }

cmd_optimize() {
  local apply=0 arg desc cond act n=0
  for arg in "$@"; do
    case $arg in
      --apply) apply=1 ;;
      -h | --help) help_optimize; return 0 ;;
      *) usage_error "optimize: unknown option '$arg'" ;;
    esac
  done
  if ((apply)); then section "Optimizing"; else section "Dry run: these steps would run (add --apply)"; fi
  while IFS='|' read -r desc cond act; do
    "$cond" || continue
    n=$((n + 1))
    if ((!apply)); then note "$desc"; continue; fi
    if "$act"; then ok "$desc"; oplog optimize "$desc"; else err "failed: $desc"; return 1; fi
  done < <(opt_tasks)
  ((n)) || say "  Nothing to do."
}

help_optimize() {
  cat <<'EOF'
Usage: lemux optimize [--apply]

Refreshes what tends to go stale: the DNS cache (systemd-resolved), your application
menu, MIME and icon databases, the font cache, a TRIM pass on SSDs when no weekly
fstrim timer is active. Only steps that apply
to this system are shown.
EOF
}
