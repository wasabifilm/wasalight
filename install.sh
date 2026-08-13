#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Project entry point. It automatically uses the single local or persistent .deb.

set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$PROJECT_DIR/bin/chamsys_install_ubuntu.sh"
. "$PROJECT_DIR/lib/wasalight-release-manifest.sh"
RELEASE_MANIFEST="$PROJECT_DIR/release-manifest.ini"
MAGICQ_PACKAGE_NAME=$(require_manifest_value "$RELEASE_MANIFEST" MagicQ Package)
MAGICQ_ARCHITECTURE=$(require_manifest_value "$RELEASE_MANIFEST" MagicQ Architecture)
args=("$@")
deb_supplied=0

magicq_version_of() {
    local package=$1 version
    dpkg-deb --info "$package" >/dev/null 2>&1 || return 1
    [[ $(dpkg-deb -f "$package" Package 2>/dev/null) == "$MAGICQ_PACKAGE_NAME" ]] || return 1
    [[ $(dpkg-deb -f "$package" Architecture 2>/dev/null) == "$MAGICQ_ARCHITECTURE" ]] || return 1
    version=$(dpkg-deb -f "$package" Version 2>/dev/null) || return 1
    dpkg --validate-version "$version" >/dev/null 2>&1 || return 1
    printf '%s\n' "$version"
}

allow_missing_magicq=0
for arg in "$@"; do
    if [[ "$arg" == -h || "$arg" == -help || "$arg" == --help || "$arg" == --version ]]; then
        exec "$INSTALLER" "$@"
    fi
    [[ "$arg" == --allow-missing-magicq ]] && allow_missing_magicq=1
    [[ "$arg" == *.deb ]] && deb_supplied=1
done

# shellcheck source=lib/wasalight-operation-lock.sh
. "$PROJECT_DIR/lib/wasalight-operation-lock.sh"
[[ $EUID -eq 0 ]] || { echo "Esegui l'installer con sudo." >&2; exit 1; }
wasalight_acquire_operation_lock "installazione Wasalight"

if ((deb_supplied == 0)); then
    shopt -s nullglob
    packages=("$PROJECT_DIR"/packages/*.deb /data/system/packages/*.deb)
    shopt -u nullglob

    # A mounted USB may contain the installer either in its root or in the
    # conventional packages/ directory. Ignore stale directories below /stick:
    # only targets currently reported by findmnt are scanned.
    while IFS= read -r usb_mount; do
        while IFS= read -r -d '' usb_package; do
            packages+=("$usb_package")
        done < <(find "$usb_mount" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)
        if [[ -d $usb_mount/packages ]]; then
            while IFS= read -r -d '' usb_package; do
                packages+=("$usb_package")
            done < <(find "$usb_mount/packages" -maxdepth 1 -type f -name '*.deb' -print0 2>/dev/null)
        fi
        # libfsapfs exposes every APFS volume as fsapfs1, fsapfs2, ... below
        # the FUSE mount. Search those volume roots without scanning recursively.
        while IFS= read -r -d '' apfs_volume; do
            while IFS= read -r -d '' usb_package; do
                packages+=("$usb_package")
            done < <(find "$apfs_volume" -maxdepth 1 -type f -iname '*.deb' -print0 2>/dev/null)
            if [[ -d $apfs_volume/packages ]]; then
                while IFS= read -r -d '' usb_package; do
                    packages+=("$usb_package")
                done < <(find "$apfs_volume/packages" -maxdepth 1 -type f -iname '*.deb' -print0 2>/dev/null)
            fi
        done < <(find "$usb_mount" -mindepth 1 -maxdepth 1 -type d \
            -name 'fsapfs[0-9]*' -print0 2>/dev/null)
    done < <(findmnt -rn -o TARGET 2>/dev/null | awk '$0 ~ "^/stick/[^/]+$"')

    selected_package=
    selected_version=
    for package in "${packages[@]}"; do
        version=$(magicq_version_of "$package") || {
            printf 'Ignoro un file che non è MagicQ amd64 valido: %s\n' "$package" >&2
            continue
        }
        if [[ -z $selected_package ]] || dpkg --compare-versions "$version" gt "$selected_version"; then
            selected_package=$package
            selected_version=$version
        elif dpkg --compare-versions "$version" eq "$selected_version" && \
             ! cmp -s -- "$package" "$selected_package"; then
            printf 'Conflitto: due pacchetti MagicQ %s hanno contenuto differente.\n' \
                "$version" >&2
            exit 2
        fi
    done

    if [[ -n $selected_package ]]; then
        printf 'Pacchetto MagicQ selezionato: %s (versione %s)\n' \
            "$selected_package" "$selected_version"
        args+=("$selected_package")
    else
        printf 'Pacchetto MagicQ non trovato nel progetto, in /data o nelle USB montate.\n' >&2
        if dpkg-query -W -f='${db:Status-Abbrev}' magicq 2>/dev/null | grep -q '^ii'; then
            printf 'MagicQ è già installato: continuo senza reinstallare il pacchetto.\n' >&2
        elif ((allow_missing_magicq == 0)); then
            printf 'Avvio la ricerca iniziale anche nelle USB non ancora montate.\n' >&2
            printf 'Se non verrà trovato nulla, lo script indicherà --allow-missing-magicq.\n' >&2
        else
            printf 'Assenza di MagicQ ignorata esplicitamente.\n' >&2
        fi
    fi
fi

exec "$INSTALLER" "${args[@]}"
