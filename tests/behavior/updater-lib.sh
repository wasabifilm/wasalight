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
[[ $(grep -c 'retrying' "$tmp_dir/retry.stderr") == 2 ]] || \
    fail "i retry non vengono segnalati correttamente"

printf '0\n' >"$retry_count"
set +e
PATH="$mock_bin:$PATH" GIT_RETRY_COUNT="$retry_count" GIT_ALWAYS_FAIL=1 \
    git_retry fetch origin main >/dev/null 2>"$tmp_dir/failure.stderr"
failure_rc=$?
set -e
[[ $failure_rc == 42 ]] || fail "git_retry non conserva il codice di errore finale"
[[ $(<"$retry_count") == 3 ]] || fail "git_retry non si ferma dopo tre errori"

state_file="$tmp_dir/update-state"
WASALIGHT_UPDATE_STATE_OWNER="$(id -un):$(id -gn)" \
update_state_write "$state_file" running installing 2026.08.20.1 \
    0123456789012345678901234567890123456789 /data/snapshot.tar.zst \
    2026-08-20T10:00:00+02:00 debug /data/system/wasalight.candidate
[[ $(update_state_value "$state_file" status) == running ]] || \
    fail "lo stato transazionale non conserva status"
[[ $(update_state_value "$state_file" phase) == installing ]] || \
    fail "lo stato transazionale non conserva phase"
[[ $(update_state_value "$state_file" candidate) == /data/system/wasalight.candidate ]] || \
    fail "lo stato transazionale non conserva il checkout candidato"
# GNU stat accepts -f too, but interprets it as filesystem status and can
# return a successful, non-mode value. Prefer its native -c form, then fall
# back to the BSD/macOS spelling used by local development machines.
state_mode=$(stat -c '%a' "$state_file" 2>/dev/null || stat -f '%Lp' "$state_file")
[[ $state_mode == 640 ]] || fail "lo stato transazionale non usa permessi 0640"
(
    readonly state_file=/data/system/update-state
    readonly_collision_file="$tmp_dir/readonly-collision-state"
    WASALIGHT_UPDATE_STATE_OWNER="$(id -un):$(id -gn)" \
    update_state_write "$readonly_collision_file" running verified 2026.08.20.1 \
        0123456789012345678901234567890123456789 '' \
        2026-08-20T10:00:00+02:00 debug /data/system/wasalight.candidate
    [[ $(update_state_value "$readonly_collision_file" phase) == verified ]]
) || fail "le funzioni di stato collidono con la variabile readonly dell’updater"
WASALIGHT_UPDATE_STATE_OWNER="$(id -un):$(id -gn)" \
update_state_write "$state_file" complete complete 2026.08.20.1 \
    0123456789012345678901234567890123456789 /data/snapshot.tar.zst \
    2026-08-20T10:00:00+02:00 stable /data/system/wasalight
[[ $(update_state_value "$state_file" status) == complete ]] || \
    fail "la sostituzione atomica dello stato non conserva l'ultimo valore"
if find "$tmp_dir" -maxdepth 1 -name '.wasalight-write.*' | grep -q .; then
    fail "la sostituzione atomica lascia file temporanei"
fi
if WASALIGHT_UPDATE_STATE_OWNER="$(id -un):$(id -gn)" \
    update_state_write "$state_file" $'bad\nstatus' phase version commit snapshot started \
    stable candidate >/dev/null 2>&1; then
    fail "lo stato transazionale accetta valori multilinea"
fi

if normalize_update_channel normale >/dev/null 2>&1; then
    fail "alias di canale precedente ancora accettato"
fi
[[ $(normalize_update_channel debug) == debug ]] || fail "canale debug non riconosciuto"
if normalize_update_channel invalid >/dev/null 2>&1; then
    fail "un canale aggiornamenti sconosciuto viene accettato"
fi

# Model the curl options used by stable discovery: JSON goes to --output while
# the HTTP status is returned by --write-out.
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
if [[ ${MOCK_CURL_FAIL:-0} == 1 ]]; then
    echo "curl: simulated connection failure" >&2
    exit 7
fi
output=
while (($#)); do
    case $1 in
        --output) output=$2; shift 2 ;;
        --write-out) shift 2 ;;
        *) shift ;;
    esac
done
json=${MOCK_RELEASE_JSON:-}
[[ -n $json ]] || json='{}'
printf '%s\n' "$json" >"${output:?}"
printf '%s' "${MOCK_HTTP_STATUS:-200}"
EOF
chmod +x "$mock_bin/curl"
release_json="$tmp_dir/release.json"
stable_tag=$(PATH="$mock_bin:$PATH" \
    MOCK_RELEASE_JSON='{"draft":false,"prerelease":false,"immutable":true,"tag_name":"v2026.08.20.1"}' \
    discover_stable_release https://example.invalid/latest "$release_json") || \
    fail "una release stable immutabile viene rifiutata"
[[ $stable_tag == v2026.08.20.1 ]] || fail "tag stable inatteso: $stable_tag"
if PATH="$mock_bin:$PATH" \
    MOCK_RELEASE_JSON='{"draft":false,"prerelease":false,"immutable":false,"tag_name":"v2026.08.20.1"}' \
    discover_stable_release https://example.invalid/latest "$release_json" >/dev/null 2>&1; then
    fail "una release GitHub modificabile viene accettata come stable"
fi
set +e
PATH="$mock_bin:$PATH" MOCK_HTTP_STATUS=404 \
    discover_stable_release https://example.invalid/latest "$release_json" \
    >"$tmp_dir/no-release.stdout" 2>"$tmp_dir/no-release.stderr"
no_release_rc=$?
set -e
[[ $no_release_rc == 44 ]] || \
    fail "l'assenza di una release Stable non ha un codice distinto"
grep -Fq 'no published stable release' "$tmp_dir/no-release.stderr" || \
    fail "il 404 Stable non spiega che nessuna release è pubblicata"
set +e
PATH="$mock_bin:$PATH" MOCK_CURL_FAIL=1 \
    discover_stable_release https://example.invalid/latest "$release_json" \
    >"$tmp_dir/stable.stdout" 2>"$tmp_dir/stable.stderr"
stable_failure_rc=$?
set -e
[[ $stable_failure_rc == 7 ]] || \
    fail "il fallimento HTTP stable non conserva il codice curl"
grep -Fq 'Unable to contact the GitHub stable release endpoint' \
    "$tmp_dir/stable.stderr" || \
    fail "il fallimento di rete Stable non è distinto dal 404"
if grep -Eq 'Traceback|JSONDecodeError' "$tmp_dir/stable.stderr"; then
    fail "il fallimento HTTP stable mostra ancora il traceback Python"
fi

if command -v ssh-keygen >/dev/null 2>&1 && git version >/dev/null 2>&1; then
    signed_repo="$tmp_dir/signed-repo"
    signing_key="$tmp_dir/release-key"
    signer_list="$tmp_dir/allowed-signers"
    mkdir -p "$signed_repo"
    git -C "$signed_repo" init -q
    git -C "$signed_repo" config user.name 'Wasalight Test'
    git -C "$signed_repo" config user.email 'release@wasalight.local'
    printf 'signed release\n' >"$signed_repo/content"
    git -C "$signed_repo" add content
    git -C "$signed_repo" commit -qm 'test release'
    ssh-keygen -q -t ed25519 -N '' -f "$signing_key"
    git -C "$signed_repo" -c gpg.format=ssh -c user.signingkey="$signing_key" \
        tag -s -a v2026.08.20.1 -m 'signed test release'
    printf 'release@wasalight.local %s\n' "$(<"$signing_key.pub")" >"$signer_list"
    verify_stable_tag "$signed_repo" v2026.08.20.1 "$signer_list" >/dev/null 2>&1 || \
        fail "un tag SSH firmato da una chiave autorizzata viene rifiutato"
    printf '# no trusted keys\n' >"$signer_list"
    if verify_stable_tag "$signed_repo" v2026.08.20.1 "$signer_list" \
        >/dev/null 2>&1; then
        fail "un tag stable viene accettato senza una chiave autorizzata"
    fi
fi
