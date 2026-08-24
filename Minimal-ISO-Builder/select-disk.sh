#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Validated disk backend for install-wizard.py.
set -eu

umask 077
RUNTIME_DIR=${WASALIGHT_RUNTIME_DIR:-/run}
AUTOINSTALL=${WASALIGHT_AUTOINSTALL_PATH:-/autoinstall.yaml}
DISK_LIST="$RUNTIME_DIR/wasalight-disks.txt"
DEVICE_LIST="$RUNTIME_DIR/wasalight-device-names.txt"
MINIMUM_BYTES=$((32 * 1024 * 1024 * 1024))

if [ -d /sys/firmware/efi ]; then
  boot_mode=UEFI
  disk_grub_device=false
  efi_grub_device=true
else
  boot_mode=BIOS
  disk_grub_device=true
  efi_grub_device=false
fi

clean_field() { printf '%s' "$1" | tr '\n|' '  '; }

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
    elif [ "$(lsblk -dnro TYPE -- "$source" 2>/dev/null || true)" = disk ]; then
      printf '%s\n' "$source"
    fi
  done | sort -u
}

build_disk_list() {
  : >"$DISK_LIST"
  : >"$DEVICE_LIST"
  lsblk -dnp -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" {print $1}' >"$DEVICE_LIST"
  install_sources=$(installation_disks)
  index=0
  while IFS= read -r device; do
    [ -b "$device" ] || continue
    if [ -n "$install_sources" ] && printf '%s\n' "$install_sources" | grep -Fxq -- "$device"; then
      continue
    fi
    bytes=$(lsblk -bdnro SIZE -- "$device" 2>/dev/null | head -n 1 || true)
    case "$bytes" in ''|*[!0-9]*) continue ;; esac
    [ "$bytes" -ge "$MINIMUM_BYTES" ] || continue
    size=$(lsblk -dnro SIZE -- "$device" 2>/dev/null | head -n 1 || true)
    model=$(lsblk -dnro MODEL -- "$device" 2>/dev/null | head -n 1 || true)
    serial=$(lsblk -dnro SERIAL -- "$device" 2>/dev/null | head -n 1 || true)
    transport=$(lsblk -dnro TRAN -- "$device" 2>/dev/null | head -n 1 || true)
    removable=$(lsblk -dnro RM -- "$device" 2>/dev/null | head -n 1 || true)
    index=$((index + 1))
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$index" "$device" \
      "$(clean_field "$size")" "$(clean_field "$model")" \
      "$(clean_field "$serial")" "$(clean_field "$transport")" \
      "$(clean_field "${removable:-0}")" >>"$DISK_LIST"
  done <"$DEVICE_LIST"
}

apply_target() {
  requested=$1
  build_disk_list
  line=$(awk -F'|' -v requested="$requested" '$2 == requested {print; exit}' "$DISK_LIST")
  [ -n "$line" ] || {
    echo "ERROR: selected disk is unavailable, too small, or contains the installer." >&2
    return 1
  }
  target=$(printf '%s' "$line" | cut -d'|' -f2)
  size=$(printf '%s' "$line" | cut -d'|' -f3)
  model=$(printf '%s' "$line" | cut -d'|' -f4)
  [ -b "$target" ] || { echo "ERROR: selected disk disappeared." >&2; return 1; }
  [ "$(lsblk -dnro TYPE -- "$target" 2>/dev/null || true)" = disk ] || {
    echo "ERROR: selected device is no longer a disk." >&2; return 1;
  }
  current_install_sources=$(installation_disks)
  if [ -n "$current_install_sources" ] && printf '%s\n' "$current_install_sources" | grep -Fxq -- "$target"; then
    echo "ERROR: selected disk contains the installation media." >&2
    return 1
  fi

  [ -f "$AUTOINSTALL" ] || { echo "ERROR: autoinstall.yaml was not found." >&2; return 1; }
  for placeholder in __WASALIGHT_TARGET_DISK__ __WASALIGHT_DISK_GRUB_DEVICE__ \
    __WASALIGHT_EFI_GRUB_DEVICE__
  do
    grep -Fq "$placeholder" "$AUTOINSTALL" || {
      echo "ERROR: $placeholder was not found in autoinstall.yaml." >&2
      return 1
    }
  done
  escaped_target=$(printf '%s' "$target" | sed 's/[\/&]/\\&/g')
  sed "s/__WASALIGHT_TARGET_DISK__/$escaped_target/g" "$AUTOINSTALL" | \
    sed -e "s/false # __WASALIGHT_DISK_GRUB_DEVICE__/$disk_grub_device/g" \
        -e "s/true # __WASALIGHT_EFI_GRUB_DEVICE__/$efi_grub_device/g" \
    >"$RUNTIME_DIR/autoinstall.wasalight.yaml"
  cat "$RUNTIME_DIR/autoinstall.wasalight.yaml" >"$AUTOINSTALL"

  printf '%s\n' "$target" >"$RUNTIME_DIR/wasalight-target-disk"
  printf '%s\n' "$size" >"$RUNTIME_DIR/wasalight-target-size"
  printf '%s\n' "$model" >"$RUNTIME_DIR/wasalight-target-model"
  printf '%s\n' "$boot_mode" >"$RUNTIME_DIR/wasalight-boot-mode"
}

case "${1:-}" in
  --list-disks)
    [ "$#" -eq 1 ] || exit 2
    build_disk_list
    cat "$DISK_LIST"
    ;;
  --boot-mode)
    [ "$#" -eq 1 ] || exit 2
    printf '%s\n' "$boot_mode"
    ;;
  --apply-target)
    [ "$#" -eq 2 ] || exit 2
    apply_target "$2"
    ;;
  *)
    echo "ERROR: expected a validated backend operation." >&2
    exit 2
    ;;
esac
