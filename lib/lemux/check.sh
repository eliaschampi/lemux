# shellcheck shell=bash
# check.sh — read-only health report, with guided fixes for the problems it can repair.

FIXES=() # "description|function" pairs offered by --fix

add_fix() { FIXES+=("$1|$2"); }

chk_system() {
  section "System"
  local pretty boot
  # shellcheck source=/dev/null
  pretty=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}")
  note "${pretty:-unknown distribution} · kernel $(uname -r) · $(uptime -p 2>/dev/null)"
  note "package manager: $PKG"
  boot=$(timeout 5 systemd-analyze 2>/dev/null | sed -n 's/^Startup finished in .* = //p' | head -n1)
  [[ -n $boot ]] && note "last boot took $boot"
}

chk_clock() {
  section "Clock"
  local f=/sys/devices/system/clocksource/clocksource0/current_clocksource cs
  [[ -r $f ]] || { note "clocksource not exposed"; return; }
  cs=$(<"$f")
  ok "clocksource $cs"
  if [[ $cs != tsc ]] && grep -qw constant_tsc /proc/cpuinfo && grep -qw nonstop_tsc /proc/cpuinfo; then
    note "invariant TSC is advertised; inspect kernel logs for the reason it was not selected"
  fi
}

chk_audio() {
  section "Audio"
  local info server unit state
  local -a masked=()
  info=$(LC_ALL=C timeout 5 pactl info 2>/dev/null) || info=""
  server=$(sed -n 's/^Server Name: //p' <<<"$info")
  if [[ -n $server ]]; then
    ok "sound server: $server"
    if ! grep -qE '^Default Sink: .+' <<<"$info"; then warn "sound server has no default output"; fi
    if ! grep -qE '^Default Source: .+' <<<"$info"; then note "sound server has no default input"; fi
    return
  fi
  if ! has pactl; then note "install pactl to inspect PipeWire or PulseAudio"; fi
  if has systemctl; then
    for unit in pipewire.socket pipewire-pulse.socket; do
      state=$(timeout 4 systemctl --user is-enabled "$unit" 2>/dev/null || true)
      [[ $state == masked || $state == masked-runtime ]] && masked+=("$unit")
    done
  fi
  if (("${#masked[@]}")); then
    warn "audio sockets are masked: ${masked[*]}"
    if ! has pulseaudio; then add_fix "unmask and start PipeWire audio sockets" fix_pipewire_units; fi
  elif has pactl && [[ -d /dev/snd ]]; then
    warn "no sound server answers in this session"
  else
    note "audio server unavailable in this session"
  fi
}
fix_pipewire_units() {
  systemctl --user unmask pipewire.socket pipewire-pulse.socket &&
    systemctl --user unmask --runtime pipewire.socket pipewire-pulse.socket &&
    systemctl --user start pipewire.socket pipewire-pulse.socket
}

chk_radio_blocks() {
  local type=$1 radio name hard soft
  for radio in /sys/class/rfkill/rfkill*; do
    [[ -r $radio/type && $(<"$radio/type") == "$type" ]] || continue
    name=$(cat "$radio/name" 2>/dev/null) || name=$type
    hard=$(cat "$radio/hard" 2>/dev/null) || continue
    soft=$(cat "$radio/soft" 2>/dev/null) || continue
    if [[ $hard == 1 ]]; then note "$name: hardware-blocked"
    elif [[ $soft == 1 ]]; then note "$name: software-blocked"
    fi
  done
}

chk_wifi() {
  section "Wi-Fi"
  local iface state any=0
  for iface in /sys/class/net/*; do
    [[ -d $iface/wireless || -e $iface/phy80211 ]] || continue
    any=1
    state=$(cat "$iface/operstate" 2>/dev/null) || state=unknown
    if [[ $state == up ]]; then ok "${iface##*/}: link up"
    else note "${iface##*/}: link $state"; fi
  done
  chk_radio_blocks wlan
  if ((!any)); then note "no Wi-Fi interface found"; return; fi
  if service_failed NetworkManager.service; then
    warn "NetworkManager failed"
    add_fix "restart the failed NetworkManager service (may interrupt networking)" fix_network_manager
  elif has nmcli && state=$(LC_ALL=C timeout 4 nmcli -t radio wifi 2>/dev/null); then
    note "NetworkManager Wi-Fi radio: $state"
  fi
}

chk_bluetooth() {
  section "Bluetooth"
  local adapter result any=0
  for adapter in /sys/class/bluetooth/hci*; do
    [[ ${adapter##*/} =~ ^hci[0-9]+$ ]] && any=1
  done
  chk_radio_blocks bluetooth
  if ((!any)); then note "no Bluetooth controller found"; return; fi
  if service_failed bluetooth.service; then
    warn "Bluetooth service failed"
    add_fix "restart the failed Bluetooth service" fix_bluetooth
  elif has bluetoothctl; then
    result=$(LC_ALL=C timeout 4 bluetoothctl show 2>/dev/null | awk '/^[[:space:]]*Powered:/ {print $2; exit}')
    case $result in
      yes) ok "controller powered on" ;;
      no) note "controller powered off" ;;
      *) note "controller detected; BlueZ did not report its power state" ;;
    esac
  else
    note "controller detected; bluetoothctl unavailable"
  fi
}

service_failed() {
  has systemctl && [[ $(timeout 4 systemctl is-failed "$1" 2>/dev/null) == failed ]]
}
fix_network_manager() { service_failed NetworkManager.service && as_root systemctl restart NetworkManager.service; }
fix_bluetooth() { service_failed bluetooth.service && as_root systemctl restart bluetooth.service; }

chk_services() {
  section "Services"
  has systemctl || { note "no systemd, skipped"; return; }
  local sys usr
  if sys=$(timeout 4 systemctl --failed --plain --no-legend 2>/dev/null); then
    if [[ -n $sys ]]; then warn "failed system units: $(awk '{print $1}' <<<"$sys" | paste -sd' ')"
    else ok "no failed system units"; fi
  else
    note "system service manager unavailable"
  fi
  if usr=$(timeout 4 systemctl --user --failed --plain --no-legend 2>/dev/null); then
    if [[ -n $usr ]]; then warn "failed user units: $(awk '{print $1}' <<<"$usr" | paste -sd' ')"
    else ok "no failed user units"; fi
  else
    note "user service manager unavailable"
  fi
}

chk_packages() {
  section "Packages"
  [[ $PKG == none ]] && { note "no supported package manager"; return; }
  local broken orphaned rc=0
  broken=$(pkg_broken 2>&1) || rc=$?
  if ((rc == 2)) && [[ $PKG == zypper ]]; then
    note "package consistency check unavailable on this backend"
  elif ((rc != 0)) || [[ $PKG == apt && -n $broken ]]; then
    warn "package database check reported a problem"
    if [[ -n $broken ]]; then head -n 6 <<<"$broken" | sed 's/^/          /'; fi
    if [[ $PKG == apt && $rc == 0 ]]; then add_fix "finish interrupted apt installs" pkg_fix_broken; fi
  else
    ok "package database consistent"
  fi
  if orphaned=$(pkg_orphans 2>/dev/null); then
    if [[ -n $orphaned ]]; then note "$(wc -l <<<"$orphaned") orphaned packages"
    else ok "no orphaned packages"; fi
  else
    note "orphaned packages could not be checked"
  fi
}

chk_memory() {
  section "Memory"
  local total avail swap_total swap_free pct pressure
  read -r total avail swap_total swap_free < <(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
    /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2} END{print t+0, a+0, st+0, sf+0}' /proc/meminfo)
  [[ ${total:-0} -gt 0 ]] || { note "memory counters unavailable"; return; }
  pct=$((avail * 100 / total))
  if ((pct >= 15)); then ok "RAM available $(human $((avail * 1024))) of $(human $((total * 1024))) ($pct%)"
  else warn "RAM available only $pct%"; fi
  if ((swap_total)); then note "swap used $(human $(((swap_total - swap_free) * 1024))) of $(human $((swap_total * 1024)))"
  else note "no swap"; fi
  if [[ -r /proc/pressure/memory ]]; then
    pressure=$(awk '/^some / { split($2,a,"="); print a[2] }' /proc/pressure/memory)
    if [[ -n $pressure ]]; then note "memory pressure: $pressure% stalled over the last 10 seconds"; fi
  fi
  [[ $(cat /sys/module/zswap/parameters/enabled 2>/dev/null) == Y ]] && note "zswap on"
  grep -q '^/dev/zram' /proc/swaps 2>/dev/null && note "zram swap on"
}

chk_disks() {
  section "Disks"
  local dev pct mnt disk
  while read -r dev pct mnt; do
    pct=${pct%\%}
    [[ $pct =~ ^[0-9]+$ ]] || continue
    if ((pct >= 85)); then warn "$mnt $pct% used ($dev)"; else ok "$mnt $pct% used"; fi
  done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x vfat -x fuse.portal 2>/dev/null |
    awk 'NR > 1 && !seen[$1]++ {print $1, $5, $6}')
  if has smartctl && root_ready; then
    for disk in $(lsblk -dno NAME,TYPE | awk '$2 == "disk" && $1 !~ /^(zram|loop)/ {print "/dev/" $1}'); do
      local report
      report=$(as_root timeout 8 smartctl -H "$disk" 2>/dev/null)
      if grep -Eq 'PASSED|: OK' <<<"$report"; then ok "SMART $disk healthy"
      elif grep -Eq 'FAILED|BAD' <<<"$report"; then warn "SMART $disk reports failure"
      else note "SMART $disk unavailable"; fi
    done
  else
    note "SMART skipped (needs smartctl and cached sudo: run 'sudo -v' first)"
  fi
}

chk_thermal() {
  section "Thermal"
  local hw name milli celsius crit any=0
  for hw in /sys/class/hwmon/hwmon*; do
    milli=$(cat "$hw/temp1_input" 2>/dev/null) || continue
    name=$(cat "$hw/name" 2>/dev/null)
    celsius=$((milli / 1000)) any=1
    crit=$(($(cat "$hw/temp1_crit" 2>/dev/null || echo 100000) / 1000))
    ((crit > 0 && crit <= 150)) || crit=100
    if ((celsius >= crit - 10)); then warn "$name $celsius°C (critical at $crit°C)"; else ok "$name $celsius°C"; fi
  done
  ((any)) || note "no temperature sensors exposed"
}

chk_journal() {
  section "Logs"
  has journalctl || { note "no journald, skipped"; return; }
  local size bytes
  size=$(LC_ALL=C timeout 5 journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -n1)
  [[ -n $size ]] || { note "journal size unknown"; return; }
  bytes=$(numfmt --from=iec "$size" 2>/dev/null || echo 0)
  if ((bytes > 1073741824)); then
    warn "journal uses $size"
    add_fix "shrink the journal to 500M" fix_journal
  else
    ok "journal uses $size"
  fi
}
fix_journal() {
  if is_protected /var/log/journal || is_protected /run/log/journal; then
    err "journal kept by protect list"
    return 1
  fi
  as_root journalctl --vacuum-size=500M
}

cmd_check() {
  local fix=0 arg entry desc fn
  for arg in "$@"; do
    case $arg in
      --fix) fix=1 ;;
      -h | --help) help_check; return 0 ;;
      *) usage_error "check: unknown option '$arg'" ;;
    esac
  done
  if ((fix)); then load_protect; fi
  WARNINGS=0 FIXES=()
  chk_system
  chk_clock
  chk_audio
  chk_wifi
  chk_bluetooth
  chk_services
  chk_packages
  chk_memory
  chk_disks
  chk_thermal
  chk_journal
  printf '\n'
  if ((WARNINGS == 0)); then say "${C_G}Healthy.${C_0}"; else say "${C_Y}$WARNINGS warning(s).${C_0}"; fi
  if ((${#FIXES[@]})); then
    if ((fix)); then
      local -a choices=() picked=()
      local i
      for entry in "${FIXES[@]}"; do
        choices+=("${entry%%|*}")
        if [[ $LEMUX_YES == 1 ]]; then picked+=(1); else picked+=(0); fi
      done
      if [[ $LEMUX_YES != 1 && -t 0 && -t 1 ]]; then
        checkboxes choices picked "Select repairs" || return $?
      fi
      for i in "${!FIXES[@]}"; do
        ((picked[i])) || continue
        entry=${FIXES[i]}
        desc=${entry%%|*} fn=${entry#*|}
        if "$fn"; then
          ok "applied: $desc"
          oplog repair "$desc"
        else
          err "fix failed: $desc"
        fi
      done
    else
      say "${#FIXES[@]} fix(es) available: lemux check --fix"
    fi
  fi
  ((WARNINGS == 0))
}

help_check() {
  cat <<'EOF'
Usage: lemux check [--fix]

Read-only health report: clock source, audio, Wi-Fi, Bluetooth, failed services, package
database, memory pressure, disks, temperatures and journal size.

  --fix   select repairs with Space and accept with Enter. -y applies all offered repairs

Exit status: 0 healthy, 1 warnings found.
EOF
}
