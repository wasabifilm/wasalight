# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_companion() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    local companion_source=/usr/local/src/companionpi
    local temporary_source="${companion_source}.new.$$"
    local companion_present=0
    local companion_build
    local installed_companion_version
    local companion_icon_tmp

    [[ -d /opt/companion && -x $companion_source/launch.sh ]] && companion_present=1

    if ((ENABLE_COMPANION)) && ((companion_present == 0)); then
        mountpoint -q "$DATA_MOUNT" || \
            die "Bitfocus Companion requires the persistent /data mount"
        log "installing Bitfocus Companion $COMPANION_VERSION headless"
        id companion >/dev/null 2>&1 || adduser --disabled-password --gecos "" companion

        install -d -m 0755 /usr/local/src
        if [[ -e $companion_source && ! -d $companion_source/.git ]]; then
            die "Companion source path exists but is not a Git checkout: $companion_source"
        fi
        if [[ -d $companion_source/.git ]]; then
            git -C "$companion_source" remote set-url origin "$COMPANION_REPOSITORY"
            git -C "$companion_source" fetch --depth=1 origin "$COMPANION_PI_COMMIT"
            git -C "$companion_source" checkout --detach "$COMPANION_PI_COMMIT"
        else
            [[ ! -e $temporary_source ]] || \
                die "temporary Companion source path already exists: $temporary_source"
            git clone --no-checkout "$COMPANION_REPOSITORY" "$temporary_source"
            git -C "$temporary_source" checkout --detach "$COMPANION_PI_COMMIT"
            mv "$temporary_source" "$companion_source"
        fi

        "$companion_source/update.sh" stable "$COMPANION_VERSION"
        [[ -d /opt/companion && -s /opt/companion/BUILD && \
           -f /etc/systemd/system/companion.service ]] || \
            die "the official Companion installer did not create the expected runtime"
        companion_build=$(tr -d '\r\n' </opt/companion/BUILD)
        installed_companion_version=${companion_build#[vV]}
        installed_companion_version=${installed_companion_version%%+*}
        [[ $installed_companion_version == "$COMPANION_VERSION" ]] || \
            die "Companion requested $COMPANION_VERSION but BUILD reports $companion_build"
        companion_present=1
    fi

    if ((companion_present == 0)); then
        rm -f \
            /etc/wasalight/apps.d/companion.desktop \
            /etc/wasalight/apps.d/companion-web.desktop
        return 0
    fi

    id companion >/dev/null 2>&1 || \
        die "Companion runtime exists but its dedicated user is missing"
    mountpoint -q "$DATA_MOUNT" || \
        die "installed Companion cannot be configured without /data"
    [[ -s /opt/companion/BUILD ]] || \
        die "installed Companion has no readable BUILD version"
    companion_build=$(tr -d '\r\n' </opt/companion/BUILD)
    installed_companion_version=${companion_build#[vV]}
    installed_companion_version=${installed_companion_version%%+*}

    # Use Bitfocus' official Linux icon when the pinned, checksummed asset is
    # reachable. The local Wasalight SVG remains a safe offline fallback.
    install -d -m 0755 /usr/local/share/icons/wasalight
    companion_icon_tmp=$(mktemp /run/wasalight-companion-icon.XXXXXX)
    if curl --fail --silent --show-error --location \
        "https://raw.githubusercontent.com/bitfocus/companion/$COMPANION_ICON_COMMIT/assets/linux/icon.png" \
        -o "$companion_icon_tmp" && \
       printf '%s  %s\n' "$COMPANION_ICON_SHA256" "$companion_icon_tmp" | sha256sum -c -; then
        install -m 0644 "$companion_icon_tmp" \
            /usr/local/share/icons/wasalight/companion-official.png
        log "installed the verified official Bitfocus Companion icon"
    elif [[ -s /usr/local/share/icons/wasalight/companion-official.png ]]; then
        warn "official Companion icon refresh failed; keeping the previously verified icon"
    else
        warn "official Companion icon unavailable or checksum mismatch; using the local fallback"
    fi
    rm -f -- "$companion_icon_tmp"

    # The execute-only permission for other users lets the chamsys desktop
    # reach its dedicated browser profile without exposing Companion data.
    install -d -o root -g companion -m 0751 "$DATA_MOUNT/companion"
    install -d -o companion -g companion -m 0750 \
        "$DATA_MOUNT/companion/home" \
        "$DATA_MOUNT/companion/log" \
        "$DATA_MOUNT/companion/backups"
    install -d -o root -g companion -m 0750 "$DATA_MOUNT/companion/etc"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
        "$DATA_MOUNT/companion/browser" \
        "$DATA_MOUNT/companion/browser/config" \
        "$DATA_MOUNT/companion/browser/data"
    install -d -o companion -g companion -m 0750 /home/companion
    install -d -o root -g root -m 0755 /etc/companion

    if ! mountpoint -q /home/companion; then
        cp -a --update=none /home/companion/. "$DATA_MOUNT/companion/home/"
    fi
    if ! mountpoint -q /etc/companion; then
        cp -a --update=none /etc/companion/. "$DATA_MOUNT/companion/etc/"
    fi
    chown -R companion:companion "$DATA_MOUNT/companion/home"
    chown -R root:companion "$DATA_MOUNT/companion/etc"

    ensure_fstab_line "Bitfocus Companion persistent home" \
        "$DATA_MOUNT/companion/home /home/companion none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
    ensure_fstab_line "Bitfocus Companion persistent launch configuration" \
        "$DATA_MOUNT/companion/etc /etc/companion none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
    systemctl daemon-reload
    mountpoint -q /home/companion || mount /home/companion
    mountpoint -q /etc/companion || mount /etc/companion

    if [[ ! -e $DATA_MOUNT/companion/log/companion.log ]]; then
        install -o companion -g companion -m 0640 /dev/null \
            "$DATA_MOUNT/companion/log/companion.log"
    else
        chown companion:companion "$DATA_MOUNT/companion/log/companion.log"
        chmod 0640 "$DATA_MOUNT/companion/log/companion.log"
    fi

    install -d -m 0755 /etc/wasalight/logrotate.d
    install_template /etc/wasalight/logrotate.d/companion 0644

    install -d -m 0755 /etc/wasalight
    write_file /etc/wasalight/companion-target-version 0644 <<EOF
$COMPANION_VERSION
EOF
    write_file /etc/wasalight/companion-pi-commit 0644 <<EOF
$COMPANION_PI_COMMIT
EOF
    if [[ ! -s $DATA_MOUNT/companion/installed-version ]]; then
        write_file "$DATA_MOUNT/companion/installed-version" 0644 <<EOF
$installed_companion_version
EOF
    fi

    install -d -m 0755 /etc/systemd/system/companion.service.d
    install_template /etc/systemd/system/companion.service.d/wasalight.conf 0644

    install_template /usr/local/bin/wasalight-companion-version 0755

    install_template /usr/local/sbin/wasalight-companion-control 0755

    install_template /usr/local/sbin/wasalight-companion-backup 0755

    install_template /usr/local/sbin/wasalight-companion-update 0755

    install_template /usr/local/libexec/wasalight-companion-update-session 0755

    install_template /usr/local/bin/wasalight-companion-update-terminal 0755

    install_template /usr/local/bin/wasalight-companion-panel 0755

    install_template /usr/local/bin/wasalight-companion-browser 0755

    install_template /usr/local/bin/wasalight-falkon-profile 0755

    install_template /usr/local/bin/wasalight-x11-window-icon 0755

    install -d -m 0755 /etc/wasalight/apps.d
    # The old technical launcher duplicated the controls now exposed by the
    # Control Center plugin card. Keep only the operational web interface.
    rm -f /etc/wasalight/apps.d/companion.desktop
    install_template /etc/wasalight/apps.d/companion-web.desktop 0644
    install -d -m 0755 /usr/local/share/applications
    install -m 0644 /etc/wasalight/apps.d/companion-web.desktop \
        /usr/local/share/applications/wasalight-companion-web.desktop
    if [[ ! -s /usr/local/share/icons/wasalight/companion-official.png ]]; then
        sed -i 's|companion-official.png|companion.svg|' \
            /etc/wasalight/apps.d/companion-web.desktop \
            /usr/local/share/applications/wasalight-companion-web.desktop
    fi

    systemctl daemon-reload
    if [[ -r $DATA_MOUNT/system/plugins-state/companion ]] && \
       [[ $(<"$DATA_MOUNT/system/plugins-state/companion") == disabled ]]; then
        systemctl disable --now companion.service
    else
        systemctl enable --now companion.service
    fi
}
