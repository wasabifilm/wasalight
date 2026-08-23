# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_user() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    local supplementary_groups password_status
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        useradd --create-home --shell /bin/bash --user-group "$TARGET_USER"
        passwd -l "$TARGET_USER" >/dev/null
        RESET_CHAMSYS_PASSWORD=1
    fi

    # chamsys is the dedicated appliance operator and is always an
    # administrator. Optional desktop/log groups vary between Ubuntu images;
    # add only those actually present, but sudo is mandatory.
    getent group sudo >/dev/null || die "the required sudo group is unavailable"
    supplementary_groups=$(existing_groups_csv \
        audio video plugdev sudo adm systemd-journal)
    [[ -z $supplementary_groups ]] || \
        usermod -aG "$supplementary_groups" "$TARGET_USER"

    password_status=$(passwd -S "$TARGET_USER" | awk '{print $2}')
    if [[ $password_status != P ]] || ((RESET_CHAMSYS_PASSWORD)); then
        [[ -t 0 ]] || die "setting the chamsys password requires an interactive terminal"
        log "set the password for $TARGET_USER (it may match your Ubuntu admin password)"
        passwd "$TARGET_USER"
    fi

    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/Documents/MagicQ"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/Desktop"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.local/share"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/openbox"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/pcmanfm/default"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/conky"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/libfm"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/tint2"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/wasalight-touch"

    if mountpoint -q "$DATA_MOUNT"; then
        chown -R "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/magicq"
        chmod 0750 \
            "$DATA_MOUNT/magicq" \
            "$DATA_MOUNT/magicq/Documents" \
            "$DATA_MOUNT/magicq/Documents/MagicQ" \
            "$DATA_MOUNT/magicq/.local" \
            "$DATA_MOUNT/magicq/.local/share"
        install -d -o root -g root -m 0700 \
            "$DATA_MOUNT/magicq/root-home" \
            "$DATA_MOUNT/magicq/root-home/.config" \
            "$DATA_MOUNT/magicq/root-home/.local" \
            "$DATA_MOUNT/magicq/root-home/.local/share"
        chown -R root:root "$DATA_MOUNT/magicq/root-home"
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$DATA_MOUNT/log"
        ensure_fstab_line "MagicQ shows and settings" \
            "$DATA_MOUNT/magicq/Documents/MagicQ $TARGET_HOME/Documents/MagicQ none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
        ensure_fstab_line "MagicQ local shared data" \
            "$DATA_MOUNT/magicq/.local/share $TARGET_HOME/.local/share none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
        ensure_fstab_line "MagicQ root configuration" \
            "$DATA_MOUNT/magicq/root-home/.config /root/.config none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
        ensure_fstab_line "MagicQ root local data" \
            "$DATA_MOUNT/magicq/root-home/.local/share /root/.local/share none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
        ensure_fstab_line "MagicQ root show fallback" \
            "$DATA_MOUNT/magicq/Documents/MagicQ /root/Documents/MagicQ none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"
        ensure_fstab_line "Persistent NetworkManager connections" \
            "$DATA_MOUNT/system/network /etc/NetworkManager/system-connections none bind,x-systemd.requires-mounts-for=$DATA_MOUNT 0 0"

        # Refresh systemd's generated mount units after changing fstab. Without
        # this, every immediate mount emits a stale-fstab warning even though
        # the bind itself succeeds.
        systemctl daemon-reload

        mountpoint -q "$TARGET_HOME/Documents/MagicQ" || mount "$TARGET_HOME/Documents/MagicQ"
        mountpoint -q "$TARGET_HOME/.local/share" || mount "$TARGET_HOME/.local/share"
        install -d -o root -g root -m 0700 \
            /root/.config /root/.local/share /root/Documents/MagicQ
        if ! mountpoint -q /root/.config; then
            cp -a --update=none /root/.config/. "$DATA_MOUNT/magicq/root-home/.config/"
            mount /root/.config
        fi
        if ! mountpoint -q /root/.local/share; then
            cp -a --update=none /root/.local/share/. \
                "$DATA_MOUNT/magicq/root-home/.local/share/"
            mount /root/.local/share
        fi
        if ! mountpoint -q /root/Documents/MagicQ; then
            cp -a --update=none /root/Documents/MagicQ/. \
                "$DATA_MOUNT/magicq/Documents/MagicQ/"
            chown -R "$TARGET_USER:$TARGET_USER" \
                "$DATA_MOUNT/magicq/Documents/MagicQ"
            mount /root/Documents/MagicQ
        fi

        # Qt obtains DocumentsLocation from this XDG file. Keep HOME=/root so
        # MagicQ behaves exactly like the proven manual sudo launch, while new
        # shows are offered under the shared persistent chamsys Documents path.
        write_file /root/.config/user-dirs.dirs 0600 <<EOF
XDG_DOCUMENTS_DIR="$TARGET_HOME/Documents"
EOF
        install -d -m 0700 /etc/NetworkManager/system-connections
        mountpoint -q /etc/NetworkManager/system-connections || mount /etc/NetworkManager/system-connections

        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 \
            "$DATA_MOUNT/system/touchscreen"
        if [[ ! -e "$DATA_MOUNT/system/touchscreen/config" ]]; then
            write_file "$DATA_MOUNT/system/touchscreen/config" 0600 <<'EOF'
# auto: configure only when exactly one touchscreen and one monitor are found.
MODE=auto
DEVICE=
OUTPUT=
ROTATION=normal
EOF
            chown "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/system/touchscreen/config"
        fi

        if [[ ! -e "$DATA_MOUNT/magicq/.magicq_init.sh" ]]; then
            if [[ -f "$TARGET_HOME/.magicq_init.sh" && ! -L "$TARGET_HOME/.magicq_init.sh" ]]; then
                cp -a "$TARGET_HOME/.magicq_init.sh" "$DATA_MOUNT/magicq/.magicq_init.sh"
            else
                write_file "$DATA_MOUNT/magicq/.magicq_init.sh" 0755 <<'EOF'
#!/bin/sh
# Persistent MagicQ startup customisations may be placed here.
exit 0
EOF
            fi
        fi
        chown "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/magicq/.magicq_init.sh"
        rm -f "$TARGET_HOME/.magicq_init.sh"
        ln -s "$DATA_MOUNT/magicq/.magicq_init.sh" "$TARGET_HOME/.magicq_init.sh"
    elif [[ ! -e "$TARGET_HOME/.magicq_init.sh" ]]; then
        write_file "$TARGET_HOME/.magicq_init.sh" 0755 <<'EOF'
#!/bin/sh
# MagicQ startup customisations may be placed here.
exit 0
EOF
    fi

    if [[ ! -e "$TARGET_HOME/.config/wasalight-touch/config" ]]; then
        write_file "$TARGET_HOME/.config/wasalight-touch/config" 0600 <<'EOF'
# Fallback used only when /data/system/touchscreen is unavailable.
MODE=auto
DEVICE=
OUTPUT=
ROTATION=normal
EOF
    fi

    write_file "$TARGET_HOME/.bash_profile" 0644 <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ] && \
   [ ! -e /run/wasalight-first-boot-active ]; then
    xorg_log=/data/log/wasalight-xorg-startup.log
    if [ ! -d /data/log ] || [ ! -w /data/log ]; then
        xorg_log=/tmp/wasalight-xorg-startup.log
    fi

    # Keep the Plymouth-to-Xorg hand-off black and hide the text cursor. Xorg
    # output remains available in a persistent log instead of flashing on tty1.
    printf '\033[2J\033[H\033[?25l' >/dev/tty1
    startx -- -keeptty vt1 >"$xorg_log" 2>&1
    xorg_rc=$?

    # startx normally returns only when the graphical session ends. Restore a
    # usable console before agetty starts the next session or an operator needs
    # to diagnose an Xorg failure.
    printf '\033[?25h\033[2J\033[H' >/dev/tty1
    if [ "$xorg_rc" -ne 0 ]; then
        printf 'Graphical startup failed. Log: %s\n' "$xorg_log" >/dev/tty1
    fi
    exit "$xorg_rc"
fi
EOF

    # login(1) honours .hushlogin and suppresses the last-login/MOTD text that
    # would otherwise be visible briefly before startx clears tty1.
    install -o "$TARGET_USER" -g "$TARGET_USER" -m 0644 /dev/null \
        "$TARGET_HOME/.hushlogin"

    chown "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.magicq_init.sh" "$TARGET_HOME/.bash_profile" \
        "$TARGET_HOME/.config/wasalight-touch/config"
}

configure_touchscreen() {
    install_template /usr/local/bin/wasalight-touch 0755

    ln -sfn wasalight-touch /usr/local/bin/wasalight-touch-status
    ln -sfn wasalight-touch /usr/local/bin/wasalight-touch-apply
    ln -sfn wasalight-touch /usr/local/bin/wasalight-touch-watch
    ln -sfn wasalight-touch /usr/local/bin/wasalight-touch-config
}

configure_vnc() {
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
        "$TARGET_HOME/.config/wasalight-vnc"
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
            "$DATA_MOUNT/system/vnc"
    fi

    install_template /usr/local/bin/wasalight-vnc-password 0755

    install_template /usr/local/bin/wasalight-vnc-start 0755

    install_template /usr/local/bin/wasalight-vnc-stop 0755

    install_template /usr/local/bin/wasalight-vnc-toggle 0755

    install_template /usr/local/bin/wasalight-vnc-control 0755
}

configure_ssh() {
    install_template /usr/local/sbin/wasalight-ssh-control 0755

    install_template /usr/local/bin/wasalight-ssh-toggle 0755
}

configure_remote_persistence() {
    local flag_dir="$DATA_MOUNT/system/service-flags"
    install -d -o root -g root -m 0755 "$flag_dir"

    case $SSH_AUTOSTART_MODE in
        enabled|disabled)
            printf '%s\n' "$SSH_AUTOSTART_MODE" >"$flag_dir/ssh-autostart"
            chmod 0644 "$flag_dir/ssh-autostart"
            ;;
        preserve)
            if [[ ! -e $flag_dir/ssh-autostart ]]; then
                printf '%s\n' disabled >"$flag_dir/ssh-autostart"
                chmod 0644 "$flag_dir/ssh-autostart"
            fi
            ;;
    esac
    if [[ ! -e $flag_dir/vnc-autostart ]]; then
        printf '%s\n' disabled >"$flag_dir/vnc-autostart"
        chmod 0644 "$flag_dir/vnc-autostart"
    fi
    if [[ ! -e $flag_dir/magicq-autostart ]]; then
        printf '%s\n' enabled >"$flag_dir/magicq-autostart"
        chmod 0644 "$flag_dir/magicq-autostart"
    fi
    if [[ ! -e $flag_dir/companion-autostart ]]; then
        printf '%s\n' enabled >"$flag_dir/companion-autostart"
        chmod 0644 "$flag_dir/companion-autostart"
    fi

    install_template /usr/local/sbin/wasalight-remote-persistence 0755

    install_template /usr/local/bin/wasalight-remote-auto-toggle 0755

    install_template /usr/local/bin/wasalight-remote-autostart 0755
}
