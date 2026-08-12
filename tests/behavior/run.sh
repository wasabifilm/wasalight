#!/usr/bin/env bash
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
    "$TEST_DIR/updater-lib.sh"; do
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

printf 'Test comportamentali Wasalight superati.\n'
