#!/usr/bin/env bash
# linux distro converter installer
# auto-installs bedrock linux and switches distro

set -euo pipefail

# ascii welcome
ASCII="
=====================================
   🌀 LINUX DISTRO CONVERTER INSTALLER
=====================================
"

SUPPORTED=("arch" "centos" "debian" "devuan" "fedora" "gentoo" "ubuntu" "void" "void-musl")

# defaults
VERBOSE=false
userpkgs=""

log(){
  $VERBOSE && echo "[*] $1"
}
err(){
  echo "[ERR] $1" >&2
  exit 1
}

check_root(){
  if [[ $EUID -ne 0 ]]; then
    err "run as root!"
  fi
}

parse_args(){
  for arg in "$@"; do
    case $arg in
      --verbose) VERBOSE=true ;;
      --hijack) HIJACK=true ;; # HIJACK is not used, but kept for compatibility
      -h|--help)
        echo "Usage: $0 [--verbose] [--hijack]"
        exit 0
        ;;
    esac
  done
}

check_network(){
  log "checking for working network (not ping)..."
  if command -v nc >/dev/null 2>&1; then
    if nc -zw2 8.8.8.8 53; then
      log "network ok via TCP"
    else
      err "no network detected! connect via ethernet or wifi first"
    fi
  else
    # fallback: try connecting with curl
    if curl -s --head https://google.com | grep -q "200 OK"; then
      log "network ok via curl"
    else
      err "no network detected and nc not found! Please install netcat or connect to internet."
    fi
  fi
}

detect_distro(){
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  else
    err "cannot detect base distro"
  fi
}

confirm(){
  read -rp "$1 [$2]: " ans
  if [[ "${ans,,}" != "${2,,}" ]]; then
    err "confirmation failed"
  fi
}

select_distro(){
  echo "choose distro to install:"
  for i in "${!SUPPORTED[@]}"; do
    printf "%2d) %s\n" $((i+1)) "${SUPPORTED[i]}"
  done
  read -rp "enter number: " idx
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#SUPPORTED[@]} )); then
    err "invalid selection"
  fi
  TARGET="${SUPPORTED[idx-1]}"
}

read_pkgs(){
  read -rp "additional packages to install (comma-separated, e.g. htop,networkmanager): " userpkgs
  userpkgs="${userpkgs// /}" # remove all spaces
}

detect_target_pkgmgr(){
  # crude deduction based on TARGET name
  case "$TARGET" in
    arch)   echo "pacman -Sy --noconfirm" ;;
    void|void-musl) echo "xbps-install -Sy" ;;
    debian|ubuntu|devuan) echo "apt-get install -y" ;;
    fedora|centos) echo "dnf install -y" ;;
    gentoo) echo "emerge" ;;
    alpine) echo "apk add" ;;
    *) echo "" ;;
  esac
}

install_bedrock(){
  log "getting latest beta release tag from GitHub"
  url="$(curl -s https://api.github.com/repos/bedrocklinux/bedrocklinux-userland/releases | \
        awk '/"prerelease": true/{p=1} p&&/"browser_download_url"/{print $2; exit}' | tr -d '",')"
  [ -z "$url" ] && err "Could not fetch Bedrock Linux installer URL"
  tmpfile="$(mktemp /tmp/brl-installer.XXXXXX.sh)"
  trap 'rm -f "$tmpfile"' EXIT
  curl -L -o "$tmpfile" "$url"
  chmod +x "$tmpfile"
  log "running bedrock installer"
  "$tmpfile" --hijack
}

install_packages(){
  local pkgmgr
  pkgmgr="$(detect_target_pkgmgr)"
  if [[ -z "$pkgmgr" ]]; then
    log "Unknown package manager for $TARGET, trying all known..."
    for pkg in "${arr[@]}"; do
      brl run "$TARGET" -- sh -c \
        "pacman -Sy --noconfirm $pkg || apt-get install -y $pkg || dnf install -y $pkg || xbps-install -Sy $pkg || apk add $pkg || emerge $pkg"
    done
  else
    for pkg in "${arr[@]}"; do
      log "install $pkg in $TARGET"
      brl run "$TARGET" -- sh -c "$pkgmgr $pkg"
    done
  fi
}

main(){
  parse_args "$@"
  check_root
  echo "$ASCII"
  check_network
  BASE=$(detect_distro)
  confirm "Type exactly 'Not reversible!'" "Not reversible!"

  install_bedrock

  select_distro
  log "fetching and enabling '$TARGET'"
  brl fetch "$TARGET"
  brl enable "$TARGET"
  read_pkgs

  if [[ -n "${userpkgs// /}" ]]; then
    IFS=',' read -ra arr <<<"$userpkgs"
    install_packages
  fi

  read -rp "remove original distro '$BASE'? [y/N]: " rm
  if [[ "${rm,,}" == "y" ]]; then
    brl remove -d "$BASE"
  fi

  echo "✅ Done! reboot now to enter '$TARGET' (or use 'strat $TARGET bash')"
}

main "$@"
