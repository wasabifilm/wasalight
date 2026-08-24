#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -eu

umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION_FILE=$SCRIPT_DIR/VERSION
[ -r "$VERSION_FILE" ] || {
  echo "ERROR: VERSION is unavailable."
  exit 1
}
INSTALLER_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
case "$INSTALLER_VERSION" in
  ''|*[!0-9]*) echo "ERROR: invalid VERSION."; exit 1 ;;
esac

XKB_ROOT=${WASALIGHT_XKB_ROOT:-/usr/share/X11/xkb}

valid_xkb_token() {
  candidate=$1
  case "$candidate" in
    ''|*[!A-Za-z0-9_+-]*) return 1 ;;
  esac
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

  keymap_file=/run/wasalight-console-keymap
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
  [ -e "/usr/share/zoneinfo/$candidate" ] && \
    [ ! -d "/usr/share/zoneinfo/$candidate" ]
}

valid_interface_language() {
  case "$1" in
    en|it) return 0 ;;
    *) return 1 ;;
  esac
}

case "${1:-}" in
  '') ;;
  --validate-timezone)
    [ "$#" -eq 2 ] || exit 2
    valid_timezone "$2"
    exit $?
    ;;
  --validate-layout)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || exit 2
    valid_xkb_selection "$2" "${3:-}"
    exit $?
    ;;
  --validate-language)
    [ "$#" -eq 2 ] || exit 2
    valid_interface_language "$2"
    exit $?
    ;;
  *)
    echo "ERROR: unknown option: $1" >&2
    exit 2
    ;;
esac

TTY=/dev/tty1
[ -c "$TTY" ] || TTY=/dev/console
exec <"$TTY" >"$TTY" 2>&1

clear_screen() { printf '\033[2J\033[H'; }
green() { printf '\033[1;32m%s\033[0m\n' "$1"; }

echo_disabled=0
restore_tty() {
  if [ "$echo_disabled" -eq 1 ]; then
    stty echo 2>/dev/null || true
    echo_disabled=0
  fi
}
trap restore_tty EXIT HUP INT TERM

pause_error() {
  printf '\n%s\n' "$1"
  printf 'Press ENTER to try again... '
  IFS= read -r _dummy
}

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Select the Wasalight interface language:"
  echo
  echo "   1) Italiano"
  echo "   2) English"
  echo
  echo "This does not change the keyboard layout."
  echo
  printf "Selection [1]: "
  IFS= read -r language_choice

  case "$language_choice" in
    ''|1)
      interface_language="it"
      interface_language_label="Italiano"
      ;;
    2)
      interface_language="en"
      interface_language_label="English"
      ;;
    *)
      pause_error "Invalid selection."
      continue
      ;;
  esac
  break
done

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "The installer language is English. The keyboard layout is independent"
  echo "from the Wasalight interface language selected on the previous screen."
  echo
  echo "Select the keyboard layout:"
  echo
  echo "   1) Italian"
  echo "   2) English (US)"
  echo "   3) English (UK)"
  echo "   4) Deutsch"
  echo "   5) Francais"
  echo "   6) Espanol"
  echo "   7) Swiss German"
  echo "   8) Swiss French"
  echo "   9) Other XKB layout"
  echo
  printf "Selection: "
  IFS= read -r choice

  case "$choice" in
    1)
      layout="it"
      variant=""
      label="Italian"
      ;;
    2)
      layout="us"
      variant=""
      label="English (US)"
      ;;
    3)
      layout="gb"
      variant=""
      label="English (UK)"
      ;;
    4)
      layout="de"
      variant=""
      label="Deutsch"
      ;;
    5)
      layout="fr"
      variant=""
      label="Francais"
      ;;
    6)
      layout="es"
      variant=""
      label="Espanol"
      ;;
    7)
      layout="ch"
      variant="de"
      label="Swiss German"
      ;;
    8)
      layout="ch"
      variant="fr"
      label="Swiss French"
      ;;
    9)
      echo
      printf "XKB layout code (for example pl, pt or no): "
      IFS= read -r layout
      printf "XKB variant (leave empty for the default): "
      IFS= read -r variant
      if ! valid_xkb_selection "$layout" "$variant"; then
        pause_error "Invalid or unavailable XKB layout/variant: $layout ${variant:-default}"
        continue
      fi
      label="$layout"
      [ -z "$variant" ] || label="$layout ($variant)"
      ;;
    *)
      pause_error "Invalid selection."
      continue
      ;;
  esac

  if ! apply_live_keyboard "$layout" "$variant"; then
    pause_error "Unable to apply this keyboard layout to the live console."
    continue
  fi

  clear_screen
  echo "=============================================================="
  echo "                   TEST KEYBOARD"
  echo "=============================================================="
  echo
  echo "Layout: $label"
  echo
  echo "Type a short test, including symbols such as @, /, - or _, then press ENTER."
  printf "> "
  IFS= read -r keyboard_test
  echo
  printf 'You typed: %s\n' "$keyboard_test"
  echo
  printf "Is the keyboard correct? [Y/n]: "
  IFS= read -r confirm
  keyboard_test=""

  case "$confirm" in
    ""|y|Y|yes|YES|Yes)
      break
      ;;
    *)
      continue
      ;;
  esac
done

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Select the time zone:"
  echo
  echo "   1) Italy           (Europe/Rome)"
  echo "   2) Switzerland     (Europe/Zurich)"
  echo "   3) United Kingdom  (Europe/London)"
  echo "   4) Germany         (Europe/Berlin)"
  echo "   5) France          (Europe/Paris)"
  echo "   6) Spain           (Europe/Madrid)"
  echo "   7) UTC             (Etc/UTC)"
  echo "   8) Other IANA zone (for example America/New_York)"
  echo
  printf "Selection [1]: "
  IFS= read -r timezone_choice

  case "$timezone_choice" in
    ''|1) timezone="Europe/Rome" ;;
    2) timezone="Europe/Zurich" ;;
    3) timezone="Europe/London" ;;
    4) timezone="Europe/Berlin" ;;
    5) timezone="Europe/Paris" ;;
    6) timezone="Europe/Madrid" ;;
    7) timezone="Etc/UTC" ;;
    8)
      echo
      printf "IANA time zone: "
      IFS= read -r timezone
      ;;
    *)
      pause_error "Invalid selection."
      continue
      ;;
  esac

  if ! valid_timezone "$timezone"; then
    pause_error "Invalid or unavailable time zone: $timezone"
    continue
  fi

  clear_screen
  echo "=============================================================="
  echo "                 CONFIRM TIME ZONE"
  echo "=============================================================="
  echo
  echo "Time zone: $timezone"
  echo
  printf "Confirm? [Y/n]: "
  IFS= read -r confirm

  case "$confirm" in
    ""|y|Y|yes|YES|Yes) break ;;
    *) continue ;;
  esac
done

command -v openssl >/dev/null 2>&1 || {
  echo
  echo "ERROR: openssl is unavailable in the installation environment."
  echo "Press ENTER to open a shell."
  read _dummy
  exec sh
}

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Set the password for the chamsys administrator account."
  echo
  echo "The password must contain at least 6 characters."
  echo "It will not be displayed while you type."
  echo

  printf "Password: "
  echo_disabled=1
  stty -echo
  IFS= read -r password
  stty echo
  echo_disabled=0
  echo

  if [ "${#password}" -lt 6 ]; then
    password=""
    pause_error "The password is too short."
    continue
  fi

  printf "Repeat password: "
  echo_disabled=1
  stty -echo
  IFS= read -r password_confirm
  stty echo
  echo_disabled=0
  echo

  if [ "$password" != "$password_confirm" ]; then
    password=""
    password_confirm=""
    pause_error "The passwords do not match."
    continue
  fi

  password_hash=$(printf '%s\n' "$password" | openssl passwd -6 -stdin) || {
    password=""
    password_confirm=""
    pause_error "Unable to generate the password hash."
    continue
  }
  password=""
  password_confirm=""
  break
done

[ -f /autoinstall.yaml ] || {
  echo
  echo "ERROR: /autoinstall.yaml was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_KEYBOARD_LAYOUT__' /autoinstall.yaml || {
  echo
  echo "ERROR: keyboard layout placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_KEYBOARD_VARIANT__' /autoinstall.yaml || {
  echo
  echo "ERROR: keyboard variant placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_TIMEZONE__' /autoinstall.yaml || {
  echo
  echo "ERROR: time zone placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_PASSWORD_HASH__' /autoinstall.yaml || {
  echo
  echo "ERROR: password placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

escaped_layout=$(printf '%s' "$layout" | sed 's/[\/&]/\\&/g')
escaped_variant=$(printf '%s' "$variant" | sed 's/[\/&]/\\&/g')
escaped_timezone=$(printf '%s' "$timezone" | sed 's/[\/&]/\\&/g')
escaped_password_hash=$(printf '%s' "$password_hash" | sed 's/[\/&]/\\&/g')

sed \
  -e "s/__WASALIGHT_KEYBOARD_LAYOUT__/$escaped_layout/g" \
  -e "s/__WASALIGHT_KEYBOARD_VARIANT__/$escaped_variant/g" \
  -e "s/__WASALIGHT_TIMEZONE__/$escaped_timezone/g" \
  -e "s/__WASALIGHT_PASSWORD_HASH__/$escaped_password_hash/g" \
  /autoinstall.yaml > /run/autoinstall.keyboard.yaml

cat /run/autoinstall.keyboard.yaml > /autoinstall.yaml

printf '%s\n' "$label" > /run/wasalight-keyboard-label
printf '%s\n' "$interface_language" > /run/wasalight-interface-language
printf '%s\n' "$interface_language_label" > /run/wasalight-interface-language-label
printf '%s\n' "$timezone" > /run/wasalight-timezone-label
printf '%s\n' "configured" > /run/wasalight-password-status
password_hash=""
escaped_password_hash=""

clear_screen
echo "Selected interface language: $interface_language_label"
echo "Selected keyboard: $label"
echo "Selected time zone: $timezone"
echo "The chamsys password is configured."
echo
echo "Installation will continue automatically..."
sleep 2
