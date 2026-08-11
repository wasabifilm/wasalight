#!/bin/sh
set -eu

umask 077

TTY=/dev/tty1
[ -c "$TTY" ] || TTY=/dev/console
exec <"$TTY" >"$TTY" 2>&1

DISK_LIST=/run/wasalight-disks.txt
DEVICE_LIST=/run/wasalight-device-names.txt
MINIMUM_BYTES=$((16 * 1024 * 1024 * 1024))
INSTALLER_VERSION=24

clear_screen() { printf '\033[2J\033[H'; }
green() { printf '\033[1;32m%s\033[0m\n' "$1"; }

pause_error() {
  printf '\n%s\n' "$1"
  printf 'Premi INVIO per riprovare... '
  IFS= read -r _dummy
}

clean_field() {
  printf '%s' "$1" | tr '\n|' '  '
}

installation_disks() {
  {
    findmnt -n -o SOURCE -M /cdrom 2>/dev/null || true
    findmnt -n -o SOURCE -M /isodevice 2>/dev/null || true
    blkid -L ISOIMAGE 2>/dev/null || true
  } | while IFS= read -r source; do
    [ -n "$source" ] || continue
    source=$(readlink -f -- "$source" 2>/dev/null || printf '%s' "$source")
    parent=$(lsblk -dnro PKNAME -- "$source" 2>/dev/null | head -n 1 || true)
    if [ -n "$parent" ]; then
      printf '/dev/%s\n' "$parent"
    elif [ "$(lsblk -dnro TYPE -- "$source" 2>/dev/null || true)" = "disk" ]; then
      printf '%s\n' "$source"
    fi
  done | sort -u
}

build_disk_list() {
  : > "$DISK_LIST"
  : > "$DEVICE_LIST"
  lsblk -dnp -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" {print $1}' > "$DEVICE_LIST"

  install_sources=$(installation_disks)
  index=0

  while IFS= read -r device; do
    [ -b "$device" ] || continue
    if [ -n "$install_sources" ] && \
       printf '%s\n' "$install_sources" | grep -Fxq -- "$device"; then
      continue
    fi

    bytes=$(lsblk -bdnro SIZE -- "$device" 2>/dev/null | head -n 1 || true)
    case "$bytes" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$bytes" -ge "$MINIMUM_BYTES" ] || continue

    size=$(lsblk -dnro SIZE -- "$device" 2>/dev/null | head -n 1 || true)
    model=$(lsblk -dnro MODEL -- "$device" 2>/dev/null | head -n 1 || true)
    serial=$(lsblk -dnro SERIAL -- "$device" 2>/dev/null | head -n 1 || true)
    transport=$(lsblk -dnro TRAN -- "$device" 2>/dev/null | head -n 1 || true)
    removable=$(lsblk -dnro RM -- "$device" 2>/dev/null | head -n 1 || true)

    index=$((index + 1))
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$index" \
      "$device" \
      "$(clean_field "$size")" \
      "$(clean_field "$model")" \
      "$(clean_field "$serial")" \
      "$(clean_field "$transport")" \
      "$(clean_field "${removable:-0}")" >> "$DISK_LIST"
  done < "$DEVICE_LIST"
}

while :; do
  clear_screen
  echo "=============================================================="
  green "                WASALIGHT INSTALLER v$INSTALLER_VERSION"
  echo "=============================================================="
  echo
  echo "Seleziona il disco sul quale installare WASALIGHT."
  echo
  echo "ATTENZIONE: IL DISCO SCELTO VERRA' CANCELLATO COMPLETAMENTE."
  echo "Il supporto USB da cui e' avviato l'installer non viene mostrato."
  echo

  build_disk_list
  disk_count=$(wc -l < "$DISK_LIST" | tr -d ' ')

  if [ "$disk_count" -eq 0 ]; then
    pause_error "Nessun disco installabile da almeno 16 GiB trovato."
    continue
  fi

  while IFS='|' read -r number device size model serial transport removable; do
    note=""
    [ "$removable" = "1" ] && note="$note [REMOVIBILE]"
    [ "$transport" = "usb" ] && note="$note [USB]"
    printf '  %2s) %-16s %-9s  %s%s\n' "$number" "$device" "$size" "$model" "$note"
    [ -z "$serial" ] || printf '      seriale: %s\n' "$serial"
  done < "$DISK_LIST"

  echo
  printf "Numero del disco: "
  IFS= read -r choice

  case "$choice" in
    ''|*[!0-9]*)
      pause_error "Scelta non valida."
      continue
      ;;
  esac

  line=$(awk -F'|' -v number="$choice" '$1 == number {print; exit}' "$DISK_LIST")
  if [ -z "$line" ]; then
    pause_error "Scelta non valida."
    continue
  fi

  target=$(printf '%s' "$line" | cut -d'|' -f2)
  size=$(printf '%s' "$line" | cut -d'|' -f3)
  model=$(printf '%s' "$line" | cut -d'|' -f4)
  serial=$(printf '%s' "$line" | cut -d'|' -f5)

  clear_screen
  echo "=============================================================="
  echo "                    CONFERMA DISCO"
  echo "=============================================================="
  echo
  echo "Disco:      $target"
  echo "Dimensione: $size"
  echo "Modello:    $model"
  [ -z "$serial" ] || echo "Seriale:    $serial"
  echo
  echo "TUTTI I DATI SU QUESTO DISCO VERRANNO CANCELLATI."
  echo
  echo "Per confermare scrivi esattamente: CANCELLA"
  printf "> "
  IFS= read -r confirmation

  if [ "$confirmation" != "CANCELLA" ]; then
    pause_error "Conferma non valida. Operazione annullata."
    continue
  fi

  [ -b "$target" ] || {
    pause_error "Il disco selezionato non e' piu' disponibile."
    continue
  }
  [ "$(lsblk -dnro TYPE -- "$target" 2>/dev/null || true)" = "disk" ] || {
    pause_error "Il dispositivo selezionato non e' piu' un disco valido."
    continue
  }
  current_install_sources=$(installation_disks)
  if [ -n "$current_install_sources" ] && \
     printf '%s\n' "$current_install_sources" | grep -Fxq -- "$target"; then
    pause_error "Il disco selezionato contiene il supporto di installazione."
    continue
  fi
  break
done

[ -f /autoinstall.yaml ] || {
  echo
  echo "ERRORE: /autoinstall.yaml non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_TARGET_DISK__' /autoinstall.yaml || {
  echo
  echo "ERRORE: placeholder del disco non trovato."
  echo "Premi INVIO per aprire una shell."
  IFS= read -r _dummy
  exec sh
}

escaped_target=$(printf '%s' "$target" | sed 's/[\/&]/\\&/g')
sed "s/__WASALIGHT_TARGET_DISK__/$escaped_target/g" \
  /autoinstall.yaml > /run/autoinstall.wasalight.yaml
cat /run/autoinstall.wasalight.yaml > /autoinstall.yaml

printf '%s\n' "$target" > /run/wasalight-target-disk
printf '%s\n' "$size" > /run/wasalight-target-size
printf '%s\n' "$model" > /run/wasalight-target-model

clear_screen
echo "Disco selezionato: $target"
echo
echo "Layout WASALIGHT:"
echo "  EFI"
echo "  /boot"
echo "  LVM"
echo "    /     50%"
echo "    /data spazio restante"
echo
echo "L'installazione proseguira' automaticamente..."
sleep 2
