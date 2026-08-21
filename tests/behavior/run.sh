#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
inherited_lock_fixture=$(mktemp)
cleanup() {
    rm -f -- "$inherited_lock_fixture"
}
trap cleanup EXIT

for test_script in \
    "$TEST_DIR/operation-lock.sh" \
    "$TEST_DIR/release-manifest.sh" \
    "$TEST_DIR/updater-lib.sh" \
    "$TEST_DIR/session-language.sh" \
    "$TEST_DIR/system-i18n.sh" \
    "$TEST_DIR/openbox-menu.sh" \
    "$TEST_DIR/update-ui-i18n.sh" \
    "$TEST_DIR/plugin-localization.sh"; do
    printf 'BEHAVIOR  %s\n' "${test_script##*/}"
    if [[ ${test_script##*/} == operation-lock.sh ]]; then
        # Reproduce the environment present when the updater verifies a newly
        # downloaded checkout. The lock test must still exercise real
        # contention rather than treating itself as a nested updater action.
        (
            exec 9>>"$inherited_lock_fixture"
            export WASALIGHT_OPERATION_LOCK_HELD=1
            "$test_script"
        )
    else
        "$test_script"
    fi
done

printf 'BEHAVIOR  %s\n' control-core.py
python3 "$TEST_DIR/control-core.py"

printf 'Test comportamentali Wasalight superati.\n'
