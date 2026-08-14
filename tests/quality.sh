#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

require_tools=false
[[ ${1:-} == --require-tools ]] && require_tools=true

run_if_available() {
    local command_name=$1
    shift
    if command -v "$command_name" >/dev/null 2>&1; then
        printf 'QUALITY  %s\n' "$command_name"
        "$@"
    elif $require_tools; then
        printf 'Missing required quality tool: %s\n' "$command_name" >&2
        return 1
    else
        printf 'SKIP     %s (not installed locally)\n' "$command_name"
    fi
}

shell_files=$(git grep -IlE '^#!(/usr/bin/env (ba)?sh|/bin/(ba)?sh)' || true)
shell_fragments=$(git ls-files 'installer/modules/*.sh' 'tests/static/*.sh')
if command -v shellcheck >/dev/null 2>&1; then
    printf 'QUALITY  shellcheck\n'
    # Correctness errors block CI; style findings remain visible during focused work.
    # shellcheck disable=SC2086
    shellcheck --external-sources --severity=error $shell_files
    # Questi file sono inclusi dall'orchestratore Bash e intenzionalmente non
    # hanno uno shebang che li renda eseguibili in modo autonomo.
    # shellcheck disable=SC2086
    shellcheck --shell=bash --external-sources --severity=error $shell_fragments
elif $require_tools; then
    printf 'Missing required quality tool: shellcheck\n' >&2
    exit 1
else
    printf 'SKIP     shellcheck (not installed locally)\n'
fi

run_if_available ruff ruff check --select=E9,F63,F7,F82 \
    ui tests/behavior installer/templates/rootfs/usr/local/libexec

desktop_files=$(find installer/templates/rootfs -type f -name '*.desktop' -print | sort)
if command -v desktop-file-validate >/dev/null 2>&1; then
    printf 'QUALITY  desktop-file-validate\n'
    # shellcheck disable=SC2086
    desktop-file-validate $desktop_files
elif $require_tools; then
    printf 'Missing required quality tool: desktop-file-validate\n' >&2
    exit 1
else
    printf 'SKIP     desktop-file-validate (not installed locally)\n'
fi

if command -v msgfmt >/dev/null 2>&1; then
    printf 'QUALITY  gettext\n'
    while IFS= read -r catalog; do
        msgfmt --check --check-compatibility -o /dev/null "$catalog"
    done < <(find ui/locale -type f -name '*.po' -print | sort)
elif $require_tools; then
    printf 'Missing required quality tool: msgfmt\n' >&2
    exit 1
else
    printf 'SKIP     gettext (not installed locally)\n'
fi

if command -v systemd-analyze >/dev/null 2>&1; then
    printf 'QUALITY  systemd-analyze\n'
    systemd_log=$(mktemp)
    trap 'rm -f "$systemd_log"' EXIT
    systemd_units=$(find installer/templates/rootfs Minimal-ISO-Builder -type f \
        \( -name '*.service' -o -name '*.timer' -o -name '*.path' \) -print | sort)
    # Missing installed executables are expected in the checkout; parse/dependency
    # errors remain fatal after those path-only diagnostics are filtered.
    # shellcheck disable=SC2086
    systemd-analyze verify $systemd_units 2>"$systemd_log" || true
    sed -E '/Command .* is not executable/d; /Failed to open \/usr\/local\//d' \
        "$systemd_log" >"$systemd_log.filtered"
    if [[ -s $systemd_log.filtered ]]; then
        cat "$systemd_log.filtered" >&2
        exit 1
    fi
elif $require_tools; then
    printf 'Missing required quality tool: systemd-analyze\n' >&2
    exit 1
else
    printf 'SKIP     systemd-analyze (not installed locally)\n'
fi

python3 tests/check-doc-links.py
printf 'Quality checks completed.\n'
