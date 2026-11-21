# shellcheck shell=bash
# history.sh — read the JSON Lines operation log, including legacy TSV entries.

cmd_history() {
  local json=0 lines=40
  while (($#)); do
    case $1 in
      --json) json=1 ;;
      -n) lines=${2:-}; shift ;;
      -h | --help) help_history; return 0 ;;
      *) usage_error "history: unknown option '$1'" ;;
    esac
    shift
  done
  valid_count "$lines" || usage_error "history: -n needs a nonnegative integer"
  if [[ ! -s $LEMUX_OPLOG ]]; then
    if ((json)); then say '[]'; else say "No operations logged yet."; fi
    return 0
  fi
  need jq
  local filter='[inputs | if startswith("{") then fromjson else
    split("\t") | {time: .[0], command: .[1], action: .[2],
    bytes: (.[3] | tonumber? // null), path: (.[4:] | join("\t"))}
    end]'
  # A missing size in the TSV format was written as a dash.
  if ((json)); then
    tail -n "$lines" -- "$LEMUX_OPLOG" | jq -Rnc "$filter"
  else
    tail -n "$lines" -- "$LEMUX_OPLOG" | jq -Rn -r "$filter"'[] |
      "\(.time[:16])  \(.command)  \(.action)  \(.bytes // "-")  \(.path | @json)"' || return 1
    say "  log: ${LEMUX_OPLOG/#$HOME/\~}"
  fi
}

help_history() {
  cat <<'EOF_HELP'
Usage: lemux history [-n N] [--json]

Lists what lemux deleted, moved to the Trash, uninstalled or optimized, newest last,
from ~/.local/state/lemux/operations.log. Set LEMUX_NO_OPLOG=1 to stop logging.

  -n N     how many entries (default 40)
  --json   machine-readable output
EOF_HELP
}
