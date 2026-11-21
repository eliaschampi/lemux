# shellcheck shell=bash
# clean.sh — preview and remove known caches.

clean_targets() {
  local c=$XDG_CACHE_HOME cargo=${CARGO_HOME:-$HOME/.cargo}
  printf '%s\0' \
    'Brave cache' brave "$c/BraveSoftware" \
    'Chrome cache' chrome "$c/google-chrome" \
    'Chromium cache' chromium,chromium-browse "$c/chromium" \
    'Firefox cache' firefox,firefox-bin,firefox-esr "$c/mozilla/firefox" \
    'Vivaldi cache' vivaldi-bin "$c/vivaldi" \
    'Edge cache' msedge "$c/microsoft-edge" \
    'npm cache' '' "$HOME/.npm/_cacache" \
    'npm logs' '' "$HOME/.npm/_logs" \
    'pnpm metadata' '' "$c/pnpm" \
    'Yarn cache' '' "$c/yarn" \
    'pip cache' '' "$c/pip" \
    'Go build cache' '' "$c/go-build" \
    'Composer cache' '' "$c/composer" \
    'Corepack' '' "$c/node/corepack" \
    'Cargo downloads' cargo "$cargo/registry/cache" \
    'Thumbnails' '' "$c/thumbnails"
}

clean_candidates() {
  clean_targets
  if (($1)); then
    # Keep Trash directories and pair each file with its original metadata.
    local t=$XDG_DATA_HOME/Trash f
    for f in "$t"/files/* "$t"/files/.[!.]* "$t"/files/..?*; do
      printf '%s\0' 'Trash' '' "$f"
    done
  fi
}

cmd_clean() {
  local apply=0 trash=0 orphans=0 journal=0 packages=0 arg
  for arg in "$@"; do
    case $arg in
      --apply) apply=1 ;;
      --trash) trash=1 ;;
      --orphans) orphans=1 ;;
      --journal) journal=1 ;;
      --packages) packages=1 ;;
      -h | --help) help_clean; return 0 ;;
      *) usage_error "clean: unknown option '$arg'" ;;
    esac
  done
  load_protect
  local total=0 label guard p size info
  if ((apply)); then section "Cleaning"; else section "Dry run: nothing is deleted (add --apply)"; fi
  while IFS= read -r -d '' label && IFS= read -r -d '' guard && IFS= read -r -d '' p; do
    [[ -e $p || -L $p ]] || continue
    can_remove_path "$p" || continue
    info=""
    if [[ $label == Trash ]]; then
      info=$XDG_DATA_HOME/Trash/info/${p##*/}.trashinfo
      if [[ -e $info || -L $info ]]; then can_remove_path "$info" || continue; else info=""; fi
    fi
    if [[ -n $guard ]] && any_running "$guard"; then
      note "$label: skipped while $guard runs"
      continue
    fi
    size=$(size_of "$p")
    printf '  %-22s %9s\n' "$label" "$(human "$size")"
    if ((apply)); then
      remove_path "$p" delete "$size" || return 1
      [[ -z $info ]] || remove_path "$info" || return 1
    fi
    total=$((total + size))
  done < <(clean_candidates "$trash")

  local -a pdirs
  size=0
  if ((packages)); then
    mapfile -t pdirs < <(pkg_cache_dirs)
    size=$(size_of "${pdirs[@]}")
  fi
  if ((size > 1048576)); then
    local allowed=1
    for p in "${pdirs[@]}"; do is_protected "$p" && allowed=0; done
    if ((allowed)); then
      printf '  %-22s %9s  (root, estimate)\n' "Package cache" "$(human "$size")"
      if ((apply)); then
        pkg_cache_clean || { err "package cache clean failed"; return 1; }
        oplog clean "package cache ($PKG)"
      fi
    fi
  fi

  if ((orphans)) && [[ $PKG != none ]]; then
    local listing
    listing=$(pkg_orphans) || { err "could not list orphaned packages"; return 1; }
    if [[ -n $listing ]]; then
      section "Orphaned packages"
      printf '  %s\n' "${listing//$'\n'/$'\n  '}"
      if ((apply)) && confirm "Remove these orphaned packages?"; then
        pkg_orphans_remove "$listing" || { err "orphan removal failed"; return 1; }
        oplog uninstall "$PKG:orphaned packages"
      fi
    fi
  fi

  if ((journal)) && has journalctl; then
    if is_protected /var/log/journal || is_protected /run/log/journal; then
      note "journal kept by protect list"
    else
      note "Journal: vacuum archived files to 200M (root)"
      if ((apply)); then
        as_root journalctl --vacuum-size=200M || { err "journal vacuum failed"; return 1; }
        oplog clean "archived systemd journal"
      fi
    fi
  fi

  printf '\n'
  if ((apply)); then say "Removed $(human "$total") in user files (apparent size)."
  else say "$(human "$total") in user files: lemux clean --apply"; fi
}

help_clean() {
  cat <<'EOF_HELP'
Usage: lemux clean [--apply] [--trash] [--orphans] [--journal] [--packages]

Shows rebuildable browser, development, thumbnail and package-manager caches.
Browsers and Cargo caches are skipped while their owning processes are running.

  --apply     delete the listed caches
  --packages  also clean the native package cache
  --trash     also empty the user Trash (irreversible)
  --orphans   also offer to remove orphaned native packages
  --journal   also shrink archived systemd journal files to 200M
EOF_HELP
}
