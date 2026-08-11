#!/usr/bin/env bash
# Strict reader for Wasalight's declarative release manifest.

manifest_value() {
    local manifest=$1 section=$2 key=$3
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
    ' "$manifest"
}

require_manifest_value() {
    local manifest=$1 section=$2 key=$3 value
    value=$(manifest_value "$manifest" "$section" "$key") || {
        printf 'Missing release manifest value: [%s] %s\n' "$section" "$key" >&2
        return 1
    }
    [[ -n $value ]] || {
        printf 'Empty release manifest value: [%s] %s\n' "$section" "$key" >&2
        return 1
    }
    printf '%s\n' "$value"
}
