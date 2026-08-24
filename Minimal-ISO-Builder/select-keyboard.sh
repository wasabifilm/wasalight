#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Validated configuration backend for install-wizard.py.
set -eu

umask 077
XKB_ROOT=${WASALIGHT_XKB_ROOT:-/usr/share/X11/xkb}
RUNTIME_DIR=${WASALIGHT_RUNTIME_DIR:-/run}
AUTOINSTALL=${WASALIGHT_AUTOINSTALL_PATH:-/autoinstall.yaml}

valid_xkb_token() {
  candidate=$1
  case "$candidate" in ''|*[!A-Za-z0-9_+-]*) return 1 ;; esac
}

valid_xkb_layout() {
  candidate=$1
  valid_xkb_token "$candidate" && [ -r "$XKB_ROOT/symbols/$candidate" ]
}

valid_xkb_variant() {
  candidate_layout=$1
  candidate_variant=$2
  [ -z "$candidate_variant" ] && return 0
  valid_xkb_token "$candidate_variant" || return 1
  awk -v requested="$candidate_variant" '
    /xkb_symbols[[:space:]]+"/ {
      count = split($0, fields, "\"")
      if (count >= 3 && fields[2] == requested) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$XKB_ROOT/symbols/$candidate_layout"
}

valid_xkb_selection() {
  valid_xkb_layout "$1" && valid_xkb_variant "$1" "$2"
}

apply_live_keyboard() {
  command -v ckbcomp >/dev/null 2>&1 || return 1
  command -v loadkeys >/dev/null 2>&1 || return 1
  keymap_file="$RUNTIME_DIR/wasalight-console-keymap"
  if [ -n "$2" ]; then
    ckbcomp -layout "$1" -variant "$2" >"$keymap_file" || return 1
  else
    ckbcomp -layout "$1" >"$keymap_file" || return 1
  fi
  loadkeys "$keymap_file"
}

valid_timezone() {
  candidate=$1
  case "$candidate" in
    ''|/*|*..*|*[!A-Za-z0-9_+./-]*|*/) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  [ -e "/usr/share/zoneinfo/$candidate" ] && [ ! -d "/usr/share/zoneinfo/$candidate" ]
}

valid_interface_language() {
  case "$1" in en|it) return 0 ;; *) return 1 ;; esac
}

valid_label() {
  [ -n "$1" ] && [ "${#1}" -le 80 ] && ! printf '%s' "$1" | grep -q '[|]'
}

escape_sed() { printf '%s' "$1" | sed 's/[\/&]/\\&/g'; }

apply_config() {
  config=$1
  [ -r "$config" ] || { echo "ERROR: wizard configuration is unavailable." >&2; return 1; }
  [ "$(wc -l <"$config" | tr -d ' ')" -eq 7 ] || {
    echo "ERROR: wizard configuration has an invalid format." >&2
    return 1
  }
  interface_language=$(sed -n '1p' "$config")
  interface_language_label=$(sed -n '2p' "$config")
  layout=$(sed -n '3p' "$config")
  variant=$(sed -n '4p' "$config")
  keyboard_label=$(sed -n '5p' "$config")
  timezone=$(sed -n '6p' "$config")
  password_hash=$(sed -n '7p' "$config")

  valid_interface_language "$interface_language" || {
    echo "ERROR: unsupported Wasalight interface language." >&2; return 1;
  }
  valid_label "$interface_language_label" || {
    echo "ERROR: invalid interface language label." >&2; return 1;
  }
  valid_xkb_selection "$layout" "$variant" || {
    echo "ERROR: invalid or unavailable XKB layout/variant." >&2; return 1;
  }
  valid_label "$keyboard_label" || {
    echo "ERROR: invalid keyboard label." >&2; return 1;
  }
  valid_timezone "$timezone" || {
    echo "ERROR: invalid or unavailable time zone." >&2; return 1;
  }
  case "$password_hash" in
    \$6\$*\$*) ;;
    *) echo "ERROR: invalid SHA-512 password hash." >&2; return 1 ;;
  esac

  [ -f "$AUTOINSTALL" ] || { echo "ERROR: autoinstall.yaml was not found." >&2; return 1; }
  for placeholder in __WASALIGHT_KEYBOARD_LAYOUT__ __WASALIGHT_KEYBOARD_VARIANT__ \
    __WASALIGHT_TIMEZONE__ __WASALIGHT_PASSWORD_HASH__
  do
    grep -Fq "$placeholder" "$AUTOINSTALL" || {
      echo "ERROR: $placeholder was not found in autoinstall.yaml." >&2
      return 1
    }
  done

  escaped_layout=$(escape_sed "$layout")
  escaped_variant=$(escape_sed "$variant")
  escaped_timezone=$(escape_sed "$timezone")
  escaped_password_hash=$(escape_sed "$password_hash")
  temporary="$RUNTIME_DIR/autoinstall.keyboard.yaml"
  sed -e "s/__WASALIGHT_KEYBOARD_LAYOUT__/$escaped_layout/g" \
      -e "s/__WASALIGHT_KEYBOARD_VARIANT__/$escaped_variant/g" \
      -e "s/__WASALIGHT_TIMEZONE__/$escaped_timezone/g" \
      -e "s/__WASALIGHT_PASSWORD_HASH__/$escaped_password_hash/g" \
      "$AUTOINSTALL" >"$temporary"
  cat "$temporary" >"$AUTOINSTALL"

  printf '%s\n' "$keyboard_label" >"$RUNTIME_DIR/wasalight-keyboard-label"
  printf '%s\n' "$interface_language" >"$RUNTIME_DIR/wasalight-interface-language"
  printf '%s\n' "$interface_language_label" >"$RUNTIME_DIR/wasalight-interface-language-label"
  printf '%s\n' "$timezone" >"$RUNTIME_DIR/wasalight-timezone-label"
  printf '%s\n' configured >"$RUNTIME_DIR/wasalight-password-status"
}

case "${1:-}" in
  --validate-timezone)
    [ "$#" -eq 2 ] || exit 2
    valid_timezone "$2"
    ;;
  --validate-layout)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
    valid_xkb_selection "$2" "${3:-}"
    ;;
  --validate-language)
    [ "$#" -eq 2 ] || exit 2
    valid_interface_language "$2"
    ;;
  --apply-live-keyboard)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
    valid_xkb_selection "$2" "${3:-}" && apply_live_keyboard "$2" "${3:-}"
    ;;
  --apply-config)
    [ "$#" -eq 2 ] || exit 2
    apply_config "$2"
    ;;
  *)
    echo "ERROR: expected a validated backend operation." >&2
    exit 2
    ;;
esac
