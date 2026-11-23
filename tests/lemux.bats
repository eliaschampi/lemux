#!/usr/bin/env bats
# Tests run against a throwaway HOME: nothing on the real system is touched.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" NO_COLOR=1 LEMUX_YES=0
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" \
    XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$HOME/Documents"
  LEMUX="$BATS_TEST_DIRNAME/../bin/lemux"
}

# A few KB of throwaway data at the given path.
fill() { mkdir -p "$(dirname "$1")"; head -c 20000 /dev/urandom >"$1"; }

@test "version and help" {
  run "$LEMUX" --version
  [ "$status" -eq 0 ]
  [[ $output =~ ^lemux\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
  run "$LEMUX" --help
  [ "$status" -eq 0 ]
  [[ $output == *"remove <name>"* ]]
}

@test "unknown command and option exit with 2" {
  run "$LEMUX" frobnicate
  [ "$status" -eq 2 ]
  run "$LEMUX" clean --bogus
  [ "$status" -eq 2 ]
}

@test "every command has its own help" {
  for c in why check clean remove app update purge installers analyze status optimize history; do
    run "$LEMUX" "$c" --help
    [ "$status" -eq 0 ]
    [[ $output == Usage:* ]]
  done
}

@test "core: name helpers" {
  source "$BATS_TEST_DIRNAME/../lib/lemux/core.sh"
  [ "$(norm 'Open-IDEA_2')" = "openidea2" ]
  [ "$(slug 'Photon Studio 2')" = "photon-studio-2" ]
  [ "$(ver_num '26.11.15.glibc2.35')" = "26.11.15" ]
}

@test "core: version comparison" {
  source "$BATS_TEST_DIRNAME/../lib/lemux/core.sh"
  ver_gt 1.10.0 1.9.9
  ! ver_gt 1.9.9 1.10.0
  ! ver_gt 26.11.15 26.11.15.glibc2.35
  ver_gt v2.0 1.99
}

@test "clean: dry run reports and keeps files" {
  fill "$HOME/.npm/_cacache/blob"
  fill "$XDG_CACHE_HOME/thumbnails/large/x.png"
  run "$LEMUX" clean
  [ "$status" -eq 0 ]
  [[ $output == *"npm cache"* ]]
  [[ $output == *"Thumbnails"* ]]
  [ -f "$HOME/.npm/_cacache/blob" ]
}

@test "clean: --apply deletes caches but never npx or app data" {
  fill "$HOME/.npm/_cacache/blob"
  fill "$HOME/.npm/_npx/tool/bin"
  fill "$XDG_CONFIG_HOME/someapp/settings"
  run "$LEMUX" clean --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.npm/_cacache" ]
  [ -f "$HOME/.npm/_npx/tool/bin" ]
  [ -f "$XDG_CONFIG_HOME/someapp/settings" ]
}

@test "clean: trash only with --trash" {
  fill "$XDG_DATA_HOME/Trash/files/old.bin"
  run "$LEMUX" clean --apply
  [ -f "$XDG_DATA_HOME/Trash/files/old.bin" ]
  run "$LEMUX" clean --apply --trash
  [ ! -e "$XDG_DATA_HOME/Trash/files/old.bin" ]
  [ -d "$XDG_DATA_HOME/Trash/files" ]
}

@test "remove: refuses names shorter than 4 characters" {
  run "$LEMUX" remove obs
  [ "$status" -eq 2 ]
  run "$LEMUX" remove lemux
  [ "$status" -eq 2 ]
}

@test "remove: dry run lists leftovers, --apply removes only them" {
  fill "$XDG_CONFIG_HOME/ai.example.zorbquux/settings.json"
  fill "$XDG_CACHE_HOME/zorbquux/blob"
  fill "$HOME/.zorbquux/state"
  fill "$HOME/Documents/zorbquux-notes.txt"
  printf '[Default Applications]\ntext/plain=zorbquux.desktop;gedit.desktop;\nx-scheme-handler/zorbquux=zorbquux.desktop;\n' \
    >"$XDG_CONFIG_HOME/mimeapps.list"
  run "$LEMUX" remove zorbquux
  [ "$status" -eq 0 ]
  [[ $output == *"ai.example.zorbquux"* ]]
  [ -d "$XDG_CONFIG_HOME/ai.example.zorbquux" ]

  run "$LEMUX" remove zorbquux --apply
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/ai.example.zorbquux" ]
  [ ! -e "$XDG_CACHE_HOME/zorbquux" ]
  [ ! -e "$HOME/.zorbquux" ]
  [ -f "$HOME/Documents/zorbquux-notes.txt" ]
  run cat "$XDG_CONFIG_HOME/mimeapps.list"
  [[ $output == *"text/plain=gedit.desktop;"* ]]
  [[ $output != *zorbquux* ]]
}

@test "remove: nothing found is not an error" {
  run "$LEMUX" remove qwertyzx
  [ "$status" -eq 0 ]
  [[ $output == *"Nothing found"* ]]
}

@test "app: list is empty and install rejects non-AppImages" {
  run "$LEMUX" app list
  [ "$status" -eq 0 ]
  [[ $output == *"No AppImages"* ]]
  fill "$HOME/fake.AppImage"
  run "$LEMUX" app install "$HOME/fake.AppImage"
  [ "$status" -eq 1 ]
  [[ $output == *"not an AppImage"* ]]
}

@test "app: update with nothing installed" {
  run "$LEMUX" update --apps
  [ "$status" -eq 0 ]
  [[ $output == *"No AppImages"* ]]
}

@test "check runs to the end on any distribution" {
  run "$LEMUX" check
  [[ $status -eq 0 || $status -eq 1 ]]
  [[ $output == *"Disks"* ]]
  [[ $output == *"Healthy."* || $output == *"warning(s)."* ]]
}

@test "purge: only artifacts next to their marker, old ones, never git-tracked" {
  p="$HOME/Documents/web"
  fill "$p/package.json"; fill "$p/node_modules/lib/index.js"
  fill "$HOME/Documents/notes/node_modules/x"                 # no package.json: not an artifact
  fill "$HOME/Documents/new/package.json"; fill "$HOME/Documents/new/node_modules/y"
  touch -d '30 days ago' "$p/node_modules"
  run "$LEMUX" purge "$HOME/Documents"
  [ "$status" -eq 0 ]
  [[ $output == *"~/Documents/web"* ]]
  [[ $output == *"recent, kept"* ]]
  [[ $output != *notes* ]]
  run "$LEMUX" purge "$HOME/Documents" --apply
  [ ! -e "$p/node_modules" ]
  [ -d "$HOME/Documents/notes/node_modules" ]
  [ -d "$HOME/Documents/new/node_modules" ]
  run "$LEMUX" purge "$HOME/Documents" --apply --all
  [ ! -e "$HOME/Documents/new/node_modules" ]
}

@test "purge: keeps folders tracked by git" {
  command -v git >/dev/null || skip "git not installed"
  p="$HOME/Documents/lib"
  fill "$p/package.json"; fill "$p/dist/lib.js"
  git -C "$p" init -q && git -C "$p" add dist package.json
  run "$LEMUX" purge "$HOME/Documents" --apply --all
  [ -f "$p/dist/lib.js" ]
}

@test "protect list keeps paths and an unreadable list stops lemux" {
  fill "$HOME/.npm/_cacache/blob"
  mkdir -p "$XDG_CONFIG_HOME/lemux"
  printf '# keep npm\n~/.npm/_cacache\n' >"$XDG_CONFIG_HOME/lemux/protect"
  run "$LEMUX" clean --apply
  [ -f "$HOME/.npm/_cacache/blob" ]
  if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "$XDG_CONFIG_HOME/lemux/protect"
    run "$LEMUX" clean --apply
    [ "$status" -eq 1 ]
    [[ $output == *"protect list"* ]]
  fi
}

@test "history records deletions; LEMUX_NO_OPLOG disables it" {
  fill "$XDG_CACHE_HOME/thumbnails/a.png"
  LEMUX_NO_OPLOG=1 run "$LEMUX" clean --apply
  run "$LEMUX" history
  [[ $output == *"No operations"* ]]
  fill "$XDG_CACHE_HOME/thumbnails/b.png"
  run "$LEMUX" clean --apply
  run "$LEMUX" history
  [[ $output == *"thumbnails"* ]]
  run "$LEMUX" history --json
  [[ $output == '[{"time":'* ]]
}

@test "installers: unknown files are listed but kept unless --all" {
  mkdir -p "$HOME/Downloads"; fill "$HOME/Downloads/distro.iso"
  run "$LEMUX" installers --apply
  [ -f "$HOME/Downloads/distro.iso" ]
  run "$LEMUX" installers --apply --all
  [ ! -e "$HOME/Downloads/distro.iso" ]
}

@test "analyze, status and optimize run read-only" {
  fill "$HOME/Documents/big/file.bin"
  run "$LEMUX" analyze "$HOME"
  [ "$status" -eq 0 ]
  [[ $output == *"~/Documents"* ]]
  run "$LEMUX" status
  [ "$status" -eq 0 ]
  [[ $output == *"Health"* ]]
  run "$LEMUX" optimize
  [ "$status" -eq 0 ]
}

@test "clean keeps a cache containing an explicitly protected file" {
  fill "$XDG_CACHE_HOME/thumbnails/keep.png"
  mkdir -p "$XDG_CONFIG_HOME/lemux"
  printf '%s\n' '~/.cache/thumbnails/keep.png' >"$XDG_CONFIG_HOME/lemux/protect"
  run "$LEMUX" clean --apply
  [ "$status" -eq 0 ]
  [ -f "$XDG_CACHE_HOME/thumbnails/keep.png" ]
}

@test "installer alias also reads the protect list" {
  fill "$HOME/Downloads/keep.iso"
  mkdir -p "$XDG_CONFIG_HOME/lemux"
  printf '%s\n' '~/Downloads/keep.iso' >"$XDG_CONFIG_HOME/lemux/protect"
  run "$LEMUX" installer --apply --all
  [ "$status" -eq 0 ]
  [ -f "$HOME/Downloads/keep.iso" ]
}

@test "history rejects an invalid limit and preserves JSON paths" {
  fill "$XDG_CACHE_HOME/thumbnails/blob"
  run "$LEMUX" history -n abc
  [ "$status" -eq 2 ]
  export XDG_CACHE_HOME="$HOME/cache|with:delimiters"
  fill "$XDG_CACHE_HOME/thumbnails/blob"
  run "$LEMUX" clean --apply
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CACHE_HOME/thumbnails" ]
  "$LEMUX" history --json | jq -e --arg path "$XDG_CACHE_HOME/thumbnails" '.[0].path == $path'
}

@test "app remove only accepts an installed application ID" {
  run "$LEMUX" app remove .
  [ "$status" -eq 2 ]
}

@test "remove keeps files for a different app and keeps leftovers if Trash fails" {
  fill "$XDG_CONFIG_HOME/another-zorbquux/cache"
  fill "$XDG_CONFIG_HOME/zorbquux/settings"
  mkdir -p "$HOME/stubs"
  printf '#!/bin/sh\nexit 1\n' >"$HOME/stubs/gio"
  chmod +x "$HOME/stubs/gio"
  export PATH="$HOME/stubs:$PATH"
  run "$LEMUX" remove zorbquux --apply
  [ "$status" -eq 1 ]
  [ -f "$XDG_CONFIG_HOME/another-zorbquux/cache" ]
  [ -f "$XDG_CONFIG_HOME/zorbquux/settings" ]
}

@test "purge preserves a nested repository and deduplicates project roots" {
  p="$HOME/Documents/site"
  fill "$p/package.json"
  fill "$p/node_modules/embedded/.git/config"
  fill "$p/dist/index.js"
  run "$LEMUX" purge "$HOME/Documents" "$p" --all --apply
  [ "$status" -eq 0 ]
  [[ $output == *"Purged 1 artifact(s)"* ]]
  [ -f "$p/node_modules/embedded/.git/config" ]
  [ ! -e "$p/dist" ]
}

fixture_image() {
  local version=$1 image=$2 dir=$BATS_TEST_TMPDIR/app-root squash=$BATS_TEST_TMPDIR/payload.sqfs
  mkdir -p "$dir"
  printf '[Desktop Entry]\nType=Application\nName=Example App\nExec=example\nX-AppImage-Version=%s\n' "$version" >"$dir/example.desktop"
  mkdir -p "$dir/usr/share/icons/hicolor/scalable/apps"
  printf '<svg xmlns="http://www.w3.org/2000/svg"><title>%s</title></svg>' "$version" >"$dir/usr/share/icons/hicolor/scalable/apps/example.svg"
  echo 'Icon=example' >>"$dir/example.desktop"
  mksquashfs "$dir" "$squash" -noappend -processors 1 -no-progress >/dev/null
  cp /bin/true "$image"
  printf 'AI\002' | dd of="$image" bs=1 seek=8 conv=notrunc status=none
  cat "$squash" >>"$image"
  chmod 644 "$image"
}

@test "app installs, updates and rolls back from inert filesystem fixtures" {
  command -v mksquashfs >/dev/null || skip "squashfs-tools missing"
  fixture_image 1.0.0 "$HOME/Example-1.0.0.AppImage"
  fixture_image 2.0.0 "$HOME/Example-2.0.0.AppImage"
  run "$LEMUX" app install "$HOME/Example-1.0.0.AppImage" --name example
  [ "$status" -eq 0 ]
  entry="$XDG_DATA_HOME/applications/lemux-example.desktop"
  icon=$(sed -n 's/^Icon=//p' "$entry")
  grep -F '1.0.0' "$icon"
  [ ! -x "$HOME/Example-1.0.0.AppImage" ]
  run "$LEMUX" app update example "$HOME/Example-2.0.0.AppImage"
  [ "$status" -eq 0 ]
  grep -F '2.0.0' "$(sed -n 's/^Icon=//p' "$entry")"
  run "$LEMUX" app list
  [[ $output == *"2.0.0"* ]]
  run "$LEMUX" app rollback example
  [ "$status" -eq 0 ]
  run "$LEMUX" app list
  [[ $output == *"1.0.0"* ]]
  grep -F '1.0.0' "$(sed -n 's/^Icon=//p' "$entry")"
  run "$LEMUX" app remove example
  [ "$status" -eq 0 ]
  [ -f "$entry" ]
  run "$LEMUX" remove --appimage example --apply
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_DATA_HOME/lemux/apps/example" ]
  [ ! -L "$HOME/.local/bin/example" ]
}

@test "check labels unavailable services and reports radio sections" {
  run "$LEMUX" check
  [[ $status -eq 0 || $status -eq 1 ]]
  [[ $output == *"Wi-Fi"* ]]
  [[ $output == *"Bluetooth"* ]]
  [[ $output != *"tsc=nowatchdog"* ]]
}

@test "audio only offers to restore masked sockets when the sound server is absent" {
  source "$BATS_TEST_DIRNAME/../lib/lemux/core.sh"
  source "$BATS_TEST_DIRNAME/../lib/lemux/check.sh"
  pactl() { return 1; }
  has() { [[ $1 != pulseaudio ]]; }
  timeout() { shift; "$@"; }
  systemctl() {
    printf '%s\n' "$*" >>"$HOME/systemctl.calls"
    if [[ $* == "--user is-enabled pipewire.socket" ]]; then
      printf 'masked\n'
      return 1
    fi
    return 0
  }
  chk_audio
  [[ ${FIXES[0]} == *'|fix_pipewire_units' ]]
  fix_pipewire_units
  grep -Fx -- '--user start pipewire.socket pipewire-pulse.socket' "$HOME/systemctl.calls"
}

@test "GitHub AppImage installation stops when the asset has no digest" {
  mkdir -p "$HOME/stubs"
  cat >"$HOME/stubs/curl" <<'MOCK'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ $arg == https://api.github.com/* ]]; then
    printf '%s\n' '{"tag_name":"v1.0.0","assets":[{"name":"example.AppImage","browser_download_url":"https://github.com/example/app/releases/download/v1.0.0/example.AppImage"}]}'
    exit 0
  fi
done
printf 'unexpected asset download\n' >&2
exit 1
MOCK
  chmod +x "$HOME/stubs/curl"
  export PATH="$HOME/stubs:$PATH"
  run "$LEMUX" app install example/app
  [ "$status" -eq 1 ]
  [[ $output == *"SHA-256 digest"* ]]
  [[ $output != *"unexpected asset download"* ]]
  [ ! -e "$XDG_DATA_HOME/lemux/apps/example" ]
}

@test "explicit clean categories isolate history, browser, logs and deep caches" {
  fill "$HOME/.bash_history"
  fill "$XDG_CACHE_HOME/thumbnails/p"
  fill "$XDG_CACHE_HOME/mesa_shader_cache/p"
  fill "$HOME/.npm/_logs/log"
  run "$LEMUX" clean --bash-history
  [ "$status" -eq 0 ]
  [[ $output == *'Saved Bash history'* && $output != *'Thumbnails'* ]]
  [ -f "$HOME/.bash_history" ]
  run "$LEMUX" clean --bash-history --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.bash_history" ]
  [ -f "$XDG_CACHE_HOME/thumbnails/p" ]
  run "$LEMUX" clean --deep
  [[ $output == *'Mesa shader cache'* && $output != *'Thumbnails'* ]]
  mkdir -p "$XDG_CONFIG_HOME/lemux"
  printf '/var/log/journal\n' >"$XDG_CONFIG_HOME/lemux/protect"
  run "$LEMUX" clean --logs --apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.npm/_logs" ]
  [ -f "$XDG_CACHE_HOME/mesa_shader_cache/p" ]
  export XDG_CACHE_HOME=$XDG_CONFIG_HOME
  fill "$XDG_CONFIG_HOME/chromium/Default/Bookmarks"
  run "$LEMUX" clean --browser --apply
  [ "$status" -ne 0 ]
  [ -f "$XDG_CONFIG_HOME/chromium/Default/Bookmarks" ]
}

@test "why explains a real TCP and UDP port and signals only the chosen owner" {
  command -v python3 >/dev/null && command -v ss >/dev/null || skip "needs python3 and ss"
  python3 - "$LEMUX" <<'PY'
import signal, socket, subprocess, sys
cli = sys.argv[1]
child = """import socket,sys,time
s=socket.socket(type=getattr(socket,sys.argv[1]))
s.bind(('127.0.0.1',int(sys.argv[2])))
if s.type == socket.SOCK_STREAM: s.listen()
print(s.getsockname()[1],flush=True)
time.sleep(30)"""
a = subprocess.Popen([sys.executable, '-c', child, 'SOCK_STREAM', '0'], stdout=subprocess.PIPE, text=True)
try:
    port = a.stdout.readline().strip()
    b = subprocess.Popen([sys.executable, '-c', child, 'SOCK_DGRAM', port], stdout=subprocess.PIPE, text=True)
    try:
        assert b.stdout.readline().strip() == port
        diag = subprocess.check_output([cli, 'why', port], text=True)
        assert all(x in diag for x in ('tcp', 'udp', 'cwd:', 'parent:', f'PID {a.pid}', f'PID {b.pid}'))
        assert subprocess.run([cli, '-y', 'why', port, '--kill']).returncode == 2
        assert subprocess.run([cli, 'why', port, '--kill', '--pid', str(a.pid)], stdin=subprocess.DEVNULL).returncode != 0
        subprocess.run([cli, '-y', 'why', port, '--kill', '--pid', str(a.pid)], check=True)
        assert a.wait(timeout=3) == -signal.SIGTERM and b.poll() is None
    finally:
        b.terminate()
        b.wait()
finally:
    a.terminate()
    a.wait()
PY
  run "$LEMUX" why 65536 --kill
  [ "$status" -eq 2 ]
}

@test "terminal checklists accept arrows and Space, apply a subset, and cancel cleanly" {
  command -v python3 >/dev/null || skip "needs python3"
  fill "$HOME/.npm/_cacache/blob"
  fill "$HOME/.bash_history"
  python3 - "$LEMUX" <<'PY'
import os, pty, select, subprocess, sys, time
from pathlib import Path
cli = Path(sys.argv[1]).resolve()
def menu(command, marker, keys, expected):
    master, slave = pty.openpty()
    proc = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    buf = b''
    try:
        limit = time.monotonic() + 6
        while marker not in buf and time.monotonic() < limit:
            if select.select([master], [], [], .2)[0]:
                buf += os.read(master, 65536)
        assert marker in buf, buf
        os.write(master, keys)
        assert proc.wait(timeout=5) == expected, buf
    finally:
        proc.kill()
        proc.wait()
        os.close(master)
home = Path.home()
menu([cli, 'clean', '--apply'], b'Remove orphaned packages', b'q', 130)
assert (home/'.npm/_cacache/blob').exists()
# Turn off basic/browser and turn on saved history.
menu([cli, 'clean', '--apply'], b'Remove orphaned packages', b' \x1b[B jjj \n', 0)
assert (home/'.npm/_cacache/blob').exists() and not (home/'.bash_history').exists()
# Drive the normal repair dispatcher with two deterministic findings.
fixture = """
source "$1/lib/lemux/core.sh"
source "$1/lib/lemux/check.sh"
for fn in system clock audio wifi bluetooth services packages memory disks thermal journal; do
  eval "chk_${fn}() { :; }"
done
first() { touch "$HOME/first"; }
second() { touch "$HOME/second"; }
chk_system() { add_fix First first; add_fix Second second; }
cmd_check --fix
"""
menu(['bash', '-c', fixture, 'bash', cli.parents[1]], b'[ ] Second', b'j \n', 0)
assert (home/'second').exists() and not (home/'first').exists()
PY
}
