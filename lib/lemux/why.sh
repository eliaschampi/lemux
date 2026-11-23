# shellcheck shell=bash
# Local listener inspection. Retain only PIDs reported by ss for this socket.
why_sockets() {
  local -a filter=()
  [[ -z $1 ]] || filter=("sport = :$1")
  LC_ALL=C ss -H -lntup "${filter[@]}"
}

why_pids() {
  awk '{while (match($0, /,pid=[0-9]+,fd=[0-9]+/)) {
    part=substr($0,RSTART+5,RLENGTH-5); sub(/,.*/,"",part); print part
    $0=substr($0,RSTART+RLENGTH)
  }}' | sort -un
}

why_started() {
  local stat
  IFS= read -r stat <"/proc/$1/stat" || return 1
  # comm may include spaces and parentheses. starttime is field 22.
  awk '{print $20}' <<<"${stat##*) }"
}

# Match a real process file descriptor to a kernel socket inode before signalling.
why_owns_socket() {
  local port=$1 pid=$2 rows fd socket inode
  local -A inodes=()
  rows=$(LC_ALL=C ss -H -lnetu "sport = :$port") || return 1
  while read -r inode; do
    [[ -z $inode ]] || inodes[$inode]=1
  done < <(awk '{for (i=1;i<=NF;i++) if ($i ~ /^ino:[0-9]+$/) print substr($i,5)}' <<<"$rows")
  for fd in /proc/"$pid"/fd/*; do
    socket=$(readlink "$fd") || continue
    if [[ $socket =~ ^socket:\[([0-9]+)\]$ && -n ${inodes[${BASH_REMATCH[1]}]:-} ]]; then return 0; fi
  done
  return 1
}

why_process() {
  local pid=$1 parent=$1 depth=0 line name
  section "PID $pid"
  ps -ww -p "$pid" -o user=,args= || { note "process exited"; return; }
  for name in exe cwd; do
    if line=$(readlink "/proc/$pid/$name"); then printf '  %s: %q\n' "$name" "$line"; fi
  done
  while ((parent > 1 && depth < 32)); do
    parent=$(ps -p "$parent" -o ppid= | tr -d ' ') || break
    [[ $parent =~ ^[1-9][0-9]*$ ]] || break
    line=$(ps -p "$parent" -o comm=) || break
    printf '  parent: %s %q\n' "$parent" "$line"
    ((depth++))
  done
}

cmd_why() {
  local port="" stop=0 target="" sockets pid start="" current
  while (($#)); do
    case $1 in
      -h | --help) help_why; return 0 ;;
      --kill) stop=1 ;;
      --pid) [[ ${2:-} =~ ^[1-9][0-9]{0,8}$ ]] || usage_error "--pid requires a positive PID"
        target=$2; shift ;;
      *) [[ -z $port && $1 =~ ^[0-9]{1,5}$ ]] || usage_error "why: supply one port (1-65535)"
        port=$((10#$1))
        ((port >= 1 && port <= 65535)) || usage_error "port must be 1-65535" ;;
    esac
    shift
  done
  if ((stop)) && [[ -z $port ]]; then usage_error "--kill needs a port"; fi
  if ((!stop)) && [[ -n $target ]]; then usage_error "--pid requires --kill"; fi
  has ss || die "why needs ss (iproute2)"
  sockets=$(why_sockets "$port") || { err "could not inspect local sockets"; return 1; }
  if [[ -z $sockets ]]; then
    say "No local TCP listener or bound UDP socket found${port:+ on port $port}."
    ((stop == 0)); return
  fi
  section "Local sockets (protocol, state, queues, local address, peer, process)"
  say "$sockets"
  [[ -n $port ]] || return 0
  local -a pids
  mapfile -t pids < <(why_pids <<<"$sockets")
  if ((${#pids[@]} == 0)); then
    note "Process details unavailable with current permissions."
    ((stop == 0)); return
  fi
  if ((stop)) && [[ -z $target && ${#pids[@]} == 1 ]]; then target=${pids[0]}; fi
  for pid in "${pids[@]}"; do
    if [[ $pid == "$target" ]]; then start=$(why_started "$pid") || return 1; fi
    why_process "$pid"
  done
  ((stop)) || return 0
  [[ -n $target ]] || usage_error "multiple processes own this port; select one with --pid PID"
  [[ -n $start && $target != 1 && $target != "$$" ]] ||
    { err "select a listed process other than PID 1 or lemux"; return 1; }
  confirm "Send SIGTERM to PID $target on port $port?" || { note "No signal sent."; return 1; }
  sockets=$(why_sockets "$port") || return 1
  if ! current=$(why_started "$target") || [[ $current != "$start" ]] ||
     ! why_pids <<<"$sockets" | grep -Fx -- "$target" >/dev/null ||
     ! why_owns_socket "$port" "$target"; then
    err "process or port owner changed; no signal sent"
    return 1
  fi
  kill -TERM "$target" || return 1
  oplog signal "SIGTERM pid=$target port=$port"
  ok "sent SIGTERM to PID $target"
}

help_why() {
  cat <<'EOF_HELP'
Usage: lemux why [PORT] [--kill [--pid PID]]

List local TCP listeners and bound UDP sockets. Supply a port to show its
visible owners, commands, executable paths, working directories and parents.
--kill asks before sending SIGTERM to one owner. Select --pid if several
processes share the port. In scripts, lemux -y why PORT --kill confirms it.
EOF_HELP
}
