#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
helper="$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-i18n"
catalog="$PROJECT_DIR/ui/locale/it/LC_MESSAGES/wasalight-system.po"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE gettext sistema: %s\n' "$*" >&2
    exit 1
}

install -d "$tmp_dir/it/LC_MESSAGES"
msgfmt --check -o "$tmp_dir/it/LC_MESSAGES/wasalight-system.mo" "$catalog"

catalog_table=$(msgunfmt --stringtable-output \
    "$tmp_dir/it/LC_MESSAGES/wasalight-system.mo")
grep -Fqx '"Restart the workstation now?" = "Riavviare adesso la postazione?";' \
    <<<"$catalog_table" || fail "il catalogo non contiene la traduzione italiana attesa"
grep -Fqx '"<big><b>MagicQ is ready.</b></big>\\n\\n%s" = "<big><b>MagicQ è pronto.</b></big>\\n\\n%s";' \
    <<<"$catalog_table" || fail "il catalogo non conserva la stringa multilinea"

if grep -Eqi '^it_IT\.(UTF-8|utf8)$' <<<"$(locale -a 2>/dev/null || true)"; then
    translated=$(
        LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
            WASALIGHT_LOCALE_DIR="$tmp_dir" bash -c \
            '. "$1"; _ "Restart the workstation now?"' bash "$helper"
    )
    [[ $translated == 'Riavviare adesso la postazione?' ]] || \
        fail "il catalogo italiano non viene caricato"

    multiline=$(
        LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
            WASALIGHT_LOCALE_DIR="$tmp_dir" bash -c \
            '. "$1"; _ "<big><b>MagicQ is ready.</b></big>\n\n%s"' bash "$helper"
    )
    [[ $multiline == '<big><b>MagicQ è pronto.</b></big>\n\n%s' ]] || \
        fail "le stringhe multilinea dei dialoghi non vengono tradotte"
else
    printf 'Locale it_IT.UTF-8 non presente: catalogo verificato senza test runtime.\n'
fi

fallback=$(
    LANG=C LANGUAGE= LC_ALL=C \
        WASALIGHT_LOCALE_DIR="$tmp_dir" bash -c \
        '. "$1"; _ "Restart the workstation now?"' bash "$helper"
)
[[ $fallback == 'Restart the workstation now?' ]] || \
    fail "il fallback inglese non conserva il testo sorgente"
