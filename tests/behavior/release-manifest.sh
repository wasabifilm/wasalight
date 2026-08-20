#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
. "$PROJECT_DIR/lib/wasalight-release-manifest.sh"

fail() {
    printf 'ERRORE manifest: %s\n' "$*" >&2
    exit 1
}

fixture="$tmp_dir/release.ini"
printf '%s\n' \
    '[Wasalight]' \
    'Repository=  https://example.invalid/wasalight.git  ' \
    'Branch=main' \
    'Empty=   ' \
    '' \
    '[Companion]' \
    'Branch=stable' >"$fixture"

[[ $(require_manifest_value "$fixture" Wasalight Repository) == \
    https://example.invalid/wasalight.git ]] || fail "spazi nel valore non normalizzati"
[[ $(require_manifest_value "$fixture" Wasalight Branch) == main ]] || \
    fail "chiave Wasalight errata"
[[ $(require_manifest_value "$fixture" Companion Branch) == stable ]] || \
    fail "sezioni con chiavi omonime non isolate"

if require_manifest_value "$fixture" Missing Value >/dev/null 2>&1; then
    fail "una chiave mancante viene accettata"
fi
if require_manifest_value "$fixture" Wasalight Empty >/dev/null 2>&1; then
    fail "un valore vuoto viene accettato"
fi

for requirement in \
    'Wasalight Repository' 'Wasalight Branch' 'Wasalight VersionURL' \
    'Updates DefaultChannel' 'Updates StableAPI' 'Updates DebugRef' \
    'Updates TagPrefix' 'Updates SignerFile' \
    'Platform UbuntuVersion' 'Platform Architecture' \
    'Companion Version' 'Companion Repository' 'Companion Commit' \
    'MagicQ Package' 'MagicQ Architecture'; do
    read -r section key <<<"$requirement"
    require_manifest_value "$PROJECT_DIR/release-manifest.ini" "$section" "$key" \
        >/dev/null || fail "manifest reale incompleto: [$section] $key"
done
