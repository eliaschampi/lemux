# shellcheck shell=bash
# pkg.sh — one interface over apt/dpkg, dnf/rpm, pacman and zypper.

pkg_backend() {
  if has dpkg-query && has apt-get; then echo apt
  elif has dnf || has dnf5; then echo dnf
  elif has pacman; then echo pacman
  elif has zypper; then echo zypper
  else echo none
  fi
}
PKG=$(pkg_backend)
DNF=$(command -v dnf5 || command -v dnf || echo dnf)

pkg_is_installed() {
  case $PKG in
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q ' installed$' ;;
    dnf | zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

pkg_purge() {
  local -a yes=() mode=() pacman_yes=()
  if [[ $LEMUX_YES == 1 ]]; then yes=(-y); mode=(--non-interactive); pacman_yes=(--noconfirm); fi
  case $PKG in
    apt)
      local plan extra
      plan=$(LC_ALL=C apt-get -s purge -- "$1") || return 1
      extra=$(awk -v id="$1" '/^(Purg|Remv)/ {name=$2; sub(/:[^:]+$/, "", name); if (name != id) print $2}' <<<"$plan")
      [[ -z $extra ]] || { err "apt would also remove: ${extra//$'\n'/ }"; return 1; }
      as_root apt-get "${yes[@]}" purge -- "$1" ;;
    dnf) as_root "$DNF" "${yes[@]}" --setopt=clean_requirements_on_remove=False remove -- "$1" ;;
    pacman) as_root pacman -R "${pacman_yes[@]}" -- "$1" ;;
    zypper) as_root zypper "${mode[@]}" remove -- "$1" ;;
    *) return 1 ;;
  esac
}

pkg_cache_dirs() {
  case $PKG in
    apt) echo /var/cache/apt/archives ;;
    dnf) printf '%s\n' /var/cache/dnf /var/cache/libdnf5 ;;
    pacman) echo /var/cache/pacman/pkg ;;
    zypper) echo /var/cache/zypp/packages ;;
  esac
}

pkg_cache_clean() {
  case $PKG in
    apt) as_root apt-get clean ;;
    dnf) as_root "$DNF" clean packages ;;
    pacman) if has paccache; then as_root paccache -rk1; else as_root pacman -Sc --noconfirm; fi ;;
    zypper) as_root zypper clean --all ;;
  esac
}

pkg_orphans() {
  local list rc=0
  case $PKG in
    apt) list=$(LC_ALL=C apt-get -s autoremove | awk '/^Remv/{print $2}') || return 1 ;;
    dnf) list=$("$DNF" -q repoquery --unneeded --qf '%{name}\n') || return 1 ;;
    pacman)
      list=$(pacman -Qdtq) || rc=$?
      ((rc == 0 || (rc == 1 && ${#list} == 0))) || return 1 ;;
    zypper)
      list=$(LC_ALL=C zypper -q packages --unneeded |
        awk -F'|' 'NF >= 5 && $1 ~ /^[[:space:]]*i/ {gsub(/[[:space:]]/,"",$3); print $3}') || return 1 ;;
    *) return 0 ;;
  esac
  if [[ -n $list ]]; then sort -u <<<"$list"; fi
}

pkg_orphans_remove() {
  local -a list
  mapfile -t list <<<"$1"
  case $PKG in
    apt) as_root apt-get -y purge -- "${list[@]}" ;;
    dnf) as_root "$DNF" -y --setopt=clean_requirements_on_remove=False remove -- "${list[@]}" ;;
    pacman) as_root pacman -R --noconfirm -- "${list[@]}" ;;
    zypper) as_root zypper -n remove -- "${list[@]}" ;;
  esac
}

pkg_broken() {
  case $PKG in
    apt) LC_ALL=C dpkg --audit ;;
    pacman) LC_ALL=C pacman -Dk ;;
    dnf) LC_ALL=C "$DNF" -q check ;;
    *) return 2 ;;
  esac
}

pkg_fix_broken() {
  case $PKG in
    apt) as_root dpkg --configure -a && as_root apt-get -y --no-remove -f install ;;
    *) return 1 ;;
  esac
}

pkg_upgrade() { # refresh metadata and upgrade every package
  case $PKG in
    apt) as_root apt-get update && as_root env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade ;;
    dnf) as_root "$DNF" -y upgrade --refresh ;;
    pacman) as_root pacman -Syu --noconfirm ;;
    zypper) as_root zypper -n refresh && as_root zypper -n update ;;
    *) return 1 ;;
  esac
}
