#!/usr/bin/env bash
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
        echo "Git non ha risposto (tentativo $attempt/3); nuovo tentativo…" >&2
        sleep "$attempt"
    done
    return "$rc"
}

free_kib() {
    df -Pk "$1" | awk 'NR == 2 {print $4}'
}

update_preflight() {
    local root_free data_free required_command
    for required_command in git timeout dpkg dpkg-deb sha256sum tar; do
        command -v "$required_command" >/dev/null 2>&1 || {
            echo "Comando necessario non disponibile: $required_command" >&2
            return 1
        }
    done
    root_free=$(free_kib /)
    data_free=$(free_kib /data)
    ((root_free >= 262144)) || {
        echo "Spazio insufficiente su /: servono almeno 256 MiB liberi." >&2
        return 1
    }
    ((data_free >= 131072)) || {
        echo "Spazio insufficiente su /data: servono almeno 128 MiB liberi." >&2
        return 1
    }
    if dpkg --audit | grep -q .; then
        echo "dpkg segnala pacchetti incompleti; correggere APT prima dell'update." >&2
        dpkg --audit >&2
        return 1
    fi
    echo "Preflight: spazio / $((root_free / 1024)) MiB · /data $((data_free / 1024)) MiB · dpkg OK"
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
    local baseline destination

    [[ -f $source ]] || return 0
    version=$(magicq_version_of "$source") || {
        echo "Ignoro un file che non è MagicQ amd64 valido: $source" >&2
        return 0
    }

    while IFS= read -r -d '' stored; do
        stored_version=$(magicq_version_of "$stored") || continue
        if dpkg --compare-versions "$version" eq "$stored_version"; then
            if ! cmp -s -- "$source" "$stored"; then
                echo "CONFLITTO: MagicQ $version esiste già con contenuto differente: $stored" >&2
                return 1
            fi
            ((remove_source)) && rm -f -- "$source"
            echo "MagicQ $version è già conservato in $stored"
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
        echo "Ignoro MagicQ $version da $source: è precedente alla versione $baseline"
        ((remove_source)) && rm -f -- "$source"
        return 0
    fi

    destination="$package_store/magicq_${version}_amd64.deb"
    install -o root -g root -m 0640 "$source" "$destination"
    cmp -s -- "$source" "$destination" || {
        echo "Verifica della copia del pacchetto non riuscita: $destination" >&2
        rm -f -- "$destination"
        return 1
    }
    ((remove_source)) && rm -f -- "$source"
    echo "MagicQ $version importato e conservato in $destination"
}

select_newest_magicq_package() {
    local stored version
    selected_package=
    selected_package_version=
    while IFS= read -r -d '' stored; do
        version=$(magicq_version_of "$stored") || {
            echo "Ignoro un pacchetto persistente non valido: $stored" >&2
            continue
        }
        if [[ -z $selected_package ]] || \
           dpkg --compare-versions "$version" gt "$selected_package_version"; then
            selected_package=$stored
            selected_package_version=$version
        elif dpkg --compare-versions "$version" eq "$selected_package_version" && \
             ! cmp -s -- "$stored" "$selected_package"; then
            echo "CONFLITTO: due pacchetti MagicQ $version persistenti hanno contenuto differente." >&2
            return 1
        fi
    done < <(find "$package_store" -maxdepth 1 -type f -name '*.deb' -print0)
}
