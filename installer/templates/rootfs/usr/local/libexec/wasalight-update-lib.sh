#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Shared, side-effect-free helpers for the Wasalight updater orchestrator.

git_retry() {
    local attempt rc=1
    for attempt in 1 2 3; do
        if timeout --signal=TERM 120 env GIT_TERMINAL_PROMPT=0 \
            git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 "$@"; then
            return 0
        else
            rc=$?
        fi
        ((attempt == 3)) && break
        echo "Git did not respond (attempt $attempt/3); retrying…" >&2
        sleep "$attempt"
    done
    return "$rc"
}

atomic_text_write() {
    local destination=$1 content=$2 owner=${3:-root:root} mode=${4:-0640}
    local directory temporary
    directory=${destination%/*}
    [[ $directory != "$destination" ]] || directory=.
    install -d -m 0755 "$directory"
    temporary=$(mktemp "$directory/.wasalight-write.XXXXXX")
    printf '%s' "$content" >"$temporary"
    chown "$owner" "$temporary"
    chmod "$mode" "$temporary"
    mv -f -- "$temporary" "$destination"
}

update_state_value() {
    local state_path=$1 key=$2
    [[ -r $state_path ]] || return 1
    awk -F= -v wanted="$key" '
        $1 == wanted { print substr($0, index($0, "=") + 1); found=1; exit }
        END { if (!found) exit 1 }
    ' "$state_path"
}

update_state_write() {
    local state_path=$1 status=$2 phase=$3 version=$4 commit=$5
    local snapshot=$6 started=$7 channel=$8 candidate=$9
    local value
    for value in "$status" "$phase" "$version" "$commit" "$snapshot" \
                 "$started" "$channel" "$candidate"; do
        [[ $value != *$'\n'* && $value != *$'\r'* ]] || {
            echo "Invalid newline in update transaction state." >&2
            return 1
        }
    done
    atomic_text_write "$state_path" \
        "status=$status
phase=$phase
version=$version
commit=$commit
snapshot=$snapshot
started=$started
channel=$channel
candidate=$candidate
" "${WASALIGHT_UPDATE_STATE_OWNER:-root:chamsys}" 0640
}

normalize_update_channel() {
    local normalized
    normalized=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case $normalized in
        stable|normal|normale) printf '%s\n' stable ;;
        debug|development|sviluppo) printf '%s\n' debug ;;
        *) echo "Invalid update channel: $1 (use stable or debug)" >&2; return 2 ;;
    esac
}

discover_stable_release() {
    local api_url=$1 output_json=$2
    curl --fail --silent --show-error --location \
        --connect-timeout 5 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$api_url" >"$output_json"
    python3 - "$output_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    release = json.load(source)
if release.get("draft") or release.get("prerelease"):
    raise SystemExit("GitHub latest release is not stable")
if release.get("immutable") is not True:
    raise SystemExit("GitHub stable release is not immutable")
tag = release.get("tag_name", "")
if not isinstance(tag, str) or not tag:
    raise SystemExit("GitHub stable release has no tag")
print(tag)
PY
}

verify_stable_tag() {
    local repository_dir=$1 tag=$2 signer_file=$3
    [[ -r $signer_file ]] && grep -Eq '^[^#[:space:]].*[[:space:]]ssh-(ed25519|rsa)[[:space:]]' "$signer_file" || {
        echo "Release public key is missing: $signer_file" >&2
        return 1
    }
    git -C "$repository_dir" \
        -c gpg.format=ssh \
        -c gpg.ssh.allowedSignersFile="$signer_file" \
        verify-tag "$tag"
}

free_kib() {
    df -Pk "$1" | awk 'NR == 2 {print $4}'
}

update_preflight() {
    local root_free data_free required_command
    for required_command in curl git python3 ssh-keygen timeout dpkg dpkg-deb sha256sum tar; do
        command -v "$required_command" >/dev/null 2>&1 || {
            echo "Required command is unavailable: $required_command" >&2
            return 1
        }
    done
    root_free=$(free_kib /)
    data_free=$(free_kib /data)
    ((root_free >= 262144)) || {
        echo "Insufficient space on /: at least 256 MiB must be free." >&2
        return 1
    }
    ((data_free >= 131072)) || {
        echo "Insufficient space on /data: at least 128 MiB must be free." >&2
        return 1
    }
    if dpkg --audit | grep -q .; then
        echo "dpkg reports incomplete packages; repair APT before updating." >&2
        dpkg --audit >&2
        return 1
    fi
    echo "Preflight: / free $((root_free / 1024)) MiB · /data free $((data_free / 1024)) MiB · dpkg OK"
}

magicq_version_of() {
    local source=$1 version
    dpkg-deb --info "$source" >/dev/null 2>&1 || return 1
    [[ $(dpkg-deb -f "$source" Package 2>/dev/null) == "$magicq_package" ]] || return 1
    [[ $(dpkg-deb -f "$source" Architecture 2>/dev/null) == "$magicq_architecture" ]] || return 1
    version=$(dpkg-deb -f "$source" Version 2>/dev/null) || return 1
    dpkg --validate-version "$version" >/dev/null 2>&1 || return 1
    printf '%s\n' "$version"
}

newest_stored_version() {
    local stored version newest=
    [[ -d $package_store ]] || { printf '\n'; return 0; }
    while IFS= read -r -d '' stored; do
        version=$(magicq_version_of "$stored") || continue
        if [[ -z $newest ]] || dpkg --compare-versions "$version" gt "$newest"; then
            newest=$version
        fi
    done < <(find "$package_store" -maxdepth 1 -type f -name '*.deb' -print0)
    printf '%s\n' "$newest"
}

import_magicq_package() {
    local source=$1 remove_source=${2:-0}
    local version installed_record installed_magicq_version= stored stored_version
    local baseline destination temporary

    [[ -f $source ]] || return 0
    version=$(magicq_version_of "$source") || {
        echo "Ignoring a file that is not a valid MagicQ amd64 package: $source" >&2
        return 0
    }

    while IFS= read -r -d '' stored; do
        stored_version=$(magicq_version_of "$stored") || continue
        if dpkg --compare-versions "$version" eq "$stored_version"; then
            if ! cmp -s -- "$source" "$stored"; then
                echo "CONFLICT: MagicQ $version already exists with different content: $stored" >&2
                return 1
            fi
            ((remove_source)) && rm -f -- "$source"
            echo "MagicQ $version is already stored in $stored"
            return 0
        fi
    done < <(find "$package_store" -maxdepth 1 -type f -name '*.deb' -print0)

    baseline=$(newest_stored_version)
    installed_record=$(dpkg-query -W -f='${db:Status-Abbrev}\t${Version}' magicq \
        2>/dev/null || true)
    [[ $installed_record == ii*$'\t'* ]] && \
        installed_magicq_version=${installed_record#*$'\t'}
    if [[ -n $installed_magicq_version ]] && \
       { [[ -z $baseline ]] || dpkg --compare-versions "$installed_magicq_version" gt "$baseline"; }; then
        baseline=$installed_magicq_version
    fi
    if [[ -n $baseline ]] && dpkg --compare-versions "$version" lt "$baseline"; then
        echo "Ignoring MagicQ $version from $source: it is older than version $baseline"
        ((remove_source)) && rm -f -- "$source"
        return 0
    fi

    destination="$package_store/magicq_${version}_amd64.deb"
    temporary=$(mktemp "$package_store/.magicq-import.XXXXXX")
    install -o root -g root -m 0640 "$source" "$temporary"
    cmp -s -- "$source" "$temporary" || {
        echo "Package copy verification failed: $destination" >&2
        rm -f -- "$temporary"
        return 1
    }
    mv -f -- "$temporary" "$destination"
    ((remove_source)) && rm -f -- "$source"
    echo "MagicQ $version imported and stored in $destination"
}

select_newest_magicq_package() {
    local stored version
    selected_package=
    selected_package_version=
    [[ -d $package_store ]] || return 0
    while IFS= read -r -d '' stored; do
        version=$(magicq_version_of "$stored") || {
            echo "Ignoring an invalid persistent package: $stored" >&2
            continue
        }
        if [[ -z $selected_package ]] || \
           dpkg --compare-versions "$version" gt "$selected_package_version"; then
            selected_package=$stored
            selected_package_version=$version
        elif dpkg --compare-versions "$version" eq "$selected_package_version" && \
             ! cmp -s -- "$stored" "$selected_package"; then
            echo "CONFLICT: two persistent MagicQ $version packages have different content." >&2
            return 1
        fi
    done < <(find "$package_store" -maxdepth 1 -type f -name '*.deb' -print0)
}
