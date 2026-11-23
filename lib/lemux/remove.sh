# shellcheck shell=bash
# remove.sh — remove an exact application identifier and recoverable leftovers.

app_file_matches() {
  local name=${1#.} id=${2,,}
  name=${name,,}
  name=${name%.desktop}
  [[ $name == "$id" || $name == *."$id" ]]
}

remove_leftovers() {
  local id=$1 dir f
  for dir in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
    "$HOME/.local/bin" "$XDG_DATA_HOME/applications" "$XDG_CONFIG_HOME/autostart" "$HOME/.var/app"; do
    [[ $dir != "$HOME" && "$HOME/" != "$dir/"* ]] || continue
    for f in "$dir"/* "$dir"/.[!.]*; do
      [[ -e $f || -L $f ]] || continue
      case $f in
        "$XDG_DATA_HOME/applications"|"$XDG_DATA_HOME/Trash"|"$XDG_DATA_HOME/icons"|"$XDG_DATA_HOME/fonts"|\
        "$LEMUX_CONF"|"$LEMUX_STATE"|"$XDG_DATA_HOME/lemux"|"$XDG_DATA_HOME/mime"|"$XDG_CONFIG_HOME/autostart"|"$XDG_CONFIG_HOME/systemd")
          continue ;;
      esac
      app_file_matches "${f##*/}" "$id" && can_remove_path "$f" && printf '%s\0' "$f"
    done
  done
  local legacy=$HOME/.$id
  if [[ -e $legacy || -L $legacy ]]; then
    local reserved
    for reserved in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
      "$HOME/.local" "$HOME/.var" "$HOME/.git" "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.password-store"; do
      [[ $reserved == "$legacy" || $reserved == "$legacy"/* ]] && return 0
    done
    [[ -d $legacy ]] && can_remove_path "$legacy" && printf '%s\0' "$legacy"
  fi
  return 0
}

remove_mime_filter() {
  awk -v id="${1,,}" '
    /^\[/ || /^[[:space:]]*#/ || !/=/{ print; next }
    {
      sep = index($0, "="); n = split(substr($0, sep + 1), ids, ";")
      keep = ""; edited = 0
      for (i = 1; i <= n; i++) {
        if (ids[i] == "") continue
        name = tolower(ids[i]); sub(/\.desktop$/, "", name)
        suffix = substr(name, length(name) - length(id))
        if (name == id || suffix == "." id) edited = 1
        else keep = keep ids[i] ";"
      }
      if (!edited) print
      else if (keep != "") print substr($0, 1, sep) keep
    }'
}

remove_user_data() {
  local id=$1 apply=$2 f stage mime=$XDG_CONFIG_HOME/mimeapps.list
  local -a files
  mapfile -d '' -t files < <(remove_leftovers "$id")
  for f in "${files[@]}"; do
    note "Trash: ${f/#$HOME/\~}"
    if ((apply)); then remove_path "$f" trash || return 1; fi
  done
  if [[ -f $mime && ! -L $mime ]] && can_remove_path "$mime"; then
    stage=$LEMUX_TMP/mimeapps
    remove_mime_filter "$id" <"$mime" >"$stage" || return 1
    if ! cmp -s -- "$stage" "$mime"; then
      note "Remove matching entries from ${mime/#$HOME/\~}"
      if ((apply)); then
        stage=$(mktemp -- "${mime%/*}/.lemux-mime.XXXXXX") || return 1
        if ! remove_mime_filter "$id" <"$mime" >"$stage" || ! mv -fT -- "$stage" "$mime"; then
          rm -f -- "$stage"
          return 1
        fi
        oplog edit "$mime"
      fi
    fi
  fi
}

cmd_remove() {
  local id="" apply=0 scoped=0 purge=0 arg
  for arg in "$@"; do
    case $arg in
      --apply) apply=1 ;;
      --appimage) scoped=1 ;;
      --purge) purge=1 ;;
      -h | --help) help_remove; return 0 ;;
      -*) usage_error "remove: unknown option '$arg'" ;;
      *) [[ -z $id ]] || usage_error "remove: one application at a time"; id=$arg ;;
    esac
  done
  if ((scoped)); then
    app_id "$id" || usage_error "remove --appimage needs a managed AppImage ID"
    [[ -f $LEMUX_APPS/$id/$id.AppImage ]] || { err "$id is not a managed AppImage"; return 1; }
    load_protect
    if ((apply)); then
      local -a options=()
      ((purge)) && options+=(--purge)
      app_remove "$id" "${options[@]}"
      return
    fi
    section "Dry run: managed AppImage '$id' (add --apply)"
    note "Remove managed versions, menu entry and command link"
    if ((purge)); then remove_user_data "$id" 0; fi
    return
  fi
  ((purge == 0)) || usage_error "--purge is for --appimage"
  [[ $id =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]{3,127}$ ]] || usage_error "remove: give an exact application ID (at least 4 characters)"
  [[ ${id,,} != lemux ]] || usage_error "to remove lemux itself run 'make uninstall' in its source folder"
  load_protect

  local native=0 managed=0 snap=0 flatpak_scope
  local -a scopes=()
  pkg_is_installed "$id" && native=1
  [[ $id =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && -d $LEMUX_APPS/$id ]] && managed=1
  if has snap && snap list "$id" >/dev/null 2>&1; then snap=1; fi
  if has flatpak; then
    for flatpak_scope in --user --system; do
      if flatpak info "$flatpak_scope" --show-ref "$id" 2>/dev/null | grep -qF "app/$id/"; then
        scopes+=("$flatpak_scope")
      fi
    done
  fi

  if ((apply)); then
    section "Removing $id"
    if any_running "$id"; then err "$id is running; close it first"; return 1; fi
  else
    section "Dry run for '$id' (add --apply)"
  fi
  if ((native)); then note "Native package ($PKG): $id"; fi
  if ((managed)); then note "Managed AppImage: $id"; fi
  if ((snap)); then note "Snap: $id"; fi
  for flatpak_scope in "${scopes[@]}"; do note "Flatpak $flatpak_scope: $id"; done

  if ((apply)); then
    if ((native)); then
      pkg_purge "$id" || { err "native package removal failed"; return 1; }
      if pkg_is_installed "$id"; then err "$id is still installed"; return 1; fi
      oplog uninstall "$PKG:$id"
    fi
    for flatpak_scope in "${scopes[@]}"; do
      local -a yes=()
      [[ $LEMUX_YES != 1 ]] || yes=(-y)
      flatpak uninstall "$flatpak_scope" "${yes[@]}" "$id" || return 1
      oplog uninstall "flatpak:$id ($flatpak_scope)"
    done
    if ((snap)); then
      as_root snap remove "$id" || return 1
      oplog uninstall "snap:$id"
    fi
    if ((managed)); then app_remove "$id" || return 1; fi
  fi
  if ((!native && !managed && !snap && ${#scopes[@]} == 0)); then note "Nothing found in installed applications for '$id'."; fi
  remove_user_data "$id" "$apply"
}

help_remove() {
  cat <<'EOF_HELP'
Usage: lemux remove <id> [--apply]
       lemux remove --appimage <id> [--apply] [--purge]

--appimage limits removal to a managed AppImage and its integration. Add
--purge to include its matching user data. app remove is a compatibility alias.

Finds the exact native package, Flatpak, Snap or managed AppImage ID. Also
lists matching user files by exact name or reverse-domain suffix. With
--apply, uninstalls the application, moves those files to the Trash and
removes matching file associations. Close the app first.
EOF_HELP
}
