#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
HELPER="$REPO_ROOT/installer/templates/rootfs/usr/local/sbin/wasalight-magicq-network"
fixture=$(mktemp -d)
cleanup() {
    rm -rf -- "$fixture"
}
trap cleanup EXIT

mkdir -p "$fixture/MagicQ/show"
printf 'T,"/home/chamsys/Documents/MagicQ/show/active.sbk"\n' \
    >"$fixture/MagicQ/show/status.dat"
printf '\\ Time: 2026-08-27 Hostname: wasalight IP: 2.9.200.82\n52c80902,0000,000000ff,"tig",00000000,\n' \
    >"$fixture/MagicQ/show/active.sbk"

result=$(WASALIGHT_MAGICQ_ROOT="$fixture/MagicQ" \
    WASALIGHT_MAGICQ_STATUS="$fixture/MagicQ/show/status.dat" \
    "$HELPER" inspect --json)
python3 - "$result" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["address"] == "2.9.200.82"
assert value["netmask"] == "255.0.0.0"
assert value["prefix"] == 8
assert value["cidr"] == "2.9.200.82/8"
assert value["gateway"] == "0.0.0.0"
PY

printf '\\ Time: 2026-08-27 Hostname: wasalight IP: 2.9.200.83\n52c80902,0000,000000ff,"tig",00000000,\n' \
    >"$fixture/MagicQ/show/active.sbk"
if WASALIGHT_MAGICQ_ROOT="$fixture/MagicQ" \
        WASALIGHT_MAGICQ_STATUS="$fixture/MagicQ/show/status.dat" \
        "$HELPER" inspect --json >/dev/null 2>&1; then
    printf 'MagicQ network accepted mismatched header and encoded address\n' >&2
    exit 1
fi

printf 'MagicQ network parser behavior verified.\n'
