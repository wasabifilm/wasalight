#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Casper hook for the Wasalight Mini ISO two-stage network loader.

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case ${1:-} in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /scripts/casper-functions
. /scripts/casper-helpers

readonly MEDIA_URL="__WASALIGHT_SERVER_ISO_URL__"
readonly MEDIA_SIZE="__WASALIGHT_SERVER_ISO_SIZE__"
readonly MEDIA_256SUM="__WASALIGHT_SERVER_ISO_SHA256__"
readonly MINI_MOUNT=/cdrom
readonly FINAL_OVERLAY=/wasalight/final-overlay.cpio

mount_mini_iso() {
    configure_networking
    device=$(blkid --match-token LABEL=ISOIMAGE | cut -d: -f1 | head -n 1)
    [ -n "$device" ] || panic "Mini ISO media not found"
    modprobe isofs
    grep -qs " $MINI_MOUNT " /proc/mounts || mount -o ro "$device" "$MINI_MOUNT"
}

wasalight_step1() {
    mount_mini_iso
    echo "WASALIGHT NETBOOT: preparing Ubuntu Server __WASALIGHT_UBUNTU_POINT_RELEASE__ download..."

    memmap_size=$(/usr/lib/mini-iso-tools/get_memmap_directive "$MEDIA_SIZE") || {
        echo "Insufficient RAM. WASALIGHT NETBOOT requires at least 8 GiB."
        /bin/sh
    }

    cmdline="iso-url=$MEDIA_URL"
    cmdline="$cmdline iso-size=$MEDIA_SIZE iso-256sum=$MEDIA_256SUM"
    cmdline="$cmdline wasalight-netboot-step2 memmap=$memmap_size"
    cmdline="$cmdline nokaslr ip=dhcp ---"

    kexec --command-line="$cmdline" \
        --load "$MINI_MOUNT/casper/vmlinuz" \
        --initrd="$MINI_MOUNT/casper/initrd"
    kexec --exec
}

wasalight_step2() {
    configure_networking
    target=/dev/pmem0
    [ -e "$target" ] || panic "Reserved memory device /dev/pmem0 is unavailable"
    [ -n "${MEMMAP:-}" ] || panic "The memmap directive is unavailable"

    echo "WASALIGHT NETBOOT: downloading Ubuntu Server __WASALIGHT_UBUNTU_POINT_RELEASE__..."
    wget "$MEDIA_URL" -O "$target" || panic "Ubuntu download failed"

    echo "WASALIGHT NETBOOT: verifying the Canonical SHA-256 checksum..."
    /usr/lib/mini-iso-tools/checksum-device \
        "$target" "$MEDIA_SIZE" "$MEDIA_256SUM" || \
        panic "Invalid Ubuntu ISO checksum"

    mount -o ro "$target" "$MINI_MOUNT"
    [ -f "$FINAL_OVERLAY" ] || panic "Wasalight overlay is unavailable"

    cat "$MINI_MOUNT/casper/initrd" "$FINAL_OVERLAY" \
        >/run/wasalight-server-initrd

    cmdline="live-media=$target $MEMMAP nokaslr ip=dhcp"
    cmdline="$cmdline cloud-config-url=/dev/null autoinstall"
    cmdline="$cmdline subiquity.autoinstallpath=autoinstall.yaml ---"

    echo "WASALIGHT NETBOOT: starting the verified installer..."
    kexec --command-line="$cmdline" \
        --load "$MINI_MOUNT/casper/vmlinuz" \
        --initrd=/run/wasalight-server-initrd
    kexec --exec
}

MENU_STEP=""
MEMMAP=""
for argument in $(cat /proc/cmdline); do
    case $argument in
        wasalight-netboot) MENU_STEP=step1 ;;
        wasalight-netboot-step2) MENU_STEP=step2 ;;
        memmap=*) MEMMAP=${argument#memmap=} ;;
    esac
done

case $MENU_STEP in
    step1) wasalight_step1 ;;
    step2) wasalight_step2 ;;
esac
