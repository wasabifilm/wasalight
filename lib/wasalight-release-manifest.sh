#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Strict reader for Wasalight's declarative release manifest.

manifest_value() {
    local manifest_path=$1 section=$2 key=$3
    awk -F= -v wanted_section="$section" -v wanted_key="$key" '
        /^[[:space:]]*\[/ {
            current=$0
            sub(/^[[:space:]]*\[/, "", current)
            sub(/\][[:space:]]*$/, "", current)
            next
        }
        current == wanted_section && $1 == wanted_key {
            value=substr($0, index($0, "=") + 1)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print value
            found=1
            exit
        }
        END { if (!found) exit 1 }
    ' "$manifest_path"
}

require_manifest_value() {
    local manifest_path=$1 section=$2 key=$3 value
    value=$(manifest_value "$manifest_path" "$section" "$key") || {
        printf 'Missing release manifest value: [%s] %s\n' "$section" "$key" >&2
        return 1
    }
    [[ -n $value ]] || {
        printf 'Empty release manifest value: [%s] %s\n' "$section" "$key" >&2
        return 1
    }
    printf '%s\n' "$value"
}

require_manifest_value_matching() {
    local manifest_path=$1 section=$2 key=$3 pattern=$4 description=$5 value
    value=$(require_manifest_value "$manifest_path" "$section" "$key") || return 1
    [[ $value =~ $pattern ]] || {
        printf 'Invalid release manifest value: [%s] %s must be %s (got: %s)\n' \
            "$section" "$key" "$description" "$value" >&2
        return 1
    }
    printf '%s\n' "$value"
}

require_manifest_positive_integer() {
    local manifest_path=$1 section=$2 key=$3 value
    value=$(require_manifest_value_matching \
        "$manifest_path" "$section" "$key" '^[1-9][0-9]*$' 'a positive integer') || return 1
    printf '%s\n' "$value"
}
