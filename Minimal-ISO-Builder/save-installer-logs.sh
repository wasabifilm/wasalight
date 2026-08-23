#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -u

umask 027

outcome=${1:-}
case "$outcome" in
  success|failed) ;;
  *) echo "ERROR: expected installer outcome: success or failed." >&2; exit 2 ;;
esac

# An early failure can happen before /data exists. Never write into the target
# root filesystem while merely assuming that the dedicated data LV is mounted.
findmnt -n -M /target/data >/dev/null 2>&1 || exit 0

log_dir=/target/data/log/installer
mkdir -p "$log_dir" || exit 0
chmod 0750 "$log_dir" 2>/dev/null || true

scrub_log() {
  source_file=$1
  destination_file=$2
  [ -r "$source_file" ] || return 0
  sed -E \
    -e 's/^([[:space:]]*password:).*/\1 "<redacted>"/' \
    -e 's#\$6\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+#<redacted-password-hash>#g' \
    "$source_file" >"$log_dir/$destination_file" 2>/dev/null || return 0
  chmod 0640 "$log_dir/$destination_file" 2>/dev/null || true
}

scrub_log /var/log/installer/subiquity-server-debug.log subiquity-server-debug.log
scrub_log /var/log/installer/subiquity-client-debug.log subiquity-client-debug.log
scrub_log /var/log/installer/curtin-install.log curtin-install.log
scrub_log /run/wasalight-ui.log wasalight-ui.log
scrub_log /run/wasalight-theme.log wasalight-theme.log
scrub_log /autoinstall.yaml autoinstall.yaml

{
  printf 'outcome=%s\n' "$outcome"
  printf 'saved_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  printf 'installer_version=%s\n' "$(sed -n '1p' /cdrom/wasalight/VERSION 2>/dev/null || sed -n '1p' /wasalight/VERSION 2>/dev/null || echo unknown)"
  printf 'variant=%s\n' "$(sed -n '1p' /run/wasalight-install-variant 2>/dev/null || echo unknown)"
  printf 'target_disk=%s\n' "$(sed -n '1p' /run/wasalight-target-disk 2>/dev/null || echo unknown)"
  printf 'keyboard=%s\n' "$(sed -n '1p' /run/wasalight-keyboard-label 2>/dev/null || echo unknown)"
  printf 'timezone=%s\n' "$(sed -n '1p' /run/wasalight-timezone-label 2>/dev/null || echo unknown)"
  printf 'preflight=%s\n' "$(sed -n '1p' /run/wasalight-preflight-status 2>/dev/null || echo unknown)"
} >"$log_dir/status" 2>/dev/null || true
chmod 0640 "$log_dir/status" 2>/dev/null || true

exit 0
