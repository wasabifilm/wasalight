# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_management_tools() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    install -d -m 0755 /etc/wasalight/apps.d
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 \
            "$DATA_MOUNT/system/first-run" "$DATA_MOUNT/system/magicq-updates"
    fi
    for tool in \
        wasalight-health wasalight-health-monitor wasalight-system-audit \
        wasalight-support-bundle wasalight-data-transfer \
        wasalight-first-run wasalight-magicq-usb-watch \
        wasalight-plugin-bundle wasalight-update-snapshot wasalight-rollback; do
        source="$PROJECT_DIR/libexec/$tool"
        [[ -s $source ]] || die "management tool is missing: $source"
        case $tool in
            wasalight-health|wasalight-system-audit|wasalight-first-run|wasalight-magicq-usb-watch)
                destination="/usr/local/bin/$tool" ;;
            *) destination="/usr/local/sbin/$tool" ;;
        esac
        install -o root -g root -m 0755 "$source" "$destination"
    done
    install -o root -g root -m 0755 \
        "$PROJECT_DIR/lib/wasalight-release-manifest.sh" \
        "$PROJECT_DIR/lib/wasalight-operation-lock.sh" \
        /usr/local/libexec/

    install_template /usr/local/bin/wasalight-support-bundle-terminal 0755

    install_template /usr/local/bin/wasalight-data-transfer-terminal 0755

    install_template /usr/local/bin/wasalight-plugin-bundle-terminal 0755

    install_template /usr/local/bin/wasalight-screen-lock 0755
    install_template /usr/local/bin/wasalight-rollback-ui 0755
    install_template /usr/local/bin/wasalight-date-time 0755
    install_template /usr/local/bin/wasalight-magicq-install-ui 0755
    install_template /usr/local/sbin/wasalight-magicq-install 0755
    install_template /usr/local/sbin/wasalight-time-control 0755

    install_template /etc/wasalight/apps.d/health.desktop 0644
    install_template /etc/wasalight/apps.d/system-audit.desktop 0644
    install_template /etc/wasalight/apps.d/support-bundle.desktop 0644
    install_template /etc/wasalight/apps.d/data-transfer.desktop 0644
    install_template /etc/wasalight/apps.d/plugin-bundle.desktop 0644

    install_template /etc/wasalight/apps.d/magicq-usb-update.desktop 0644

    install_template /etc/wasalight/apps.d/calculator.desktop 0644

    install_template /etc/wasalight/apps.d/mousepad.desktop 0644

    install_template /etc/wasalight/apps.d/screen-lock.desktop 0644
    install_template /etc/wasalight/apps.d/rollback.desktop 0644
    install_template /etc/wasalight/apps.d/date-time.desktop 0644

    install -d -m 0755 /usr/share/polkit-1/actions
    install_template /usr/share/polkit-1/actions/com.wasalight.time.policy 0644
    install_template /usr/share/polkit-1/actions/com.wasalight.magicq.policy 0644

    install_template /etc/sudoers.d/wasalight-management 0440
    visudo -cf /etc/sudoers.d/wasalight-management >/dev/null

    install_template /etc/systemd/system/wasalight-health.service 0644
    systemctl disable --now wasalight-health.timer 2>/dev/null || true
    rm -f /etc/systemd/system/wasalight-health.timer
    systemctl daemon-reload
    systemctl enable wasalight-health.service
}
