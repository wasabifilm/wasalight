#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -eu

umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION_FILE=$SCRIPT_DIR/VERSION
[ -r "$VERSION_FILE" ] || {
  echo "ERRORE: VERSION non disponibile."
  exit 1
}
INSTALLER_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
case "$INSTALLER_VERSION" in
  ''|*[!0-9]*) echo "ERRORE: VERSION non valida."; exit 1 ;;
esac

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

case "${1:-}" in
  '') ;;
  --validate-timezone)
    [ "$#" -eq 2 ] || exit 2
    valid_timezone "$2"
    exit $?
    ;;
  *)
    echo "ERRORE: opzione sconosciuta: $1" >&2
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
  printf 'Premi INVIO per riprovare... '
  IFS= read -r _dummy
}

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Seleziona il layout della tastiera:"
  echo
  echo "   1) Italiano"
  echo "   2) English (US)"
  echo "   3) English (UK)"
  echo "   4) Deutsch"
  echo "   5) Francais"
  echo "   6) Espanol"
  echo "   7) Swiss German"
  echo "   8) Swiss French"
  echo
  printf "Scelta: "
  IFS= read -r choice

  case "$choice" in
    1)
      layout="it"
      variant=""
      label="Italiano"
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
    *)
      pause_error "Scelta non valida."
      continue
      ;;
  esac

  clear_screen
  echo "=============================================================="
  echo "                CONFERMA TASTIERA"
  echo "=============================================================="
  echo
  echo "Layout: $label"
  echo
  printf "Confermare? [S/n]: "
  IFS= read -r confirm

  case "$confirm" in
    ""|s|S|si|SI|Si|sI)
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
  echo "Seleziona il fuso orario:"
  echo
  echo "   1) Italia          (Europe/Rome)"
  echo "   2) Svizzera        (Europe/Zurich)"
  echo "   3) Regno Unito     (Europe/London)"
  echo "   4) Germania        (Europe/Berlin)"
  echo "   5) Francia         (Europe/Paris)"
  echo "   6) Spagna          (Europe/Madrid)"
  echo "   7) UTC             (Etc/UTC)"
  echo "   8) Altro fuso IANA (es. America/New_York)"
  echo
  printf "Scelta [1]: "
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
      printf "Fuso orario IANA: "
      IFS= read -r timezone
      ;;
    *)
      pause_error "Scelta non valida."
      continue
      ;;
  esac

  if ! valid_timezone "$timezone"; then
    pause_error "Fuso orario non valido o non disponibile: $timezone"
    continue
  fi

  clear_screen
  echo "=============================================================="
  echo "                CONFERMA FUSO ORARIO"
  echo "=============================================================="
  echo
  echo "Fuso orario: $timezone"
  echo
  printf "Confermare? [S/n]: "
  IFS= read -r confirm

  case "$confirm" in
    ""|s|S|si|SI|Si|sI) break ;;
    *) continue ;;
  esac
done

command -v openssl >/dev/null 2>&1 || {
  echo
  echo "ERRORE: openssl non disponibile nell'ambiente di installazione."
  echo "Premi INVIO per aprire una shell."
  read _dummy
  exec sh
}

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Configura la password dell'utente amministratore chamsys."
  echo
  echo "La password deve contenere almeno 10 caratteri."
  echo "Non verra' mostrata mentre la digiti."
  echo

  printf "Password: "
  echo_disabled=1
  stty -echo
  IFS= read -r password
  stty echo
  echo_disabled=0
  echo

  if [ "${#password}" -lt 10 ]; then
    password=""
    pause_error "Password troppo corta."
    continue
  fi

  printf "Ripeti password: "
  echo_disabled=1
  stty -echo
  IFS= read -r password_confirm
  stty echo
  echo_disabled=0
  echo

  if [ "$password" != "$password_confirm" ]; then
    password=""
    password_confirm=""
    pause_error "Le password non coincidono."
    continue
  fi

  password_hash=$(printf '%s\n' "$password" | openssl passwd -6 -stdin) || {
    password=""
    password_confirm=""
    pause_error "Impossibile generare l'hash della password."
    continue
  }
  password=""
  password_confirm=""
  break
done

[ -f /autoinstall.yaml ] || {
  echo
  echo "ERRORE: /autoinstall.yaml non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_KEYBOARD_LAYOUT__' /autoinstall.yaml || {
  echo
  echo "ERRORE: placeholder layout tastiera non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_KEYBOARD_VARIANT__' /autoinstall.yaml || {
  echo
  echo "ERRORE: placeholder variante tastiera non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_TIMEZONE__' /autoinstall.yaml || {
  echo
  echo "ERRORE: placeholder fuso orario non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_PASSWORD_HASH__' /autoinstall.yaml || {
  echo
  echo "ERRORE: placeholder password non trovato."
  echo "Premi INVIO per aprire una shell."
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
printf '%s\n' "$timezone" > /run/wasalight-timezone-label
printf '%s\n' "configurata" > /run/wasalight-password-status
password_hash=""
escaped_password_hash=""

clear_screen
echo "Tastiera selezionata: $label"
echo "Fuso orario selezionato: $timezone"
echo "Password chamsys configurata."
echo
echo "L'installazione proseguira' automaticamente..."
sleep 2
