# shellcheck shell=bash
# purge.sh — delete the rebuildable build artifacts of your projects. Dry run unless --apply.
#
# An artifact counts only next to the file that proves what it is (node_modules next to
# package.json, target next to Cargo.toml...). Anything tracked by git is never touched,
# and artifacts changed in the last N days (default 7) are skipped unless --all is given.

# artifact folder|marker files beside it (colon list; empty = the name is proof enough)
purge_rules() {
  printf '%s\n' \
    'node_modules|package.json' '.svelte-kit|package.json' '.next|package.json' '.nuxt|package.json' \
    '.output|package.json' '.turbo|package.json' '.parcel-cache|package.json' '.angular|angular.json' \
    'target|Cargo.toml:pom.xml' 'vendor|composer.json' \
    '.venv|pyproject.toml:requirements.txt:setup.py' 'venv|pyproject.toml:requirements.txt:setup.py' \
    '__pycache__|' '.pytest_cache|' '.mypy_cache|' '.ruff_cache|' \
    '.gradle|build.gradle:build.gradle.kts:settings.gradle:settings.gradle.kts' \
    'build|package.json:build.gradle:build.gradle.kts:CMakeLists.txt:pyproject.toml:pubspec.yaml' \
    'dist|package.json:pyproject.toml:setup.py' \
    '.dart_tool|pubspec.yaml' '.build|Package.swift' '.zig-cache|build.zig' 'zig-cache|build.zig'
}

purge_roots() { # explicit paths, ~/.config/lemux/purge_paths, or common project folders
  if (($#)); then printf '%s\0' "$@"; return; fi
  local f=$LEMUX_CONF/purge_paths line d
  if [[ -r $f ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%%#*}
      [[ -n ${line// } ]] && printf '%s\0' "${line/#\~/$HOME}"
    done <"$f"
    return
  fi
  for d in Projects projects Code code dev Dev src work Work GitHub git repos Documents; do
    [[ -d $HOME/$d ]] && printf '%s\0' "$HOME/$d"
  done
}

cmd_purge() {
  local apply=0 all=0 days=7
  local -a paths=()
  while (($#)); do
    case $1 in
      --apply) apply=1 ;;
      --all) all=1 ;;
      --days) days=${2:-}; shift ;;
      -h | --help) help_purge; return 0 ;;
      -*) usage_error "purge: unknown option '$1'" ;;
      *) [[ -d $1 ]] || usage_error "purge: not a folder: $1"; paths+=("$(realpath -e -- "$1")") ;;
    esac
    shift
  done
  valid_count "$days" || usage_error "purge: --days needs a number"
  load_protect
  if ((apply)); then need git; fi
  local -a roots names=() expr=()
  mapfile -d '' -t roots < <(purge_roots "${paths[@]}")
  ((${#roots[@]})) || { say "No project folders found. Pass one: lemux purge ~/my-projects"; return 0; }
  local -A markers=()
  local name marker
  while IFS='|' read -r name marker; do markers[$name]=$marker; names+=("$name"); done < <(purge_rules)
  for name in "${names[@]}"; do expr+=(-name "$name" -o); done
  unset 'expr[${#expr[@]}-1]'

  if ((apply)); then section "Purging build artifacts"; else section "Dry run: nothing is deleted (add --apply)"; fi
  local dir proj base age size total=0 count=0 tracked m ok_marker candidate
  local inventory=$LEMUX_TMP/purge
  local -a scan_roots=()
  local -A seen=()
  for dir in "${roots[@]}"; do
    dir=$(realpath -e -- "$dir") || return 1
    [[ -d $dir && $dir != / ]] || usage_error "purge: invalid project root: $dir"
    scan_roots+=("$dir")
  done
  find "${scan_roots[@]}" -xdev \( -name .git -o -name .hg \) -prune -o \
    -type d \( "${expr[@]}" \) -prune -print0 >"$inventory" || return 1
  local -a ms
  while IFS= read -r -d '' dir; do
    [[ ! ${seen[$dir]+found} ]] || continue
    seen[$dir]=1
    base=${dir##*/} proj=${dir%/*}
    ok_marker=1
    if [[ -n ${markers[$base]} ]]; then
      ok_marker=0
      IFS=: read -ra ms <<<"${markers[$base]}"
      for m in "${ms[@]}"; do [[ -e $proj/$m ]] && { ok_marker=1; break; }; done
    fi
    ((ok_marker)) || continue
    can_remove_path "$dir" || continue
    if has git; then
      local ancestor=$proj
      while [[ -n $ancestor ]]; do
        if [[ -e $ancestor/.git || -L $ancestor/.git ]]; then
          tracked=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
            git --literal-pathspecs -C "$proj" ls-files -- "$base") || return 1
          break
        fi
        ancestor=${ancestor%/*}
      done
      if [[ -n ${tracked:-} ]]; then tracked=""; continue; fi
    fi
    candidate=$(find "$dir" -xdev \( -name .git -o -name .hg -o ! -uid "$EUID" \) -printf x -quit) || return 1
    [[ -z $candidate ]] || continue
    age=$(days_old "$dir")
    size=$(size_of "$dir")
    ((size > 0)) || continue
    if ((age < days && !all)); then
      printf '  %s○%s %-46s %8s  %-13s %sd (recent, kept)\n' "$C_D" "$C_0" "${proj/#$HOME/\~}" "$(human "$size")" "$base" "$age"
      continue
    fi
    printf '  %s●%s %-46s %8s  %-13s %sd\n' "$C_G" "$C_0" "${proj/#$HOME/\~}" "$(human "$size")" "$base" "$age"
    total=$((total + size)) count=$((count + 1))
    if ((apply)); then remove_path "$dir" delete "$size" || return 1; fi
  done <"$inventory"
  printf '\n'
  if ((count == 0)); then say "Nothing to purge."
  elif ((apply)); then say "Purged $count artifact(s), $(human "$total") apparent size."
  else say "$count artifact(s), $(human "$total"): lemux purge --apply"; fi
}

help_purge() {
  cat <<'EOF'
Usage: lemux purge [folder ...] [--apply] [--all] [--days N]

Finds rebuildable build artifacts in your projects: node_modules, .svelte-kit, .next,
.nuxt, Cargo/Maven target, Composer vendor, Python venvs and caches, Gradle, build/dist
folders, Dart, Swift and Zig caches. Each one must sit next to the file that proves what
it is (node_modules next to package.json...), and anything tracked by git is never touched.

  --apply    delete them (reinstall with npm install, cargo build...)
  --all      include artifacts changed in the last N days
  --days N   what counts as recent (default 7)

Folders scanned: the ones given, else the lines of ~/.config/lemux/purge_paths, else
~/Projects, ~/Code, ~/dev, ~/src, ~/work, ~/GitHub, ~/repos and ~/Documents.
EOF
}
