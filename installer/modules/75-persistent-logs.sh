configure_persistent_logs() {
    local log_file
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$DATA_MOUNT/log"
        for log_file in wasalight-magicq-console.log wasalight-magicq-session.log wasalight-control.log wasalight-network-tools.log wasalight-xorg-startup.log; do
            if [[ ! -e "$DATA_MOUNT/log/$log_file" ]]; then
                install -o "$TARGET_USER" -g "$TARGET_USER" -m 0640 \
                    /dev/null "$DATA_MOUNT/log/$log_file"
            else
                chown "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/log/$log_file"
                chmod 0640 "$DATA_MOUNT/log/$log_file"
            fi
        done
    else
        warn "persistent MagicQ logs are unavailable because /data is not mounted"
    fi

    install -d -m 0755 /etc/wasalight
    install -d -m 0755 /etc/wasalight/logrotate.d
    install_template /etc/wasalight/wasalight-logrotate.conf 0644

    install_template /etc/systemd/system/wasalight-logrotate.service 0644

    install_template /etc/systemd/system/wasalight-logrotate.timer 0644

    systemctl enable wasalight-logrotate.timer
}
