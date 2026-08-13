#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# One inherited lock serializes every mutating Wasalight administration task.

wasalight_acquire_operation_lock() {
    local operation=${1:-operation}
    local lock_file=${WASALIGHT_OPERATION_LOCK_FILE:-/run/lock/wasalight-operation.lock}

    if [[ ${WASALIGHT_OPERATION_LOCK_HELD:-} == 1 && -e /proc/$$/fd/9 ]]; then
        return 0
    fi

    install -d -m 0755 "$(dirname "$lock_file")"
    exec 9>>"$lock_file"
    if ! flock -n 9; then
        local holder=unknown suffix=
        IFS= read -r holder <"$lock_file" || true
        [[ -z $holder ]] || suffix=": $holder"
        printf 'Operazione Wasalight già in corso%s.\n' "$suffix" >&2
        return 73
    fi
    printf '%s (PID %s)\n' "$operation" "$$" >"$lock_file"
    export WASALIGHT_OPERATION_LOCK_HELD=1
}
