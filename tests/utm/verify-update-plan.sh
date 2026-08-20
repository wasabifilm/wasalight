#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Run on the disposable UTM appliance to prove that --plan is non-mutating.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
[[ $(findmnt -n -o FSTYPE / 2>/dev/null) != overlay ]] || {
    echo "Run in MAINTENANCE mode." >&2; exit 1;
}

temporary=$(mktemp -d /tmp/wasalight-plan-test.XXXXXX)
trap 'rm -rf -- "$temporary"' EXIT

inventory() {
    local output=$1
    find /etc/wasalight /data/system -xdev -type f \
        ! -path '/data/system/update-check/*' \
        ! -path '/data/system/health/*' -print0 2>/dev/null | \
        sort -z | xargs -0 sha256sum >"$output"
}

inventory "$temporary/before"
update_args=(--channel debug --plan)
installed_magicq=$(dpkg-query -W -f='${db:Status-Abbrev}' magicq 2>/dev/null || true)
[[ $installed_magicq == ii* ]] || update_args+=(--allow-missing-magicq)
/usr/local/sbin/wasalight-update "${update_args[@]}"
inventory "$temporary/after"
diff -u "$temporary/before" "$temporary/after"
echo "PASS: --plan did not change persistent Wasalight files."
