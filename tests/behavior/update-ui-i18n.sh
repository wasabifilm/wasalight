#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
launcher="$PROJECT_DIR/installer/templates/rootfs/usr/local/bin/wasalight-update-terminal"
i18n_helper="$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-i18n"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE lingua updater: %s\n' "$*" >&2
    exit 1
}

for language in en it; do
    install -d "$tmp_dir/locale/$language/LC_MESSAGES"
    msgfmt --check \
        -o "$tmp_dir/locale/$language/LC_MESSAGES/wasalight-system.mo" \
        "$PROJECT_DIR/ui/locale/$language/LC_MESSAGES/wasalight-system.po"
done

catalog_table=$(msgunfmt --stringtable-output \
    "$tmp_dir/locale/it/LC_MESSAGES/wasalight-system.mo")
grep -Fqx '"Unknown option" = "Opzione sconosciuta";' <<<"$catalog_table" || \
    fail "il catalogo non traduce gli errori dell'updater"

if grep -Eqi '^it_IT\.(UTF-8|utf8)$' <<<"$(locale -a 2>/dev/null || true)"; then
    italian_help=$(
        LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
            WASALIGHT_LOCALE_DIR="$tmp_dir/locale" WASALIGHT_I18N_HELPER="$i18n_helper" \
            "$launcher" --help
    )
    [[ $italian_help == Uso:* ]] || fail "l'help italiano dell'updater non è tradotto"

    set +e
    italian_error=$(
        LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
            WASALIGHT_LOCALE_DIR="$tmp_dir/locale" WASALIGHT_I18N_HELPER="$i18n_helper" \
            "$launcher" --unknown 2>&1
    )
    rc=$?
    set -e
    [[ $rc == 2 && $italian_error == 'Opzione sconosciuta: --unknown' ]] || \
        fail "l'errore italiano dell'updater non è tradotto"
fi

english_help=$(
    LANG=C LANGUAGE= LC_ALL=C \
        WASALIGHT_LOCALE_DIR="$tmp_dir/locale" WASALIGHT_I18N_HELPER="$i18n_helper" \
        "$launcher" --help
)
[[ $english_help == Usage:* ]] || fail "l'help inglese dell'updater non usa il testo sorgente"
