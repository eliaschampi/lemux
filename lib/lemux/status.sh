# shellcheck shell=bash
# status.sh — one-screen system dashboard with a health score; --watch refreshes it live.

st_cpu() { awk '/^cpu /{printf "%.0f %.0f\n", $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat; }   # busy+idle and idle ticks
st_net() { awk -F'[: ]+' 'NR > 2 && $2 != "lo" {rx += $3; tx += $11} END {printf "%.0f %.0f\n", rx, tx}' /proc/net/dev; }
st_io() { awk '$3 ~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|mmcblk[0-9]+)$/ {r += $6; w += $10} END {printf "%.0f %.0f\n", r * 512, w * 512}' /proc/diskstats; }

# st_penalty VALUE HIGH HIGH_POINTS LOW LOW_POINTS -> points to take off the health score
st_penalty() {
  if (($1 >= $2)); then echo "$3"; elif (($1 >= $4)); then echo "$5"; else echo 0; fi
}

status_once() {
  local c1 i1 c2 i2 rx1 tx1 rx2 tx2 r1 w1 r2 w2
  read -r c1 i1 < <(st_cpu); read -r rx1 tx1 < <(st_net); read -r r1 w1 < <(st_io)
  sleep 1
  read -r c2 i2 < <(st_cpu); read -r rx2 tx2 < <(st_net); read -r r2 w2 < <(st_io)
  local total=$((c2 - c1)) cpu=0 score=100 cores load
  ((total > 0)) && cpu=$(((c2 - c1 - (i2 - i1)) * 100 / total))
  ((cpu < 0)) && cpu=0
  cores=$(nproc)
  load=$(cut -d' ' -f1-3 /proc/loadavg)
  local mt ma st sf mem swp=0
  read -r mt ma st sf < <(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} /^SwapTotal:/{s=$2} /^SwapFree:/{f=$2} END{print t+0, a+0, s+0, f+0}' /proc/meminfo)
  [[ ${mt:-0} -gt 0 ]] || { err "memory counters unavailable"; return 1; }
  mem=$(((mt - ma) * 100 / mt))
  ((st > 0)) && swp=$(((st - sf) * 100 / st))
  local root free temp=0 t hw failed=0
  read -r root free < <(df -h --output=pcent,avail / | awk 'NR==2 { sub(/%$/, "", $1); print $1,$2 }')
  [[ $root =~ ^[0-9]+$ ]] || { err "disk counters unavailable"; return 1; }
  for hw in /sys/class/hwmon/hwmon*/temp1_input; do t=$(($(cat "$hw" 2>/dev/null || echo 0) / 1000)); ((t > temp)) && temp=$t; done
  has systemctl && failed=$(timeout 4 systemctl --failed --plain --no-legend 2>/dev/null | awk 'END {print NR}')

  score=$((score - $(st_penalty "$cpu" 90 15 70 5) - $(st_penalty "$mem" 90 20 80 10) - $(st_penalty "$swp" 50 10 50 10)))
  score=$((score - $(st_penalty "$root" 90 20 80 10) - $(st_penalty "$temp" 85 20 75 10) - $(st_penalty "$failed" 1 10 1 10)))
  local verdict="${C_G}Excellent${C_0}"
  ((score < 90)) && verdict="${C_G}Good${C_0}"
  ((score < 70)) && verdict="${C_Y}Fair${C_0}"
  ((score < 50)) && verdict="${C_R}Poor${C_0}"

  printf '%slemux status%s  ·  %s  ·  up %s\n' "$C_B" "$C_0" "$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname)" "$(uptime -p | sed 's/^up //')"
  printf 'Health  %s%3d%s  %s\n\n' "$C_B" "$score" "$C_0" "$verdict"
  printf '  CPU     %s %3d%%  %s cores · load %s\n' "$(bar "$cpu")" "$cpu" "$cores" "$load"
  printf '  Memory  %s %3d%%  %s of %s\n' "$(bar "$mem")" "$mem" "$(human $(((mt - ma) * 1024)))" "$(human $((mt * 1024)))"
  ((st > 0)) && printf '  Swap    %s %3d%%  %s of %s\n' "$(bar "$swp")" "$swp" "$(human $(((st - sf) * 1024)))" "$(human $((st * 1024)))"
  printf '  Disk /  %s %3d%%  %s free\n' "$(bar "$root")" "$root" "$free"
  printf '  Disk IO read %s/s · write %s/s\n' "$(human $((r2 - r1)))" "$(human $((w2 - w1)))"
  printf '  Network ↓ %s/s · ↑ %s/s\n' "$(human $((rx2 - rx1)))" "$(human $((tx2 - tx1)))"
  ((temp > 0)) && printf '  Temp    %s°C hottest sensor\n' "$temp"
  local bat
  for bat in /sys/class/power_supply/BAT*; do
    [[ -r $bat/capacity ]] && printf '  Battery %s%% · %s\n' "$(<"$bat/capacity")" "$(<"$bat/status")"
  done
  ((failed > 0)) && printf '  %s%d failed unit(s)%s: lemux check\n' "$C_Y" "$failed" "$C_0"
  printf '\n  %sTop processes%s           CPU    MEM\n' "$C_B" "$C_0"
  ps -eo comm=,pcpu=,rss= --sort=-pcpu |
    awk 'NR <= 5 {printf "  %-22s %5.1f%%  %5.0fM\n", $1, $2, $3 / 1024}'
}

cmd_status() {
  local watch=0 interval=2
  while (($#)); do
    case $1 in
      -w | --watch) watch=1 ;;
      -n) interval=${2:-}; shift ;;
      -h | --help) help_status; return 0 ;;
      *) usage_error "status: unknown option '$1'" ;;
    esac
    shift
  done
  if ! valid_count "$interval" || [[ $interval == 0 ]]; then usage_error "status: -n needs a positive integer"; fi
  if ((!watch)); then status_once; return; fi
  [[ -t 1 ]] || usage_error "status --watch needs a terminal"
  trap 'tput cnorm 2>/dev/null; printf "\n"; exit 0' INT TERM
  tput civis 2>/dev/null
  while :; do
    local frame
    frame=$(status_once) || { tput cnorm 2>/dev/null; return 1; }
    printf '\e[H\e[2J%s\n\n  %sCtrl+C to quit · every %ss%s' "$frame" "$C_D" "$interval" "$C_0"
    sleep "$((interval > 1 ? interval - 1 : 0))"
  done
}

help_status() {
  cat <<'EOF'
Usage: lemux status [--watch] [-n SECONDS]

A one-screen view of the system: health score, CPU, memory, swap, disk usage and
I/O, network traffic, temperature, battery, failed units and top processes.

  -w, --watch   refresh continuously (Ctrl+C to quit)
  -n SECONDS    refresh interval for --watch (default 2)
EOF
}
