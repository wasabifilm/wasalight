#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
toggle="$PROJECT_DIR/installer/templates/rootfs/usr/local/bin/wasalight-keyboard-toggle"
i18n_helper="$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-i18n"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE toggle tastiera: %s\n' "$*" >&2
    exit 1
}

mock_dir="$tmp_dir/bin"
runtime_dir="$tmp_dir/runtime"
state_file="$tmp_dir/state"
event_log="$tmp_dir/events"
install -d "$mock_dir" "$runtime_dir"

write_mock() {
    local name=$1
    shift
    {
        printf '#!/usr/bin/env bash\nset -u\n'
        printf '%s\n' "$@"
    } >"$mock_dir/$name"
    chmod +x "$mock_dir/$name"
}

write_mock id '[[ ${1:-} == -u ]] && { printf "1000\n"; exit 0; }' 'exit 1'
write_mock flock 'exit 0'
write_mock gsettings 'exit 0'
write_mock sleep '/bin/sleep 0.01'
write_mock wmctrl 'exit 0'
write_mock xdpyinfo 'printf "  dimensions:    1280x720 pixels (338x190 millimeters)\n"'
write_mock onboard \
    'printf "launch\n" >>"$WASALIGHT_KEYBOARD_TEST_EVENTS"' \
    'printf "visible\n" >"$WASALIGHT_KEYBOARD_TEST_STATE"'
write_mock pgrep \
    'state=$(cat "$WASALIGHT_KEYBOARD_TEST_STATE" 2>/dev/null || true)' \
    '[[ $state == visible || $state == hidden || $state == resistant ]]'
write_mock pkill \
    'signal=${1:-}' \
    'printf "%s\n" "$signal" >>"$WASALIGHT_KEYBOARD_TEST_EVENTS"' \
    'state=$(cat "$WASALIGHT_KEYBOARD_TEST_STATE" 2>/dev/null || true)' \
    'if [[ $signal == -KILL || $state != resistant ]]; then' \
    '    printf "stopped\n" >"$WASALIGHT_KEYBOARD_TEST_STATE"' \
    'fi'
write_mock xwininfo \
    'state=$(cat "$WASALIGHT_KEYBOARD_TEST_STATE" 2>/dev/null || true)' \
    'if [[ ${1:-} == -root && $state != stopped ]]; then' \
    '    printf '\''0x0400007 "Onboard": ("onboard" "Onboard") 800x300+0+0 +0+0\n'\''' \
    'elif [[ ${1:-} == -id ]]; then' \
    '    [[ $state == visible || $state == resistant ]] && printf "  Map State: IsViewable\n" || printf "  Map State: IsUnMapped\n"' \
    'fi'

run_case() {
    local initial_state=$1
    : >"$event_log"
    printf '%s\n' "$initial_state" >"$state_file"
    PATH="$mock_dir:$PATH" XDG_RUNTIME_DIR="$runtime_dir" \
        WASALIGHT_I18N_HELPER="$i18n_helper" \
        WASALIGHT_KEYBOARD_TEST_STATE="$state_file" \
        WASALIGHT_KEYBOARD_TEST_EVENTS="$event_log" \
        "$toggle"
}

run_case stopped
[[ $(cat "$event_log") == launch ]] || \
    fail "un primo tocco non avvia Onboard"

run_case visible
[[ $(cat "$event_log") == -TERM ]] || \
    fail "un tocco con finestra visibile non chiude soltanto Onboard"

run_case hidden
[[ $(cat "$event_log") == $'-TERM\nlaunch' ]] || \
    fail "un processo nascosto non viene ripulito e riaperto nello stesso tocco"

run_case resistant
[[ $(cat "$event_log") == $'-TERM\n-KILL' ]] || \
    fail "un processo resistente a SIGTERM non usa il fallback SIGKILL"
