#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
generator="$PROJECT_DIR/installer/templates/rootfs/usr/local/bin/wasalight-openbox-menu"
i18n_helper="$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-i18n"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE menu Openbox: %s\n' "$*" >&2
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
grep -Fqx '"Update Wasalight" = "Aggiorna Wasalight";' <<<"$catalog_table" || \
    fail "il catalogo non traduce l'aggiornamento del menu"
grep -Fqx '"Power off" = "Spegni";' <<<"$catalog_table" || \
    fail "il catalogo non traduce lo spegnimento del menu"

if grep -Eqi '^it_IT\.(UTF-8|utf8)$' <<<"$(locale -a 2>/dev/null || true)"; then
    italian_menu="$tmp_dir/menu-it.xml"
    LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
        WASALIGHT_LOCALE_DIR="$tmp_dir/locale" WASALIGHT_I18N_HELPER="$i18n_helper" \
        "$generator" "$italian_menu"
    grep -Fq 'label="Aggiorna Wasalight"' "$italian_menu" || \
        fail "il menu italiano non traduce l'aggiornamento"
    grep -Fq 'label="Spegni"' "$italian_menu" || \
        fail "il menu italiano non traduce lo spegnimento"
fi

english_menu="$tmp_dir/menu-en.xml"
LANG=C LANGUAGE= LC_ALL=C \
    WASALIGHT_LOCALE_DIR="$tmp_dir/locale" WASALIGHT_I18N_HELPER="$i18n_helper" \
    "$generator" "$english_menu"
grep -Fq 'label="Update Wasalight"' "$english_menu" || \
    fail "il menu inglese non usa il testo sorgente"
grep -Fq 'label="Power off"' "$english_menu" || \
    fail "il menu inglese non traduce lo spegnimento"

[[ $(stat -c '%a' "$english_menu" 2>/dev/null || stat -f '%Lp' "$english_menu") == 644 ]] || \
    fail "il menu generato non ha permessi 0644"
