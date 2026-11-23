# shellcheck shell=bash
# installers.sh — find installer files you no longer need. Dry run unless --apply.

installer_dirs() {
  local desktop downloads
  desktop=$(user_dir DESKTOP Desktop)
  downloads=$(user_dir DOWNLOAD Downloads)
  printf '%s\n' "$downloads" "$downloads/Telegram Desktop" "$desktop" | awk '!seen[$0]++'
}

# installer_status FILE -> "1|reason" when it is safe to delete, "0|reason" otherwise
installer_status() {
  local f=$1 pkg app
  case ${f,,} in
    *.deb)
      pkg=$(dpkg-deb -f "$f" Package 2>/dev/null)
      if [[ -n $pkg ]] && pkg_is_installed "$pkg"; then echo "1|$pkg is installed"; else echo "0|not installed"; fi ;;
    *.rpm)
      pkg=$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)
      if [[ -n $pkg ]] && pkg_is_installed "$pkg"; then echo "1|$pkg is installed"; else echo "0|not installed"; fi ;;
    *.pkg.tar.*)
      pkg=$(pacman -Qqp "$f" 2>/dev/null)
      if [[ -n $pkg ]] && pkg_is_installed "$pkg"; then echo "1|$pkg is installed"; else echo "0|not installed"; fi ;;
    *.appimage)
      for app in "$LEMUX_APPS"/*/*.AppImage; do
        [[ -f $app && $(stat -Lc %s -- "$app") == "$(stat -c %s "$f")" ]] && cmp -s "$app" "$f" &&
          { echo "1|installed with lemux as $(basename "$app" .AppImage)"; return; }
      done
      echo "0|not managed by lemux (lemux app install)" ;;
    *.iso) echo "0|disk image" ;;
    *) echo "0|installer" ;;
  esac
}

cmd_installers() {
  local apply=0 all=0 arg
  for arg in "$@"; do
    case $arg in
      --apply) apply=1 ;;
      --all) all=1 ;;
      -h | --help) help_installers; return 0 ;;
      *) usage_error "installers: unknown option '$arg'" ;;
    esac
  done
  if ((apply)); then section "Removing installers"; else section "Dry run: nothing is deleted (add --apply)"; fi
  load_protect
  local -a dirs
  mapfile -t dirs < <(installer_dirs)
  local f st safe reason size total=0 count=0
  while IFS= read -r -d '' f; do
    can_remove_path "$f" || continue
    st=$(installer_status "$f")
    safe=${st%%|*} reason=${st#*|}
    size=$(stat -c %s -- "$f") || return 1
    if ((safe || all)); then
      printf '  %s●%s %-44s %8s  %s\n' "$C_G" "$C_0" "${f##*/}" "$(human "$size")" "$reason"
      total=$((total + size)) count=$((count + 1))
      if ((apply)); then remove_path "$f" trash "$size" || return 1; fi
    else
      printf '  %s○%s %-44s %8s  %s\n' "$C_D" "$C_0" "${f##*/}" "$(human "$size")" "$reason"
    fi
  done < <(for d in "${dirs[@]}"; do [[ -d $d ]] && find "$d" -maxdepth 1 -type f \( -iname '*.deb' -o -iname '*.rpm' \
    -o -iname '*.pkg.tar.*' -o -iname '*.appimage' -o -iname '*.flatpakref' -o -iname '*.flatpak' -o -iname '*.snap' \
    -o -iname '*.iso' -o -iname '*.run' \) -print0; done 2>/dev/null)
  printf '\n'
  if ((count == 0)); then say "No installers to remove (○ items need --all)."
  elif ((apply)); then say "Moved $count installer(s) to the Trash ($(human "$total"))."
  else say "$count installer(s), $(human "$total"): lemux installers --apply"; fi
}

help_installers() {
  cat <<'EOF'
Usage: lemux installers [--apply] [--all]

Finds installer files in Downloads, Telegram Desktop downloads and the Desktop:
.deb, .rpm, .pkg.tar.*, AppImage, Flatpak and Snap bundles, ISO images and .run files.

● marked files are eligible for the Trash: packages that are already installed, and AppImages
identical to one installed with 'lemux app'. ○ files are listed but kept.

  --apply   move the ● files to the Trash
  --all     include the ○ files too
EOF
}
