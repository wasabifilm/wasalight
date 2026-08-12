#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for test_script in \
    "$TEST_DIR/operation-lock.sh" \
    "$TEST_DIR/release-manifest.sh" \
    "$TEST_DIR/updater-lib.sh"; do
    printf 'BEHAVIOR  %s\n' "${test_script##*/}"
    "$test_script"
done

printf 'Test comportamentali Wasalight superati.\n'
