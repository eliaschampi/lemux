# shellcheck shell=bash
# app.sh — install and inspect type-2 AppImages without running their payloads.

LEMUX_APPS=$XDG_DATA_HOME/lemux/apps
APPS_MENU=$XDG_DATA_HOME/applications

app_id() { [[ $1 =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#1} -le 100 ]]; }
app_repo() { [[ $1 =~ ^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$ && ${1#*/} != . && ${1#*/} != .. ]]; }

app_lock() {
  load_protect
  need flock
  mkdir -p -- "$LEMUX_APPS" || return 1
  [[ -O $LEMUX_APPS && $(realpath -e -- "$LEMUX_APPS") == "$LEMUX_APPS" ]] ||
    die "AppImage directory must be owned by you and use real directories"
  exec {APP_LOCK}<"$LEMUX_APPS" || return 1
  flock -x "$APP_LOCK"
}

app_pointer() {
  local link
  link=$(readlink -- "$1") || return 1
  [[ $link =~ ^\.versions/[A-Za-z0-9]+/app\.AppImage$ ]] || return 1
  printf '%s\n' "$link"
}

app_meta() {
  local dir=$1 pointer file=$1/meta
  if pointer=$(app_pointer "$dir/${dir##*/}.AppImage"); then file=$dir/${pointer%/*}/meta; fi
  awk -v key="$2=" 'index($0, key) == 1 { print substr($0, length(key)+1); exit }' "$file" 2>/dev/null
}

app_running() {
  local pid env
  for pid in $(pgrep -u "$EUID"); do
    [[ -r /proc/$pid/environ ]] || continue
    while IFS= read -r -d '' env; do
      [[ $env == "APPIMAGE=$1" || $env == "APPIMAGE=$2" ]] && return 0
    done 2>/dev/null <"/proc/$pid/environ" || true
  done
  return 1
}

app_arch_regex() {
  case $(uname -m) in
    x86_64) say 'x86_64|amd64|x64' ;;
    aarch64 | arm64) say 'aarch64|arm64' ;;
    i?86) say 'i[3-6]86' ;;
    armv7*) say 'armv7|armhf' ;;
    *) uname -m ;;
  esac
}

app_release() {
  local -a auth=()
  local repo=$1 release
  app_repo "$repo" || usage_error "invalid GitHub repository: $repo"
  [[ -z ${GITHUB_TOKEN:-} ]] || auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  release=$(curl -q -fsS --proto '=https' --connect-timeout 8 --max-time 30 "${auth[@]}" \
    -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/releases/latest") || return 1
  jq -er --arg arch "$(app_arch_regex)" '
    .tag_name as $tag | [.assets[]
      | select(.name | test("^[a-zA-Z0-9_.+-]+\\.appimage$"; "i"))
      | select((.name | test($arch; "i")) or
        (.name | test("aarch64|arm64|armhf|armv7|i[3-6]86|x86_64|amd64|x64"; "i") | not))
      | select(.browser_download_url | startswith("https://github.com/"))
      | {rank: (if (.name | test($arch; "i")) then 0 else 1 end),
         url: .browser_download_url, name, digest: (.digest // "-"), tag: $tag}]
    | sort_by(.rank) | group_by(.rank) | first
    | if length == 1 then .[0] | [.url, .name, .digest, .tag] | @tsv
      else error("expected one matching AppImage asset") end' <<<"$release"
}

app_fetch() {
  local url=$1 digest=$2 dst=$3
  [[ $digest =~ ^sha256:[0-9a-fA-F]{64}$ ]] || { err "GitHub did not publish a valid SHA-256 digest"; return 1; }
  say "Downloading ${url##*/}"
  curl -q -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 600 \
    -o "$dst" "$url" || return 1
  local hash
  hash=$(sha256sum <"$dst") || return 1
  [[ ${hash%% *} == "${digest#sha256:}" ]] || { err "AppImage checksum mismatch"; return 1; }
}

app_offset() {
  # The payload begins after the ELF section table or the last section if farther.
  local img=$1 offset last size
  [[ $(od -An -tx1 -N4 -- "$img" | tr -d ' \n') == 7f454c46 &&
     $(od -An -tx1 -j8 -N3 -- "$img" | tr -d ' \n') == 414902 ]] || return 1
  offset=$(LC_ALL=C readelf -hW -- "$img" 2>/dev/null |
    awk '/Start of section headers:/{o=$5} /Size of section headers:/{s=$5} /Number of section headers:/{n=$5}
      END { if (o > 0 && s > 0 && n > 0) printf "%.0f\n", o+s*n; else exit 1 }') || return 1
  last=$(LC_ALL=C readelf -SW -- "$img" 2>/dev/null |
    sed -nE 's/^ *\[ *[0-9]+\] +[^ ]+ +[^ ]+ +[[:xdigit:]]+ +([[:xdigit:]]+) +([[:xdigit:]]+) .*/\1 \2/p' | tail -n1)
  if [[ $last =~ ^([0-9a-fA-F]{1,12})\ ([0-9a-fA-F]{1,12})$ ]]; then
    last=$((16#${BASH_REMATCH[1]} + 16#${BASH_REMATCH[2]}))
  else
    last=0
  fi
  size=$(stat -c %s -- "$img") || return 1
  [[ $offset =~ ^[0-9]{1,15}$ ]] || return 1
  ((last > offset)) && offset=$last
  ((offset < size)) || return 1
  printf '%s\n' "$offset"
}

desktop_key() {
  awk -v key="$1=" '/^\[/ { main=($0 == "[Desktop Entry]") }
    main && index($0,key)==1 { print substr($0,length(key)+1); exit }' "$2"
}

app_inspect() {
  local img=$1 original=$2 w=$3 hint=${4:-} offset entries entry icon
  offset=$(app_offset "$img") || { err "$original is not an AppImage (type 2)"; return 1; }
  need unsquashfs
  entries=$(timeout 12 unsquashfs -processors 1 -offset "$offset" -ls -max-depth 1 "$img" '*.desktop') || return 1
  entry=$(sed -nE 's/^squashfs-root\/([A-Za-z0-9_.+-]+\.desktop)$/\1/p' <<<"$entries" | head -n1)
  [[ -n $entry ]] || { err "$original has no desktop metadata"; return 1; }
  # Older unsquashfs versions use shell globs. Only literal trusted names reach -cat.
  (ulimit -f 128; timeout 12 unsquashfs -processors 1 -offset "$offset" -cat "$img" "$entry") >"$w/desktop" ||
    { err "cannot read AppImage desktop metadata"; return 1; }
  A_NAME=$(desktop_key Name "$w/desktop")
  [[ -n $A_NAME && $A_NAME != *[[:cntrl:]]* ]] || { err "invalid AppImage display name"; return 1; }
  A_VERSION=$(ver_num "$(desktop_key X-AppImage-Version "$w/desktop")")
  [[ -n $A_VERSION ]] || A_VERSION=$(ver_num "$hint")
  [[ -n $A_VERSION ]] || A_VERSION=$(ver_num "$original")
  [[ -n $A_VERSION ]] || A_VERSION=$(date -r "$img" +%Y.%m.%d)
  icon=$(desktop_key Icon "$w/desktop")
  if [[ $icon =~ ^[A-Za-z0-9_.+-]+$ ]]; then
    if ! (ulimit -f 4096; timeout 12 unsquashfs -processors 1 -offset "$offset" -cat "$img" "$icon.png") \
      >"$w/icon.png" 2>/dev/null || [[ $(od -An -tx1 -N8 -- "$w/icon.png" | tr -d ' \n') != 89504e470d0a1a0a ]]; then
      rm -f -- "$w/icon.png"
    fi
  fi
}

app_stage() {
  local dir=$1 source=$2 original=$3 repo=$4 hint=${5:-}
  need readelf timeout
  mkdir -p -- "$dir/.versions" || return 1
  [[ ! -L $dir/.versions ]] || return 1
  APP_STAGE=$(mktemp -d -- "$dir/.versions/XXXXXXXX") || return 1
  if ! cp --reflink=auto -- "$source" "$APP_STAGE/app.AppImage" ||
     ! chmod 755 -- "$APP_STAGE/app.AppImage" ||
     ! app_inspect "$APP_STAGE/app.AppImage" "$original" "$APP_STAGE" "$hint" ||
     ! printf 'name=%s\nversion=%s\nsource=%s\n' "$A_NAME" "$A_VERSION" "$repo" >"$APP_STAGE/meta"; then
    rm -rf -- "$APP_STAGE"
    return 1
  fi
  rm -f -- "$APP_STAGE/desktop"
}

app_link() {
  local target=$1 path=$2 tmp
  tmp=$(mktemp -d -- "${path%/*}/.lemux-link.XXXXXXXX") || return 1
  if ! ln -s -- "$target" "$tmp/link" || ! mv -fT -- "$tmp/link" "$path"; then
    rm -rf -- "$tmp"
    return 1
  fi
  rmdir -- "$tmp"
}

desktop_path() {
  local path=$1
  path=${path//\\/\\\\}
  path=${path//\"/\\\"}
  path=${path//\$/\\\$}
  path=${path//\`/\\\`}
  path=${path//%/%%}
  printf '%s' "${path//\\/\\\\}"
}

app_launcher() {
  local dir=$1 id=${1##*/} entry stage icon=""
  [[ $dir != *[[:cntrl:]]* ]] || { err "desktop launchers need a path without control characters"; return 1; }
  mkdir -p -- "$APPS_MENU" || return 1
  [[ $(realpath -e -- "$APPS_MENU") == "$APPS_MENU" ]] || return 1
  entry=$APPS_MENU/lemux-$id.desktop
  if [[ -e $entry || -L $entry ]]; then can_remove_path "$entry" || return 1; fi
  if [[ -f $APP_STAGE/icon.png ]]; then
    if [[ -e $dir/icon.png || -L $dir/icon.png ]]; then can_remove_path "$dir/icon.png" || return 1; fi
    cp --remove-destination -- "$APP_STAGE/icon.png" "$dir/icon.png" || return 1
    icon=$dir/icon.png
  fi
  stage=$(mktemp -- "$APPS_MENU/.lemux-desktop.XXXXXXXX") || return 1
  if ! { printf '[Desktop Entry]\nType=Application\nName=%s\nExec="%s"\nX-Lemux-Id=%s\n' \
           "$A_NAME" "$(desktop_path "$dir/$id.AppImage")" "$id"
         if [[ -n $icon ]]; then printf 'Icon=%s\n' "${icon//\\/\\\\}"; fi
       } >"$stage" || ! mv -fT -- "$stage" "$entry"; then
    rm -f -- "$stage"
    return 1
  fi
}

app_activate() {
  local dir=$1 next=$2 id=${1##*/} live current backup
  live=$dir/$id.AppImage
  current=$(app_pointer "$live") || current=""
  if [[ -f $live && -z $current ]]; then
    # Migrate a previous installation at the same stable command path.
    backup=$(mktemp -d -- "$dir/.versions/XXXXXXXX") || return 1
    ln -- "$live" "$backup/app.AppImage" && cp -- "$dir/meta" "$backup/meta" || return 1
    current=.versions/${backup##*/}/app.AppImage
  fi
  [[ -z $current ]] || app_link "$current" "$dir/.previous" || return 1
  app_link "$next" "$live" || return 1
  for backup in "$dir"/.versions/*/; do
    backup=${backup%/}
    [[ ".versions/${backup##*/}/app.AppImage" == "$current" ||
       ".versions/${backup##*/}/app.AppImage" == "$next" ]] && continue
    can_remove_path "$backup" && rm -rf --one-file-system -- "$backup"
  done
  return 0
}

app_install() {
  local arg="" repo="" name="" move=0 local_file=0 img file release url digest tag="" id dir
  while (($#)); do
    case $1 in
      --from) (($# > 1)) || usage_error "--from needs owner/repo"; repo=$2; shift ;;
      --name) (($# > 1)) || usage_error "--name needs a value"; name=$2; shift ;;
      --move) move=1 ;;
      -*) usage_error "app install: unknown option '$1'" ;;
      *) [[ -z $arg ]] || usage_error "app install takes one file or repository"; arg=$1 ;;
    esac
    shift
  done
  [[ -n $arg ]] || usage_error "app install needs a file or GitHub repository"
  [[ -z $repo ]] || app_repo "$repo" || usage_error "--from needs owner/repo"
  app_lock || return 1
  if [[ -f $arg ]]; then
    img=$(realpath -e -- "$arg") || return 1
    file=${arg##*/} local_file=1
  else
    [[ -z $repo && $move == 0 ]] || usage_error "--from and --move apply to local files"
    repo=${arg#https://github.com/}
    repo=${repo%/}
    need curl jq
    release=$(app_release "$repo") || return 1
    IFS=$'\t' read -r url file digest tag <<<"$release"
    img=$LEMUX_TMP/download.AppImage
    app_fetch "$url" "$digest" "$img" || return 1
  fi

  # Inspect private staging first so the inferred ID cannot affect lookup paths.
  local scratch=$LEMUX_TMP/inspect
  mkdir -- "$scratch" || return 1
  need readelf timeout
  app_inspect "$img" "$file" "$scratch" "$tag" || return 1
  id=$(slug "${name:-$A_NAME}")
  app_id "$id" || usage_error "cannot derive an application ID; use --name"
  dir=$LEMUX_APPS/$id
  is_protected "$dir" && { err "protected path: $dir"; return 1; }
  mkdir -- "$dir" || { err "$id could not be created (check whether it is already installed)"; return 1; }
  if ! app_stage "$dir" "$img" "$file" "$repo" "$tag" ||
     ! app_launcher "$dir" ||
     ! app_activate "$dir" ".versions/${APP_STAGE##*/}/app.AppImage"; then
    rm -rf -- "$dir"
    return 1
  fi
  mkdir -p -- "$HOME/.local/bin" || return 1
  local link=$HOME/.local/bin/$id
  if [[ ! -e $link && ! -L $link ]] && ! has "$id" && ! is_protected "$link"; then
    ln -s -- "$dir/$id.AppImage" "$link" || return 1
  fi
  oplog install "appimage:$id $A_VERSION"
  ok "installed $A_NAME $A_VERSION as '$id'"
  if ((move && local_file)); then remove_path "$img" trash || return 1; fi
}

app_update_one() {
  local id=$1 file=$2 force=$3 repo=$4 dir=$LEMUX_APPS/$1
  local current release url name digest tag="" img candidate
  app_id "$id" || usage_error "invalid application ID: $id"
  [[ -d $dir && ! -L $dir && -f $dir/$id.AppImage ]] || { err "$id is not installed"; return 1; }
  can_remove_path "$dir" || { err "protected or unsafe path: $dir"; return 1; }
  current=$(app_meta "$dir" version)
  if [[ -z $repo ]] && app_pointer "$dir/$id.AppImage" >/dev/null; then repo=$(app_meta "$dir" source); fi
  if [[ -n $file ]]; then
    img=$(realpath -e -- "$file") || return 1
    name=${file##*/}
  else
    [[ -n $repo ]] || { note "$id: pass a local AppImage or select an update source with --from"; return 0; }
    need curl jq
    release=$(app_release "$repo") || return 1
    IFS=$'\t' read -r url name digest tag <<<"$release"
    candidate=$(ver_num "$tag")
    if [[ -n $candidate ]] && ! ver_gt "$candidate" "$current" && ((!force)); then
      ok "$id $current is up to date"
      return 0
    fi
    img=$LEMUX_TMP/download.AppImage
    app_fetch "$url" "$digest" "$img" || return 1
  fi
  if app_running "$dir/$id.AppImage" "$(realpath -e -- "$dir/$id.AppImage")"; then
    err "$id is running; close it first"
    return 1
  fi
  app_stage "$dir" "$img" "$name" "$repo" "$tag" || return 1
  if ((!force)); then
    if [[ $(app_meta "$dir" name) != "$A_NAME" ]]; then
      err "AppImage name differs; use --force only after verifying the source"
      rm -rf -- "$APP_STAGE"
      return 1
    fi
    if ! ver_gt "$A_VERSION" "$current"; then
      note "$id $current was kept (candidate: $A_VERSION)"
      rm -rf -- "$APP_STAGE"
      return 0
    fi
  fi
  app_launcher "$dir" && app_activate "$dir" ".versions/${APP_STAGE##*/}/app.AppImage" || return 1
  oplog update "appimage:$id $current -> $A_VERSION"
  ok "$id $current → $A_VERSION"
}

app_update() {
  local -a ids=()
  local file="" force=0 repo="" rc=0 dir id
  while (($#)); do
    case $1 in
      --force) force=1 ;;
      --from) (($# > 1)) || usage_error "--from needs owner/repo"; repo=$2; shift
        app_repo "$repo" || usage_error "--from needs owner/repo" ;;
      -*) usage_error "app update: unknown option '$1'" ;;
      *.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee]) [[ -z $file ]] || usage_error "provide one AppImage file"; file=$1 ;;
      *) ids+=("$1") ;;
    esac
    shift
  done
  if [[ -n $file || -n $repo ]]; then
    (("${#ids[@]}" == 1)) || usage_error "updating with a file or --from needs one application ID"
  fi
  if (("${#ids[@]}" == 0)); then
    for dir in "$LEMUX_APPS"/*/; do
      dir=${dir%/}
      id=${dir##*/}
      if app_id "$id" && [[ -f $dir/$id.AppImage ]]; then ids+=("$id"); fi
    done
  fi
  (("${#ids[@]}")) || { say "No AppImages installed with lemux."; return 0; }
  app_lock || return 1
  for id in "${ids[@]}"; do app_update_one "$id" "$file" "$force" "$repo" || rc=1; done
  return "$rc"
}

app_list() {
  local d id any=0
  (($# == 0)) || usage_error "app list takes no arguments"
  for d in "$LEMUX_APPS"/*/; do
    d=${d%/}
    id=${d##*/}
    [[ -f $d/$id.AppImage && ! -L $d ]] || continue
    if ((!any)); then printf '%-20s %-16s %s\n' ID VERSION SOURCE; any=1; fi
    printf '%-20s %-16s %s\n' "$id" "$(app_meta "$d" version)" "$(app_meta "$d" source)"
  done
  if ((!any)); then say "No AppImages installed with lemux."; fi
}

app_rollback() {
  local id=${1:-} dir backup live
  if (($# != 1)) || ! app_id "$id"; then usage_error "usage: lemux app rollback <id>"; fi
  dir=$LEMUX_APPS/$id live=$LEMUX_APPS/$id/$id.AppImage
  app_lock || return 1
  can_remove_path "$dir" || { err "protected or unsafe path: $dir"; return 1; }
  if app_running "$live" "$(realpath -e -- "$live")"; then err "$id is running; close it first"; return 1; fi
  if ! backup=$(app_pointer "$dir/.previous") || [[ ! -f $dir/$backup ]]; then
    err "$id has no managed rollback available"
    return 1
  fi
  app_activate "$dir" "$backup" || return 1
  oplog rollback "appimage:$id"
  ok "restored $id $(app_meta "$dir" version)"
}

app_remove() {
  local id=${1:-} purge=${2:-} dir live link entry
  if ! app_id "$id" || (($# > 2)) || [[ -n $purge && $purge != --purge ]]; then
    usage_error "usage: lemux app remove <id> [--purge]"
  fi
  dir=$LEMUX_APPS/$id live=$LEMUX_APPS/$id/$id.AppImage
  app_lock || return 1
  if [[ ! -d $dir || -L $dir ]] || ! can_remove_path "$dir"; then
    err "missing, protected or unsafe path: $dir"
    return 1
  fi
  if app_running "$live" "$(realpath -e -- "$live")"; then err "$id is running; close it first"; return 1; fi
  entry=$APPS_MENU/lemux-$id.desktop
  if [[ -e $entry || -L $entry ]]; then
    can_remove_path "$entry" || { err "protected or unsafe path: $entry"; return 1; }
  fi
  remove_path "$dir" || return 1
  remove_path "$entry" || return 1
  for link in "$HOME"/.local/bin/*; do
    if [[ -L $link && $(readlink -- "$link") == "$live" ]] && ! is_protected "$link"; then
      remove_path "$link" || return 1
    fi
  done
  oplog uninstall "appimage:$id"
  ok "removed $id"
  if [[ $purge == --purge ]]; then remove_user_data "$id" 1; fi
}

cmd_app() {
  local sub=${1:-help}
  shift || true
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then help_app; return 0; fi
  case $sub in
    install | add) app_install "$@" ;;
    update | upgrade) app_update "$@" ;;
    list | ls) app_list "$@" ;;
    rollback) app_rollback "$@" ;;
    remove | rm | uninstall) app_remove "$@" ;;
    -h | --help | help) help_app ;;
    *) usage_error "app: unknown command '$sub' (see: lemux app --help)" ;;
  esac
}

help_app() {
  cat <<'EOF_HELP'
Usage: lemux app <command>

  install <file.AppImage | owner/repo> [--from owner/repo] [--name id] [--move]
  update [id ...] [--force]
  update <id> <file.AppImage>
  update <id> --from owner/repo
  list
  rollback <id>
  remove <id> [--purge]

AppImages are inspected without running them. GitHub assets need a published
SHA-256 digest. --from explicitly selects a GitHub source for future updates.
Local updates take an explicit file. --move sends the original to the Trash
after installation. --purge sends matching user files to the Trash as well.
EOF_HELP
}
