#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

readonly release_version='@RELEASE_VERSION@'
readonly release_sha256='@RELEASE_SHA256@'

fail() { printf 'lemux installer: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'HELP'
Usage: bash lemux-install.sh [--prefix DIRECTORY] [--replace]

Install or update the release bundled with this installer.
The default prefix is ~/.local. --replace authorizes migration
from a source installation at the same prefix.
HELP
}

confirm_backup() {
  local answer
  [[ -t 0 && -t 2 ]] || return 1
  read -r -p "Back up and replace the existing LEmux entry points? [y/N] " answer
  [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

publish_link() {
  local target=$1 dest=$2 scratch
  # Stage beside the destination so rename stays on the same filesystem.
  scratch=$(mktemp -d -- "${dest%/*}/.lemux-link.XXXXXXXX") || return 1
  if ! ln -s -- "$target" "$scratch/link" || ! mv -fT -- "$scratch/link" "$dest"; then
    rm -rf -- "$scratch"
    return 1
  fi
  rmdir -- "$scratch"
}

check_release() {
  local root=$1 member reported
  for member in "${members[@]}"; do [[ -f $root/$member ]] || return 1; done
  [[ -f $root/.release-sha256 && $(<"$root/.release-sha256") == "$release_sha256" ]] || return 1
  reported=$(env -u LEMUX_LIBDIR "$root/bin/lemux" --version) || return 1
  [[ $reported == "lemux $release_version" && -x $root/bin/lemux ]]
}

prefix=$HOME/.local
replace=0
while (($#)); do
  case $1 in
    --prefix)
      if (($# < 2)) || [[ -z $2 ]]; then fail "--prefix needs a directory"; fi
      prefix=$2
      shift
      ;;
    --replace) replace=1 ;;
    -h | --help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done

(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) ||
  fail "Bash 4.4 or newer is required"
[[ $(uname -s) == Linux ]] || fail "This installer requires Linux"
[[ $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $release_sha256 =~ ^[0-9a-f]{64}$ ]] ||
  fail "Use the installer asset from a published LEmux release"

for tool in curl tar gzip sha256sum realpath readlink mktemp flock grep find du awk sed ps sort stat numfmt; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing dependency: $tool"
done

[[ $prefix == /* ]] || fail "--prefix must be an absolute path"
prefix=$(realpath -m -- "$prefix")
[[ $prefix != / ]] || fail "Choose an installation prefix such as ~/.local"
store=$prefix/lib/lemux-releases
current=$store/current
slot=versions/v$release_version-$release_sha256
version_dir=$store/$slot

# Keep these paths in step with the source installation. All public links
# resolve through the same pointer, so a normal upgrade switches them together.
members=(man/lemux.1 completions/lemux.bash completions/_lemux completions/lemux.fish bin/lemux)
paths=(share/man/man1/lemux.1 share/bash-completion/completions/lemux
  share/zsh/site-functions/_lemux share/fish/vendor_completions.d/lemux.fish bin/lemux)
legacy=()

[[ $(realpath -m -- "$store/versions") == "$store/versions" ]] ||
  fail "Release storage must use directories inside the installation prefix"
mkdir -p -- "$store/versions"
exec {lock_fd}<"$store"
flock -x "$lock_fd"

if [[ -L $current ]]; then
  pointer=$(readlink -- "$current")
  [[ $pointer =~ ^versions/v[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]{64}$ ]] ||
    fail "Unrecognized active version link: $current"
elif [[ -e $current ]]; then
  fail "The active version path is occupied: $current"
fi

for i in "${!paths[@]}"; do
  dest=$prefix/${paths[i]}
  parent=${dest%/*}
  [[ $(realpath -m -- "$parent") == "$parent" ]] ||
    fail "Entry point must stay inside the installation prefix: $dest"
  if [[ -L $dest && $(readlink -- "$dest") == "$current/${members[i]}" ]]; then continue; fi
  if [[ -e $dest || -L $dest ]]; then
    if [[ -f $dest && ! -L $dest ]]; then legacy+=("${paths[i]}")
    else fail "Entry point is occupied: $dest"; fi
  fi
done

if (("${#legacy[@]}")); then
  if [[ -L $prefix/bin/lemux || -L $prefix/lib/lemux || -L $prefix/lib/lemux/core.sh ]] ||
     ! grep -q '^LEMUX_LIBDIR=' "$prefix/bin/lemux" 2>/dev/null ||
     ! grep -Eq '^LEMUX_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$prefix/lib/lemux/core.sh" 2>/dev/null; then
    fail "Existing file is outside a recognized LEmux installation under $prefix"
  fi
  if ((!replace)) && ! confirm_backup; then
    fail "Source installation found at $prefix. Use --replace to back it up and switch."
  fi
fi

scratch=''
trap 'if [[ -n $scratch ]]; then rm -rf -- "$scratch"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -e $version_dir || -L $version_dir ]]; then
  if [[ ! -d $version_dir || -L $version_dir ]] || ! check_release "$version_dir"; then
    fail "Stored release failed verification: $version_dir"
  fi
else
  scratch=$(mktemp -d -- "$store/versions/.staging.XXXXXXXX")
  name=lemux-$release_version
  url=https://github.com/eliaschampi/lemux/releases/download/v$release_version/$name.tar.gz
  archive=$scratch/release.tar.gz
  printf 'Downloading LEmux %s\n' "$release_version"
  curl --disable --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 120 --output "$archive" -- "$url" ||
    fail "Download failed for LEmux $release_version"
  actual=$(sha256sum <"$archive")
  [[ ${actual%% *} == "$release_sha256" ]] || fail "SHA-256 mismatch for LEmux $release_version"
  tar --extract --gzip --file "$archive" --directory "$scratch" --no-same-owner --no-same-permissions \
    "$name/bin/lemux" "$name/lib/lemux" "$name/man/lemux.1" "$name/completions" ||
    fail "Unable to unpack the verified release"
  printf '%s\n' "$release_sha256" >"$scratch/$name/.release-sha256"
  check_release "$scratch/$name" || fail "The staged CLI failed its version check"
  mv -T -- "$scratch/$name" "$version_dir"
fi

for path in "${paths[@]}"; do
  dest=$prefix/$path
  mkdir -p -- "${dest%/*}"
done

if (("${#legacy[@]}")); then
  backup=$(mktemp -d -- "$store/backup.XXXXXXXX")
  mkdir -- "$backup/lib"
  cp -rp -- "$prefix/lib/lemux" "$backup/lib/"
  for path in "${legacy[@]}"; do
    mkdir -p -- "$backup/${path%/*}"
    cp -p -- "$prefix/$path" "$backup/$path"
  done
  printf 'Previous entry points backed up to %s\n' "$backup"
fi

# A legacy executable remains usable until its link is installed last.
# For managed upgrades, repair entry points while the old pointer is active.
if [[ ! -d $current ]]; then publish_link "$slot" "$current"; fi
for i in "${!paths[@]}"; do
  dest=$prefix/${paths[i]}
  target=$current/${members[i]}
  if [[ -L $dest && $(readlink -- "$dest") == "$target" ]]; then continue; fi
  publish_link "$target" "$dest"
done
if [[ $(readlink -- "$current") != "$slot" ]]; then publish_link "$slot" "$current"; fi

printf 'Installed LEmux %s at %s/bin/lemux\n' "$release_version" "$prefix"
if [[ :$PATH: != *":$prefix/bin:"* ]]; then
  printf 'Add %q to your PATH to run lemux by name.\n' "$prefix/bin"
fi
