# bash completion for lemux                                  -*- shell-script -*-
# shellcheck shell=bash

_lemux_apps() {
  local d
  for d in "${XDG_DATA_HOME:-$HOME/.local/share}"/lemux/apps/*/; do
    [[ -d $d ]] && basename "$d"
  done
}

_lemux() {
  local cur=${COMP_WORDS[COMP_CWORD]} cmd="" sub="" i word
  for ((i = 1; i < COMP_CWORD; i++)); do
    word=${COMP_WORDS[i]}
    [[ $word == -* ]] && continue
    if [[ -z $cmd ]]; then cmd=$word; elif [[ -z $sub ]]; then sub=$word; fi
  done
  local words=""
  case $cmd in
    '') words="status check why analyze history clean purge installers remove app update optimize -y --yes --no-color -h --help -V --version" ;;
    status) words="--watch -n --help" ;;
    why) words="--kill --pid --help" ;;
    analyze) compopt -o dirnames 2>/dev/null; words="--top --help" ;;
    history) words="--json -n --help" ;;
    purge) compopt -o dirnames 2>/dev/null; words="--apply --all --days --help" ;;
    installers) words="--apply --all --help" ;;
    optimize) words="--apply --help" ;;
    check) words="--fix --help" ;;
    clean) words="--basic --browser --deep --logs --bash-history --apply --trash --orphans --journal --packages --help" ;;
    remove | uninstall) words="--appimage --purge --apply --help" ;;
    update) words="--apps --help" ;;
    app)
      case $sub in
        '') words="install update list rollback remove --help" ;;
        install)
          compopt -o filenames 2>/dev/null
          mapfile -t COMPREPLY < <(compgen -W "--from --name --move" -- "$cur"; compgen -d -- "$cur"
            compgen -f -X '!*.[Aa]pp[Ii]mage' -- "$cur")
          return 0
          ;;
        update) words="--force --from $(_lemux_apps)" ;;
        rollback) words="$(_lemux_apps)" ;;
        remove) words="--apply --purge $(_lemux_apps)" ;;
      esac
      ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}
complete -F _lemux lemux
