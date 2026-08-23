#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -u

umask 077

MIN_RAM_KIB=$((1920 * 1024))
RECOMMENDED_RAM_KIB=$((3840 * 1024))
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RELEASE_MANIFEST=$SCRIPT_DIR/release-manifest.ini

manifest_repository() {
  awk -F= '
    /^[[:space:]]*\[/ {
      section=$0
      sub(/^[[:space:]]*\[/, "", section)
      sub(/\][[:space:]]*$/, "", section)
      next
    }
    section == "Wasalight" && $1 == "Repository" {
      value=substr($0, index($0, "=") + 1)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      found=1
      exit
    }
    END { if (!found) exit 1 }
  ' "$RELEASE_MANIFEST"
}

repository_host() {
  candidate=$1
  case "$candidate" in
    https://[A-Za-z0-9]* ) ;;
    *) return 1 ;;
  esac
  host=$(printf '%s\n' "$candidate" | sed -E 's#^https://([^/:]+).*$#\1#')
  case "$host" in
    ''|*[!A-Za-z0-9.-]*|.*|*.) return 1 ;;
  esac
  printf '%s\n' "$host"
}

memory_class() {
  memory_kib=$1
  case "$memory_kib" in
    ''|*[!0-9]*) return 2 ;;
  esac
  if [ "$memory_kib" -lt "$MIN_RAM_KIB" ]; then
    printf 'insufficient\n'
  elif [ "$memory_kib" -lt "$RECOMMENDED_RAM_KIB" ]; then
    printf 'warning\n'
  else
    printf 'recommended\n'
  fi
}

case "${1:-}" in
  '') ;;
  --classify-memory)
    [ "$#" -eq 2 ] || exit 2
    memory_class "$2"
    exit $?
    ;;
  --repository-host)
    [ "$#" -eq 2 ] || exit 2
    repository_host "$2"
    exit $?
    ;;
  *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
esac

[ -r "$RELEASE_MANIFEST" ] || {
  echo "ERROR: release-manifest.ini is unavailable." >&2
  exit 1
}
repository=$(manifest_repository) || {
  echo "ERROR: Wasalight.Repository is missing from release-manifest.ini." >&2
  exit 1
}
host=$(repository_host "$repository") || {
  echo "ERROR: Wasalight.Repository is not a valid HTTPS URL." >&2
  exit 1
}

TTY=/dev/tty1
[ -c "$TTY" ] || TTY=/dev/console
exec <"$TTY" >"$TTY" 2>&1

clear_screen() { printf '\033[2J\033[H'; }
green() { printf '\033[1;32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$1"; }
red() { printf '\033[1;31m%s\033[0m\n' "$1"; }

while :; do
  clear_screen
  echo "=============================================================="
  green "                  SYSTEM PREFLIGHT"
  echo "=============================================================="
  echo

  failures=0
  ram_kib=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)
  ram_state=$(memory_class "$ram_kib" 2>/dev/null || echo invalid)
  ram_mib=$(( ${ram_kib:-0} / 1024 ))
  case "$ram_state" in
    insufficient)
      red "[FAIL] Memory: ${ram_mib} MiB available; at least 2 GiB is required."
      failures=$((failures + 1))
      ;;
    warning)
      yellow "[WARN] Memory: ${ram_mib} MiB available; 4 GiB or more is recommended."
      ;;
    recommended)
      green "[ OK ] Memory: ${ram_mib} MiB available."
      ;;
    *)
      red "[FAIL] Unable to determine installed memory."
      failures=$((failures + 1))
      ;;
  esac

  if ip -o link show up 2>/dev/null | awk -F': ' '$2 !~ /^lo(@|$)/ { found=1 } END { exit found ? 0 : 1 }'; then
    green "[ OK ] Network interface is active."
  else
    red "[FAIL] No active network interface."
    failures=$((failures + 1))
  fi

  if ip -o addr show scope global 2>/dev/null | grep -q .; then
    green "[ OK ] Network address is configured."
  else
    red "[FAIL] No global network address."
    failures=$((failures + 1))
  fi

  if { ip -4 route show default 2>/dev/null; ip -6 route show default 2>/dev/null; } | grep -q .; then
    green "[ OK ] Default route is available."
  else
    red "[FAIL] No default route."
    failures=$((failures + 1))
  fi

  if getent ahosts "$host" >/dev/null 2>&1; then
    green "[ OK ] DNS resolves $host."
  else
    red "[FAIL] DNS cannot resolve $host."
    failures=$((failures + 1))
  fi

  if curl --fail --silent --show-error --location --head \
      --connect-timeout 5 --max-time 15 "$repository" >/dev/null 2>&1; then
    green "[ OK ] HTTPS access to the Wasalight repository."
  else
    red "[FAIL] Cannot reach the Wasalight repository over HTTPS."
    failures=$((failures + 1))
  fi

  echo
  if [ "$failures" -ne 0 ]; then
    echo "Internet and at least 2 GiB of RAM are required in FULL and NETBOOT mode."
    echo "Check the cable, DHCP/DNS configuration and available memory."
    printf "Press ENTER to retry... "
    IFS= read -r _dummy
    continue
  fi

  if [ "$ram_state" = warning ]; then
    printf "Preflight passed with a memory warning. Press ENTER to continue... "
    IFS= read -r _dummy
  else
    echo "Preflight passed."
    sleep 1
  fi

  printf 'Internet verified (%s); memory %s MiB\n' "$host" "$ram_mib" \
    >/run/wasalight-preflight-status
  break
done
