#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
helper="$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-session-language"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE lingua sessione: %s\n' "$*" >&2
    exit 1
}

session_environment() {
    env -i PATH="$PATH" HOME="$tmp_dir" LANG=C.UTF-8 LANGUAGE= LC_MESSAGES=C.UTF-8 \
        WASALIGHT_LANGUAGE_FILE="$1" sh -c \
        '. "$1"; printf "%s|%s|%s|%s\n" "$WASALIGHT_LANGUAGE" "$LANG" "$LANGUAGE" "$LC_MESSAGES"' \
        sh "$helper"
}

preference="$tmp_dir/language"
printf 'it\n' >"$preference"
[[ $(session_environment "$preference") == 'it|it_IT.UTF-8|it|it_IT.UTF-8' ]] || \
    fail "la preferenza italiana non viene applicata"

printf 'en\n' >"$preference"
[[ $(session_environment "$preference") == 'en|en_US.UTF-8|en|en_US.UTF-8' ]] || \
    fail "la preferenza inglese non viene applicata"

printf 'auto\n' >"$preference"
[[ $(session_environment "$preference") == 'auto|C.UTF-8||C.UTF-8' ]] || \
    fail "la modalità automatica non conserva la locale della sessione"

printf 'unsupported\n' >"$preference"
[[ $(session_environment "$preference") == 'auto|C.UTF-8||C.UTF-8' ]] || \
    fail "una preferenza non valida non torna alla modalità automatica"

[[ $(session_environment "$tmp_dir/missing") == 'auto|C.UTF-8||C.UTF-8' ]] || \
    fail "una preferenza mancante non torna alla modalità automatica"
