# shellcheck shell=bash
# clean.sh — preview and remove known caches.

clean_targets() {
  local c=$XDG_CACHE_HOME cargo=${CARGO_HOME:-$HOME/.cargo}
  if ((browser)); then printf '%s\0' \
    'Brave cache' brave "$c/BraveSoftware" \
    'Chrome cache' chrome "$c/google-chrome" \
    'Chromium cache' chromium,chromium-browse "$c/chromium" \
    'Firefox cache' firefox,firefox-bin,firefox-esr "$c/mozilla/firefox" \
    'Vivaldi cache' vivaldi-bin "$c/vivaldi" \
    'Edge cache' msedge "$c/microsoft-edge"
  fi
  if ((basic)); then printf '%s\0' \
    'npm cache' '' "$HOME/.npm/_cacache" \
    'pnpm metadata' '' "$c/pnpm" \
    'Yarn cache' '' "$c/yarn" \
    'pip cache' '' "$c/pip" \
    'Go build cache' '' "$c/go-build" \
    'Composer cache' '' "$c/composer" \
    'Corepack' '' "$c/node/corepack" \
    'Cargo downloads' cargo "$cargo/registry/cache" \
    'Thumbnails' '' "$c/thumbnails"
  fi
  if ((deep)); then
    printf '%s\0' \
      'Mesa shader cache' '' "$c/mesa_shader_cache" \
      'Mesa database cache' '' "$c/mesa_shader_cache_db" \
      'Mesa single-file cache' '' "$c/mesa_shader_cache_sf" \
      'Fontconfig cache' '' "$c/fontconfig" \
      'NVIDIA shader cache' '' "$c/nvidia/GLCache" \
      'Vulkan shader cache' '' "$c/radv_builtin_shaders"
    local shard
    for shard in "$c"/ccache/[0-9a-f]; do
      printf '%s\0' 'ccache objects' ccache "$shard"
    done
  fi
  if ((logs || legacy)); then printf '%s\0' 'npm logs' '' "$HOME/.npm/_logs"; fi
  if ((history)) && [[ -f $HOME/.bash_history && ! -L $HOME/.bash_history ]]; then
    printf '%s\0' 'Saved Bash history' '' "$HOME/.bash_history"
  fi
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
  local basic=0 browser=0 deep=0 logs=0 history=0 explicit=0 legacy=0 extras=0
  local apply=0 trash=0 orphans=0 journal=0 packages=0 arg
  for arg in "$@"; do
    case $arg in
      --basic) basic=1; explicit=1 ;;
      --browser) browser=1; explicit=1 ;;
      --deep) deep=1; explicit=1 ;;
      --logs) logs=1; explicit=1 ;;
      --bash-history) history=1; explicit=1 ;;
      --apply) apply=1 ;;
      --trash) trash=1; extras=1 ;;
      --orphans) orphans=1; extras=1 ;;
      --journal) journal=1; extras=1 ;;
      --packages) packages=1; extras=1 ;;
      -h | --help) help_clean; return 0 ;;
      *) usage_error "clean: unknown option '$arg'" ;;
    esac
  done
  if ((!explicit && !extras)) && [[ -t 0 && -t 1 && $LEMUX_YES != 1 ]]; then
    # shellcheck disable=SC2034  # read by checkboxes through a nameref
    local -a choices=('Development caches and thumbnails' 'Browser caches'
      'Deep caches (native package downloads, shaders, fonts, ccache)'
      'Logs (npm logs and archived journal over 200M)' 'Saved Bash history (~/.bash_history)'
      'Empty Trash' 'Remove orphaned packages')
    local -a picked=(1 1 0 0 0 0 0)
    checkboxes choices picked "Select cleanup categories" || return $?
    basic=${picked[0]} browser=${picked[1]} deep=${picked[2]} logs=${picked[3]}
    history=${picked[4]} trash=${picked[5]} orphans=${picked[6]}
  elif ((!explicit)); then
    basic=1 browser=1 legacy=1
  fi
  ((deep)) && packages=1
  ((logs)) && journal=1
  if ((history)); then note "Only the saved ~/.bash_history is cleared. Open Bash sessions may write it again."; fi
  load_protect
  if ((basic || browser || deep)); then
    case $XDG_CACHE_HOME in
      /|"$HOME"|"$XDG_CONFIG_HOME"|"$XDG_DATA_HOME"|"$XDG_STATE_HOME")
        die "XDG_CACHE_HOME overlaps a data directory: $XDG_CACHE_HOME" ;;
    esac
  fi
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
  if ((size > 0)); then
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

  if ((deep)) && has systemd-tmpfiles && ! is_protected /var/cache; then
    note "System caches: expire entries under /var/cache using systemd-tmpfiles age rules (root)"
    if ((apply)); then
      as_root systemd-tmpfiles --clean --prefix=/var/cache || { err "system cache expiry failed"; return 1; }
      oplog clean "expired /var/cache entries"
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
  else say "$(human "$total") in user files. Add --apply with the same selection to clean."; fi
}

help_clean() {
  cat <<'EOF_HELP'
Usage: lemux clean [categories] [--apply] [--trash] [--orphans] [--journal] [--packages]

In a terminal, use Space to select categories and Enter to preview or apply.
Pass category flags to choose exactly what to scan:
  --basic         development caches and thumbnails
  --browser       browser disk caches (skip running browsers)
  --deep          package, shader, font and compiler caches, plus expired /var/cache entries
  --logs          npm logs and archived journal above 200M
  --bash-history  saved ~/.bash_history (open shells may write it again)

  --apply     execute selected actions
  --packages  include the native package cache
  --trash     empty the user Trash
  --orphans   offer to remove orphaned native packages
  --journal   shrink archived systemd journal files to 200M

Without category flags, scripts and -y retain the previous default cache set.
EOF_HELP
}
