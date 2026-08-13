#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
. "$PROJECT_DIR/installer/templates/rootfs/usr/local/libexec/wasalight-update-lib.sh"

fail() {
    printf 'ERRORE updater: %s\n' "$*" >&2
    exit 1
}

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
shift 2
exec "$@"
EOF
cat >"$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
count=0
[[ ! -r $GIT_RETRY_COUNT ]] || count=$(<"$GIT_RETRY_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$GIT_RETRY_COUNT"
if [[ ${GIT_ALWAYS_FAIL:-0} == 1 || $count -lt 3 ]]; then
    exit 42
fi
printf 'mock commit\n'
EOF
cat >"$mock_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mock_bin/timeout" "$mock_bin/git" "$mock_bin/sleep"

retry_count="$tmp_dir/retry.count"
retry_output=$(PATH="$mock_bin:$PATH" GIT_RETRY_COUNT="$retry_count" \
    git_retry fetch origin main 2>"$tmp_dir/retry.stderr") || \
    fail "git_retry non recupera dopo errori temporanei"
[[ $(<"$retry_count") == 3 ]] || fail "git_retry non esegue tre tentativi"
[[ $retry_output == 'mock commit' ]] || fail "output del tentativo riuscito inatteso"
[[ $(grep -c 'nuovo tentativo' "$tmp_dir/retry.stderr") == 2 ]] || \
    fail "i retry non vengono segnalati correttamente"

printf '0\n' >"$retry_count"
set +e
PATH="$mock_bin:$PATH" GIT_RETRY_COUNT="$retry_count" GIT_ALWAYS_FAIL=1 \
    git_retry fetch origin main >/dev/null 2>"$tmp_dir/failure.stderr"
failure_rc=$?
set -e
[[ $failure_rc == 42 ]] || fail "git_retry non conserva il codice di errore finale"
[[ $(<"$retry_count") == 3 ]] || fail "git_retry non si ferma dopo tre errori"
