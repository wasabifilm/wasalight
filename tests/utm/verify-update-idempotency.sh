#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Destructive only on the disposable UTM test appliance: installs twice.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ ${WASALIGHT_IDEMPOTENCY_CONFIRM:-} == UTM-ONLY ]] || {
    echo "This test reinstalls Wasalight twice. Set WASALIGHT_IDEMPOTENCY_CONFIRM=UTM-ONLY." >&2
    exit 2
}
[[ $(findmnt -n -o FSTYPE / 2>/dev/null) != overlay ]] || {
    echo "Run in MAINTENANCE mode." >&2; exit 1;
}

temporary=$(mktemp -d /tmp/wasalight-idempotency.XXXXXX)
trap 'rm -rf -- "$temporary"' EXIT

inventory() {
    local output=$1
    find /etc/wasalight /usr/local/bin /usr/local/sbin /usr/local/libexec \
        /usr/share/wasalight /etc/systemd/system -xdev -type f \
        \( -name 'wasalight*' -o -name 'magicq*' -o -path '*/wasalight/*' \) \
        -print0 2>/dev/null | sort -z | xargs -0 sha256sum >"$output"
}

/usr/local/sbin/wasalight-update --channel debug --repair
inventory "$temporary/first"
/usr/local/sbin/wasalight-update --channel debug --repair
inventory "$temporary/second"
diff -u "$temporary/first" "$temporary/second"
echo "PASS: two repair installations produced the same managed configuration."
