#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -eu

umask 077

TTY=/dev/tty1
[ -c "$TTY" ] || TTY=/dev/console
exec <"$TTY" >"$TTY" 2>&1

DISK_LIST=/run/wasalight-disks.txt
DEVICE_LIST=/run/wasalight-device-names.txt
MINIMUM_BYTES=$((32 * 1024 * 1024 * 1024))
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

if [ -d /sys/firmware/efi ]; then
  boot_mode=UEFI
  disk_grub_device=false
  efi_grub_device=true
else
  boot_mode=BIOS
  disk_grub_device=true
  efi_grub_device=false
fi

clear_screen() { printf '\033[2J\033[H'; }
green() { printf '\033[1;32m%s\033[0m\n' "$1"; }

pause_error() {
  printf '\n%s\n' "$1"
  printf 'Press ENTER to try again... '
  IFS= read -r _dummy
}

clean_field() {
  printf '%s' "$1" | tr '\n|' '  '
}

required_runtime_value() {
  runtime_file=$1
  runtime_name=$2
  runtime_value=$(sed -n '1p' "$runtime_file" 2>/dev/null || true)
  if [ -z "$runtime_value" ]; then
    echo "ERROR: $runtime_name is unavailable." >&2
    return 1
  fi
  printf '%s\n' "$runtime_value"
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
  echo "Select the disk on which to install WASALIGHT."
  echo
  install_variant=$(sed -n '1p' /run/wasalight-install-variant 2>/dev/null || true)
  case "$install_variant" in
    FULL)
      echo "FULL mode: Ubuntu is on the ISO; Internet is required for Wasalight."
      ;;
    NETBOOT)
      echo "NETBOOT mode: Internet is required to download Ubuntu and Wasalight."
      ;;
  esac
  echo
  echo "WARNING: THE SELECTED DISK WILL BE COMPLETELY ERASED."
  echo "The USB installation media is excluded from this list."
  echo

  build_disk_list
  disk_count=$(wc -l < "$DISK_LIST" | tr -d ' ')

  if [ "$disk_count" -eq 0 ]; then
    pause_error "No installable disk of at least 32 GiB was found."
    continue
  fi

  while IFS='|' read -r number device size model serial transport removable; do
    note=""
    [ "$removable" = "1" ] && note="$note [REMOVABLE]"
    [ "$transport" = "usb" ] && note="$note [USB]"
    printf '  %2s) %-16s %-9s  %s%s\n' "$number" "$device" "$size" "$model" "$note"
    [ -z "$serial" ] || printf '      serial: %s\n' "$serial"
  done < "$DISK_LIST"

  echo
  printf "Disk number: "
  IFS= read -r choice

  case "$choice" in
    ''|*[!0-9]*)
      pause_error "Invalid selection."
      continue
      ;;
  esac

  line=$(awk -F'|' -v number="$choice" '$1 == number {print; exit}' "$DISK_LIST")
  if [ -z "$line" ]; then
    pause_error "Invalid selection."
    continue
  fi

  target=$(printf '%s' "$line" | cut -d'|' -f2)
  size=$(printf '%s' "$line" | cut -d'|' -f3)
  model=$(printf '%s' "$line" | cut -d'|' -f4)
  serial=$(printf '%s' "$line" | cut -d'|' -f5)
  keyboard_label=$(required_runtime_value /run/wasalight-keyboard-label \
    "keyboard selection") || exit 1
  language_label=$(required_runtime_value /run/wasalight-interface-language-label \
    "interface language selection") || exit 1
  install_variant=$(required_runtime_value /run/wasalight-install-variant \
    "installation mode") || exit 1
  preflight_status=$(required_runtime_value /run/wasalight-preflight-status \
    "preflight status") || exit 1
  timezone_label=$(required_runtime_value /run/wasalight-timezone-label \
    "time zone selection") || exit 1
  password_status=$(required_runtime_value /run/wasalight-password-status \
    "password status") || exit 1
  [ "$password_status" = "configured" ] || {
    echo "ERROR: the administrator password is not configured."
    exit 1
  }

  clear_screen
  echo "=============================================================="
  echo "              REVIEW AND CONFIRM INSTALLATION"
  echo "=============================================================="
  echo
  echo "Installer:  v$INSTALLER_VERSION"
  echo "Mode:       $install_variant"
  echo "Preflight:  $preflight_status"
  echo "Language:   $language_label"
  echo "Keyboard:   $keyboard_label"
  echo "Time zone:  $timezone_label"
  echo "Password:   configured"
  echo "Boot mode:  $boot_mode"
  echo
  echo "Disk:   $target"
  echo "Size:   $size"
  echo "Model:  $model"
  [ -z "$serial" ] || echo "Serial: $serial"
  echo
  echo "Storage: GPT, EFI, /boot and LVM; / uses 50%, /data uses the rest."
  echo
  echo "ALL DATA ON THIS DISK WILL BE ERASED."
  echo
  echo "To confirm, type exactly: ERASE"
  printf "> "
  IFS= read -r confirmation

  if [ "$confirmation" != "ERASE" ]; then
    pause_error "Confirmation did not match. Operation cancelled."
    continue
  fi

  [ -b "$target" ] || {
    pause_error "The selected disk is no longer available."
    continue
  }
  [ "$(lsblk -dnro TYPE -- "$target" 2>/dev/null || true)" = "disk" ] || {
    pause_error "The selected device is no longer a valid disk."
    continue
  }
  current_install_sources=$(installation_disks)
  if [ -n "$current_install_sources" ] && \
     printf '%s\n' "$current_install_sources" | grep -Fxq -- "$target"; then
    pause_error "The selected disk contains the installation media."
    continue
  fi
  break
done

[ -f /autoinstall.yaml ] || {
  echo
  echo "ERROR: /autoinstall.yaml was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_TARGET_DISK__' /autoinstall.yaml || {
  echo
  echo "ERROR: target disk placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_DISK_GRUB_DEVICE__' /autoinstall.yaml || {
  echo
  echo "ERROR: BIOS GRUB disk placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

grep -Fq '__WASALIGHT_EFI_GRUB_DEVICE__' /autoinstall.yaml || {
  echo
  echo "ERROR: EFI GRUB placeholder was not found."
  echo "Press ENTER to open a shell."
  IFS= read -r _dummy
  exec sh
}

escaped_target=$(printf '%s' "$target" | sed 's/[\/&]/\\&/g')
sed "s/__WASALIGHT_TARGET_DISK__/$escaped_target/g" \
  /autoinstall.yaml | \
  sed \
    -e "s/false # __WASALIGHT_DISK_GRUB_DEVICE__/$disk_grub_device/g" \
    -e "s/true # __WASALIGHT_EFI_GRUB_DEVICE__/$efi_grub_device/g" \
  > /run/autoinstall.wasalight.yaml
cat /run/autoinstall.wasalight.yaml > /autoinstall.yaml

printf '%s\n' "$target" > /run/wasalight-target-disk
printf '%s\n' "$size" > /run/wasalight-target-size
printf '%s\n' "$model" > /run/wasalight-target-model
printf '%s\n' "$boot_mode" > /run/wasalight-boot-mode

clear_screen
echo "Selected disk: $target"
echo
echo "Layout WASALIGHT:"
echo "  Boot $boot_mode"
echo "  BIOS GRUB"
echo "  EFI"
echo "  /boot"
echo "  LVM"
echo "    /     50%"
echo "    /data remaining space"
echo
echo "Installation will continue automatically..."
sleep 2
