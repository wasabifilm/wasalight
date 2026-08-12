#!/usr/bin/env bash
set -Eeuo pipefail

# verify-project.sh also runs this test from inside the updater, which already
# owns the production operation lock.  Isolate the test process from that
# inherited state while leaving the updater parent and its lock untouched.
unset WASALIGHT_OPERATION_LOCK_HELD WASALIGHT_OPERATION_LOCK_FILE
if { : <&9; } 2>/dev/null; then
    exec 9>&-
fi

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
tmp_dir=$(mktemp -d)
holder_pid=
cleanup() {
    if [[ ${holder_pid:-} =~ ^[0-9]+$ ]]; then
        kill "$holder_pid" 2>/dev/null || true
        wait "$holder_pid" 2>/dev/null || true
    fi
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'ERRORE lock: %s\n' "$*" >&2
    exit 1
}

lock_file="$tmp_dir/operation.lock"
ready_file="$tmp_dir/holder.ready"
release_fifo="$tmp_dir/release.fifo"
mkfifo "$release_fifo"
if ! command -v flock >/dev/null 2>&1; then
    mock_bin="$tmp_dir/bin"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/flock" <<'PY'
#!/usr/bin/env python3
import fcntl
import sys

if sys.argv[1:] != ["-n", "9"]:
    raise SystemExit(2)
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit(1)
PY
    chmod +x "$mock_bin/flock"
    export PATH="$mock_bin:$PATH"
fi

WASALIGHT_OPERATION_LOCK_FILE="$lock_file" READY_FILE="$ready_file" \
    RELEASE_FIFO="$release_fifo" \
    bash -c '
        set -Eeuo pipefail
        . "$1"
        wasalight_acquire_operation_lock "test holder"
        touch "$READY_FILE"
        read -r _ <"$RELEASE_FIFO"
    ' _ "$PROJECT_DIR/lib/wasalight-operation-lock.sh" &
holder_pid=$!

for _ in {1..50}; do
    [[ -e $ready_file ]] && break
    kill -0 "$holder_pid" 2>/dev/null || fail "il processo holder è terminato"
    sleep 0.02
done
[[ -e $ready_file ]] || fail "il primo processo non ha acquisito il lock"

set +e
contention_output=$(WASALIGHT_OPERATION_LOCK_FILE="$lock_file" \
    bash -c '
        set -Eeuo pipefail
        . "$1"
        wasalight_acquire_operation_lock "test contender"
    ' _ "$PROJECT_DIR/lib/wasalight-operation-lock.sh" 2>&1)
contention_rc=$?
set -e
[[ $contention_rc == 73 ]] || fail "la contesa restituisce $contention_rc invece di 73"
[[ $contention_output == *'Operazione Wasalight già in corso: test holder'* ]] || \
    fail "il messaggio di contesa non identifica l'operazione attiva"

printf 'release\n' >"$release_fifo"
wait "$holder_pid"
holder_pid=

WASALIGHT_OPERATION_LOCK_FILE="$lock_file" bash -c '
    set -Eeuo pipefail
    . "$1"
    wasalight_acquire_operation_lock "test released"
    wasalight_acquire_operation_lock "test reentrant"
    [[ $WASALIGHT_OPERATION_LOCK_HELD == 1 ]]
' _ "$PROJECT_DIR/lib/wasalight-operation-lock.sh" || \
    fail "il lock non viene rilasciato o non è rientrante"
