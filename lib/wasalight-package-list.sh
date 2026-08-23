#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Validate and render the shared Wasalight runtime package list.

wasalight_runtime_packages() {
    local package_file=$1 package line_number=0 seen=$'\n' count=0 packages_output=

    [[ -r $package_file ]] || {
        printf 'ERROR: runtime package list not readable: %s\n' "$package_file" >&2
        return 1
    }

    while IFS= read -r package || [[ -n $package ]]; do
        line_number=$((line_number + 1))
        [[ -z $package || $package == \#* ]] && continue
        if [[ ! $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
            printf 'ERROR: invalid package at %s:%d: %s\n' \
                "$package_file" "$line_number" "$package" >&2
            return 1
        fi
        if [[ $seen == *$'\n'"$package"$'\n'* ]]; then
            printf 'ERROR: duplicate package at %s:%d: %s\n' \
                "$package_file" "$line_number" "$package" >&2
            return 1
        fi
        seen+="$package"$'\n'
        count=$((count + 1))
        packages_output+="$package"$'\n'
    done <"$package_file"

    ((count > 0)) || {
        printf 'ERROR: runtime package list is empty: %s\n' "$package_file" >&2
        return 1
    }
    printf '%s' "$packages_output"
}

wasalight_runtime_packages_yaml() {
    local package_file=$1 package separator= packages_yaml='['

    while IFS= read -r package; do
        packages_yaml+="$separator$package"
        separator=', '
    done < <(wasalight_runtime_packages "$package_file") || return 1
    [[ $packages_yaml != '[' ]] || return 1
    printf '%s]\n' "$packages_yaml"
}
