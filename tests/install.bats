#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" \
    XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
  PREFIX="$HOME/prefix with spaces"
  SRC="$BATS_TEST_DIRNAME/.."
  mkdir -p "$HOME/bin" "$HOME/assets"
  cat >"$HOME/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while (($#)); do
  case $1 in
    --output) destination=$2; shift ;;
    https://github.com/eliaschampi/lemux/releases/download/*) asset=${1##*/} ;;
  esac
  shift
done
case ${DOWNLOAD_FAILURE:-} in
  corrupt) printf 'bad archive\n' >"$destination" ;;
  interrupted) printf 'partial transfer\n' >"$destination"; exit 28 ;;
  *) cp -- "$HOME/assets/$asset" "$destination" ;;
esac
MOCK
  chmod +x "$HOME/bin/curl"
  export PATH="$HOME/bin:$PATH"
}

bundle() {
  local version=$1 root=$HOME/lemux-$1 archive=$HOME/assets/lemux-$1.tar.gz
  mkdir -p "$root"
  cp -r -- "$SRC"/{bin,lib,man,completions} "$root/"
  sed -i -E "s/^LEMUX_VERSION=.*/LEMUX_VERSION=\"$version\"/" "$root/lib/lemux/core.sh"
  tar -czf "$archive" -C "$HOME" "lemux-$version"
  make -s -C "$SRC" installer VERSION="$version" ARCHIVE="$archive" INSTALLER="$HOME/install-$version.sh"
}

@test "release installer activates the CLI, manual and completions and can be retried" {
  bundle 1.0.0
  run bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX"
  [ "$status" -eq 0 ]
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.0.0" ]
  cmp "$PREFIX/share/man/man1/lemux.1" "$SRC/man/lemux.1"
  cmp "$PREFIX/share/bash-completion/completions/lemux" "$SRC/completions/lemux.bash"
  cmp "$PREFIX/share/zsh/site-functions/_lemux" "$SRC/completions/_lemux"
  cmp "$PREFIX/share/fish/vendor_completions.d/lemux.fish" "$SRC/completions/lemux.fish"
  active=$(readlink "$PREFIX/lib/lemux-releases/current")
  run bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX"
  [ "$status" -eq 0 ]
  [ "$(readlink "$PREFIX/lib/lemux-releases/current")" = "$active" ]
}

@test "failed downloads or digests keep a working installation active" {
  bundle 1.0.0
  bundle 1.1.0
  bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX"
  active=$(readlink "$PREFIX/lib/lemux-releases/current")
  DOWNLOAD_FAILURE=interrupted run bash "$HOME/install-1.1.0.sh" --prefix "$PREFIX"
  [ "$status" -ne 0 ]
  [[ $output == *"Download failed"* ]]
  DOWNLOAD_FAILURE=corrupt run bash "$HOME/install-1.1.0.sh" --prefix "$PREFIX"
  [ "$status" -ne 0 ]
  [[ $output == *"SHA-256 mismatch"* ]]
  [ "$(readlink "$PREFIX/lib/lemux-releases/current")" = "$active" ]
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.0.0" ]
  run bash "$HOME/install-1.1.0.sh" --prefix "$PREFIX"
  [ "$status" -eq 0 ]
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.1.0" ]
  [ -x "$PREFIX/lib/lemux-releases/$active/bin/lemux" ]
}

@test "migration requires consent and keeps a backup of the source installation" {
  bundle 1.0.0
  make -s -C "$SRC" install PREFIX="$PREFIX"
  original=$("$PREFIX/bin/lemux" --version)
  run bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX" </dev/null
  [ "$status" -ne 0 ]
  [[ $output == *"--replace"* ]]
  [ ! -L "$PREFIX/bin/lemux" ]
  [ "$("$PREFIX/bin/lemux" --version)" = "$original" ]
  run bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX" --replace
  [ "$status" -eq 0 ]
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.0.0" ]
  backups=("$PREFIX"/lib/lemux-releases/backup.*/bin/lemux)
  [ "${#backups[@]}" -eq 1 ]
  cmp "${backups[0]}" "$SRC/bin/lemux"
  [ "$("${backups[0]}" --version)" = "$original" ]
  [ -f "$PREFIX/lib/lemux/core.sh" ]
}

@test "an unrelated executable stays in place even with --replace" {
  bundle 1.0.0
  mkdir -p "$PREFIX/bin"
  printf 'different program\n' >"$PREFIX/bin/lemux"
  run bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX" --replace
  [ "$status" -ne 0 ]
  [[ $output == *"Existing file is outside a recognized LEmux installation"* ]]
  [ "$(cat "$PREFIX/bin/lemux")" = "different program" ]
}

@test "a verified archive with the wrong CLI version leaves the active release usable" {
  bundle 1.0.0
  bundle 1.1.0
  sed -i 's/^LEMUX_VERSION=.*/LEMUX_VERSION="9.9.9"/' "$HOME/lemux-1.1.0/lib/lemux/core.sh"
  tar -czf "$HOME/assets/lemux-1.1.0.tar.gz" -C "$HOME" lemux-1.1.0
  make -s -C "$SRC" installer VERSION=1.1.0 ARCHIVE="$HOME/assets/lemux-1.1.0.tar.gz" INSTALLER="$HOME/install-1.1.0.sh"
  bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX"
  run bash "$HOME/install-1.1.0.sh" --prefix "$PREFIX"
  [ "$status" -ne 0 ]
  [[ $output == *"staged CLI failed its version check"* ]]
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.0.0" ]
}

@test "concurrent installers share one complete version at the same prefix" {
  bundle 1.0.0
  bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX" >"$HOME/first.log" 2>&1 &
  first=$!
  bash "$HOME/install-1.0.0.sh" --prefix "$PREFIX" >"$HOME/second.log" 2>&1 &
  second=$!
  wait "$first" || { cat "$HOME/first.log"; return 1; }
  wait "$second" || { cat "$HOME/second.log"; return 1; }
  [ "$("$PREFIX/bin/lemux" --version)" = "lemux 1.0.0" ]
  versions=("$PREFIX"/lib/lemux-releases/versions/v1.0.0-*)
  [ "${#versions[@]}" -eq 1 ]
}
