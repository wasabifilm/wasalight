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

translated=$(
    LANG=it_IT.UTF-8 LANGUAGE=it LC_ALL=it_IT.UTF-8 \
        WASALIGHT_LOCALE_DIR="$tmp_dir" bash -c \
        '. "$1"; _ "Restart the workstation now?"' bash "$helper"
)
[[ $translated == 'Riavviare adesso la postazione?' ]] || \
    fail "il catalogo italiano non viene caricato"

fallback=$(
    LANG=en_US.UTF-8 LANGUAGE=en LC_ALL=en_US.UTF-8 \
        WASALIGHT_LOCALE_DIR="$tmp_dir" bash -c \
        '. "$1"; _ "Restart the workstation now?"' bash "$helper"
)
[[ $fallback == 'Restart the workstation now?' ]] || \
    fail "il fallback inglese non conserva il testo sorgente"
