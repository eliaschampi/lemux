# shellcheck shell=bash
# analyze.sh — largest folders and files on a single filesystem.

cmd_analyze() {
  local path="" top=12
  while (($#)); do
    case $1 in
      --top) top=${2:-}; shift ;;
      -h | --help) help_analyze; return 0 ;;
      -*) usage_error "analyze: unknown option '$1'" ;;
      *) [[ -z $path ]] || usage_error "analyze accepts one folder"; path=$1 ;;
    esac
    shift
  done
  valid_count "$top" || usage_error "analyze: --top needs a nonnegative integer"
  path=$(realpath -e -- "${path:-$HOME}") || return 1
  [[ -d $path ]] || usage_error "analyze: not a folder: $path"
  local total=0 size dir pct row n=0 rc=0
  local dirs=$LEMUX_TMP/dirs files=$LEMUX_TMP/files
  du -x -B1 --max-depth=1 -0 -- "$path" >"$dirs" || rc=1
  section "Largest folders in ${path/#$HOME/\~}"
  while IFS= read -r -d '' row; do
    size=${row%%$'\t'*} dir=${row#*$'\t'}
    if [[ $dir == "$path" ]]; then total=$size; fi
  done <"$dirs"
  while IFS= read -r -d '' row; do
    size=${row%%$'\t'*} dir=${row#*$'\t'}
    [[ $dir != "$path" ]] || continue
    ((n < top && total > 0)) || break
    pct=$((size * 100 / total))
    printf '  %8s %s %3d%%  %q\n' "$(human "$size")" "$(bar "$pct" 18)" "$pct" "${dir/#$HOME/\~}"
    n=$((n + 1))
  done < <(sort -zrn -- "$dirs")
  printf '  %8s total\n' "$(human "$total")"

  section "Largest files"
  find "$path" -xdev -type f -size +50M -printf '%s\t%p\0' >"$files" || rc=1
  while IFS= read -r -d '' row; do
    size=${row%%$'\t'*} dir=${row#*$'\t'}
    printf '  %8s  %q\n' "$(human "$size")" "${dir/#$HOME/\~}"
  done < <(sort -zrn -- "$files" | head -z -n 8)
  return "$rc"
}

help_analyze() {
  cat <<'EOF_HELP'
Usage: lemux analyze [folder] [--top N]

Shows the largest folders directly under a folder (default: your home) with their
share of the total, and the largest files below it. Stays on one filesystem.
EOF_HELP
}
