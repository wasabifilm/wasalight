# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_usb() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 "$USB_MOUNT"

    install_template /usr/local/libexec/wasalight-usb-paths 0755

    install_template /usr/local/libexec/wasalight-usb-mount 0755

    install_template /usr/local/libexec/wasalight-usb-unmount 0755

    install_template /etc/systemd/system/wasalight-usb@.service 0644

    install_template /etc/udev/rules.d/90-wasalight-usb.rules 0644

    udevadm control --reload-rules
}

install_magicq() {
    if [[ -z "$DEB_PATH" ]]; then
        warn "no MagicQ .deb supplied; appliance configuration will continue"
        return
    fi
    log "installing MagicQ package: $DEB_PATH"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEB_PATH"
    [[ -x /opt/magicq/runmagicq.sh || -x /opt/magicq/bin/mqqt ]] || \
        die "MagicQ installed but expected executables under /opt/magicq are missing"

    if [[ -x /opt/magicq/bin/mqqt ]]; then
        local missing_libraries
        missing_libraries=$(ldd /opt/magicq/bin/mqqt 2>/dev/null | \
            awk '/not found/ {print $1}' | sort -u | paste -sd, - || true)
        [[ -z $missing_libraries ]] || \
            die "MagicQ has unresolved runtime libraries: $missing_libraries"
    fi
}

repair_magicq_persistent_permissions() {
    # The vendor package can recreate paths below Documents/MagicQ as root.
    # Repair only the two user-owned persistent trees: root-home must remain
    # private to root because it contains the configuration used by sudo runs.
    mountpoint -q "$DATA_MOUNT" || return 0

    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0770 \
        "$DATA_MOUNT/magicq/Documents/MagicQ" \
        "$DATA_MOUNT/magicq/.local/share"
    chown -R "$TARGET_USER:$TARGET_USER" \
        "$DATA_MOUNT/magicq/Documents/MagicQ" \
        "$DATA_MOUNT/magicq/.local/share"
    find "$DATA_MOUNT/magicq/Documents/MagicQ" \
        "$DATA_MOUNT/magicq/.local/share" -type d \
        -exec chmod u+rwx,g+rwx,o-rwx {} +
    find "$DATA_MOUNT/magicq/Documents/MagicQ" \
        "$DATA_MOUNT/magicq/.local/share" -type f \
        -exec chmod u+rw,g+rw,o-rwx {} +
}
