# shellcheck shell=bash
# core.sh — shared helpers: output, prompts, privileges, XDG paths and small utilities.
#
# errexit is deliberately off (see CONTRIBUTING.md): every destructive step checks its
# own status, so a failed grep in a probe never aborts a cleanup halfway through.

# shellcheck disable=SC2034  # read by bin/lemux
LEMUX_VERSION="0.0.2"

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
LEMUX_YES=${LEMUX_YES:-0}
# XDG directories are absolute under the base directory specification.
[[ $XDG_CONFIG_HOME == /* ]] || XDG_CONFIG_HOME=$HOME/.config
[[ $XDG_DATA_HOME == /* ]] || XDG_DATA_HOME=$HOME/.local/share
[[ $XDG_STATE_HOME == /* ]] || XDG_STATE_HOME=$HOME/.local/state
[[ $XDG_CACHE_HOME == /* ]] || XDG_CACHE_HOME=$HOME/.cache

if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
  C_B=$'\e[1m' C_G=$'\e[32m' C_Y=$'\e[33m' C_R=$'\e[31m' C_D=$'\e[2m' C_0=$'\e[0m'
else
  C_B='' C_G='' C_Y='' C_R='' C_D='' C_0=''
fi

say()     { printf '%s\n' "$*"; }
section() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_0"; }
ok()      { printf '  %sok%s    %s\n' "$C_G" "$C_0" "$*"; }
warn()    { printf '  %swarn%s  %s\n' "$C_Y" "$C_0" "$*"; WARNINGS=$((${WARNINGS:-0} + 1)); }
note()    { printf '  %s··%s    %s\n' "$C_D" "$C_0" "$*"; }
err()     { printf '%slemux:%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()     { err "$*"; exit 1; }
usage_error() { err "$*"; exit 2; }

has()   { command -v "$1" >/dev/null 2>&1; }
need()  { local c; for c in "$@"; do has "$c" || die "missing dependency: $c"; done; }
human() { numfmt --to=iec --suffix=B "${1:-0}"; }

# size_of PATH... -> total bytes of the paths that exist
size_of() {
  local total=0 p n
  for p in "$@"; do
    [[ -e $p || -L $p ]] || continue
    n=$(du -sb -- "$p" 2>/dev/null | cut -f1)
    [[ $n =~ ^[0-9]+$ ]] && total=$((total + n))
  done
  printf '%s\n' "$total"
}

# norm "Open-IDEA_2" -> "openidea2" (for loose, case-insensitive name matching)
norm() { local s=${1,,}; printf '%s' "${s//[^a-z0-9]/}"; }
# slug "Photon Studio" -> "photon-studio"
slug() { local s=${1,,}; sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' <<<"$s"; }

confirm() { # confirm "Question" -> 0 when the user says yes (always yes with -y)
  [[ $LEMUX_YES == 1 ]] && return 0
  [[ -t 0 ]] || return 1
  local answer
  read -r -p "$1 [y/N] " answer
  [[ $answer == [yYsS]* ]]
}

# as_root CMD... -> run with root rights through sudo, doas or run0
as_root() {
  if ((EUID == 0)); then
    "$@"
  elif has sudo; then
    local opts=()
    [[ -n ${SUDO_ASKPASS:-} ]] && opts=(-A)
    sudo "${opts[@]}" -- "$@"
  elif has doas; then
    doas -- "$@"
  elif has run0; then
    run0 -- "$@"
  else
    err "root rights needed for: $*"
    return 1
  fi
}
root_ready() { ((EUID == 0)) || { has sudo && sudo -n true 2>/dev/null; }; }

# any_running "brave,chrome" -> 0 if one of these process names runs for this user
any_running() {
  local name
  local -a names
  IFS=, read -ra names <<<"$1"
  for name in "${names[@]}"; do
    pgrep -u "$EUID" -x -- "$name" >/dev/null 2>&1 && return 0
  done
  return 1
}

LEMUX_CONF=$XDG_CONFIG_HOME/lemux
LEMUX_STATE=$XDG_STATE_HOME/lemux
LEMUX_OPLOG=$LEMUX_STATE/operations.log

json_string() {
  local value=$1 char escape code
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  if [[ $value == *[[:cntrl:]]* ]]; then
    for ((code = 1; code < 32; code++)); do
      printf -v escape '\\x%02x' "$code"
      printf -v char '%b' "$escape"
      printf -v escape '\\u%04x' "$code"
      value=${value//"$char"/"$escape"}
    done
  fi
  printf '"%s"' "$value"
}

# JSON Lines for new entries. history also reads the original tab-separated log.
oplog() {
  [[ ${LEMUX_NO_OPLOG:-0} == 1 ]] && return 0
  local bytes=${3:-null}
  if ! { mkdir -p -- "$LEMUX_STATE" &&
    printf '{"time":%s,"command":%s,"action":%s,"bytes":%s,"path":%s}\n' \
      "$(json_string "$(date -Iseconds)")" "$(json_string "${LEMUX_CMD:-lemux}")" \
      "$(json_string "$1")" "$bytes" "$(json_string "$2")" >>"$LEMUX_OPLOG"; }; then
    err "could not record $1 in the operations log"
  fi
  return 0
}

# One absolute path or glob per line. Keep matching paths, their contents and
# any parent directory whose removal would also delete a protected path.
PROTECT=()
load_protect() {
  local f=$LEMUX_CONF/protect line
  [[ -e $f || -L $f ]] || return 0
  [[ -f $f && -r $f ]] || die "cannot read protect list $f"
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n $line && $line != \#* ]] || continue
    line=${line/#\~/$HOME}
    [[ $line == /* ]] || die "protect list requires absolute paths or ~/paths: $line"
    PROTECT+=("${line%/}")
  done <"$f" || die "cannot read protect list $f"
}

is_protected() {
  local rule ancestor prefix
  for rule in "${PROTECT[@]}"; do
    ancestor=$1
    while :; do
      # shellcheck disable=SC2053  # rules are globs on purpose
      [[ $ancestor == $rule ]] && return 0
      [[ -n $ancestor ]] || break
      ancestor=${ancestor%/*}
    done
    [[ $rule == "$1"/* ]] && return 0
    if [[ -d $1 && $rule == *[\*\?\[]* ]]; then
      prefix=${rule%%[\*\?\[]*}
      if [[ $prefix == "$1/"* || "$1/" == "$prefix"* ]]; then
        # A matching descendant may be hidden or contain a newline. Keep the
        # whole candidate when a glob could select a descendant.
        return 0
      fi
    fi
  done
  return 1
}

# Validate the parent without following a final symlink. This also rejects
# symlinked intermediate directories and lexical aliases such as "..".
user_path() {
  local p=$1 parent base
  [[ $p == /* && $(stat -c %u -- "$p" 2>/dev/null) == "$EUID" ]] || return 1
  parent=${p%/*} base=${p##*/}
  [[ -n $parent && -n $base && $base != . && $base != .. ]] || return 1
  [[ $(realpath -e -- "$parent") == "$parent" && $p != "$HOME" ]]
}

contains_mount() {
  local p=$1 _id _parent _device _root mount _rest
  [[ -r /proc/self/mountinfo ]] || return 0
  while read -r _id _parent _device _root mount _rest; do
    printf -v mount '%b' "$mount"
    [[ $mount == "$p" || $mount == "$p"/* ]] && return 0
  done </proc/self/mountinfo
  return 1
}

can_remove_path() {
  local p=$1
  user_path "$p" && ! is_protected "$p" || return 1
  if [[ -d $p && ! -L $p ]]; then ! contains_mount "$p"; fi
}

remove_path() {
  local p=$1 mode=${2:-delete} bytes=${3:-}
  [[ -e $p || -L $p ]] || return 0
  can_remove_path "$p" || { err "kept protected or unsafe path: $p"; return 1; }
  [[ -n $bytes ]] || bytes=$(size_of "$p")
  if [[ $mode == trash ]]; then
    if ! has gio || ! gio trash -- "$p"; then
      err "could not move to the Trash: $p"
      return 1
    fi
    oplog trash "$p" "$bytes"
    return 0
  fi
  rm -rf --one-file-system -- "$p" || return 1
  oplog delete "$p" "$bytes"
}

# command-line counters are bounded decimal integers (no Bash expressions).
valid_count() { [[ $1 =~ ^(0|[1-9][0-9]{0,6})$ ]]; }

# bar PERCENT [WIDTH] -> ███████░░░ coloured by level
bar() {
  local pct=${1%.*} width=${2:-20} fill colour=$C_G
  ((pct < 0)) && pct=0
  ((pct > 100)) && pct=100
  ((pct >= 70)) && colour=$C_Y
  ((pct >= 90)) && colour=$C_R
  fill=$((pct * width / 100))
  local on off # tr is not UTF-8 aware, so build the blocks with parameter expansion
  printf -v on '%*s' "$fill" ''
  printf -v off '%*s' $((width - fill)) ''
  printf '%s%s%s%s' "$colour" "${on// /█}" "$C_0" "${off// /░}"
}

# user_dir DOWNLOAD Downloads -> the XDG user folder; xdg-user-dir answers $HOME when it is unset
user_dir() {
  local d
  d=$(xdg-user-dir "$1" 2>/dev/null)
  [[ $d == /* && $d != "$HOME" && $d != "$HOME/" ]] || d=$HOME/$2
  printf '%s\n' "$d"
}

days_old() { echo $((($(date +%s) - $(stat -c %Y -- "$1" 2>/dev/null || date +%s)) / 86400)); }

# ver_num "shotcut-linux-x86_64-26.11.15.AppImage" -> "26.11.15" (architecture tags are not versions)
ver_num() {
  local s
  s=$(sed -E 's/(x86[_-]64|amd64|aarch64|arm64|armv7l?|armhf|i[3-6]86)//Ig' <<<"$1")
  grep -oE '[0-9]+(\.[0-9]+)+' <<<"$s" | head -n1 | grep . || grep -oE '[0-9]+' <<<"$s" | head -n1
}
# ver_gt A B -> 0 when A is a newer version than B
ver_gt() {
  local a b
  a=$(ver_num "$1") b=$(ver_num "$2")
  [[ -n $a && -n $b && $a != "$b" ]] && [[ $(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n1) == "$a" ]]
}
