#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Copy the Wasalight seed from initramfs into the downloaded live system.

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

set -eu

[ -f /autoinstall.yaml ] || {
    echo "WASALIGHT: autoinstall.yaml non disponibile nell'initramfs" >&2
    exit 1
}
[ -d /wasalight ] || {
    echo "WASALIGHT: script di installazione non disponibili nell'initramfs" >&2
    exit 1
}

cp /autoinstall.yaml /root/autoinstall.yaml
chmod 0600 /root/autoinstall.yaml
mkdir -p /root/wasalight
chmod 0755 /root/wasalight
cp -a /wasalight/. /root/wasalight/
rm -f /root/wasalight/final-overlay.cpio
