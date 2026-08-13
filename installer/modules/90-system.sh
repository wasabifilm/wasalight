configure_volatile_runtime() {
    install -d -m 0755 /etc/systemd/journald.conf.d
    install_template /etc/systemd/journald.conf.d/10-wasalight-volatile.conf 0644

    ensure_fstab_line "MagicQ volatile temporary files" \
        "tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,mode=1777,size=1G 0 0"
    ensure_fstab_line "MagicQ volatile var temporary files" \
        "tmpfs /var/tmp tmpfs rw,nosuid,nodev,noatime,mode=1777,size=512M 0 0"

    install -d -m 0755 /etc/systemd/logind.conf.d
    install_template /etc/systemd/logind.conf.d/10-wasalight-no-sleep.conf 0644
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
}

disable_service_if_present() {
    local unit
    for unit in "$@"; do
        systemctl disable --now "$unit" 2>/dev/null || true
        systemctl mask "$unit" 2>/dev/null || true
    done
}

optimize_system() {
    disable_service_if_present \
        snapd.service snapd.socket ModemManager.service cups.service cups.socket \
        bluetooth.service avahi-daemon.service avahi-daemon.socket whoopsie.service \
        apport.service unattended-upgrades.service

    # Cloud-init is disabled only after this script has completed the machine
    # configuration. A dedicated physical appliance does not need it after
    # installation, but --keep-cloud-init retains the package when required.
    install -d -m 0755 /etc/cloud
    : >/etc/cloud/cloud-init.disabled
    disable_service_if_present \
        cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service

    # Remove cloud/SAN helpers that are unnecessary on a physical appliance.
    # LVM also uses /dev/mapper, so identify the actual block-device ancestry
    # instead of treating every device-mapper path as multipath storage.
    local root_source data_source source
    local uses_multipath=0 uses_iscsi=0
    local cleanup_candidates=(pollinate os-prober)
    local cleanup_installed=()
    root_source=$(findmnt -n -o SOURCE -M /)
    data_source=$(findmnt -n -o SOURCE -M "$DATA_MOUNT" 2>/dev/null || true)

    for source in "$root_source" "$data_source"; do
        source=${source%%\[*}
        [[ -b $source ]] || continue
        if lsblk -sno TYPE "$source" 2>/dev/null | grep -qx mpath; then
            uses_multipath=1
        fi
        if lsblk -sno TRAN "$source" 2>/dev/null | grep -qx iscsi; then
            uses_iscsi=1
        fi
    done

    if ((uses_multipath)); then
        warn "multipath backs the root or data filesystem; keeping multipath-tools"
    else
        cleanup_candidates+=(multipath-tools)
        disable_service_if_present multipathd.service multipathd.socket
    fi

    if ((uses_iscsi)); then
        warn "iSCSI backs the root or data filesystem; keeping open-iscsi"
    else
        cleanup_candidates+=(open-iscsi)
        disable_service_if_present iscsid.service iscsid.socket open-iscsi.service
    fi

    ((PURGE_CLOUD_INIT)) && cleanup_candidates+=(cloud-init)
    for pkg in "${cleanup_candidates[@]}"; do
        is_installed "$pkg" && cleanup_installed+=("$pkg")
    done
    if ((${#cleanup_installed[@]})); then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "${cleanup_installed[@]}"
    fi

    # Run this exactly once, after the definitive Wasalight package set is
    # installed and every safe purge is complete. This avoids removing a
    # dependency early only to download it again later.
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    apt-get clean

    # Mask PackageKit only after every APT/dpkg operation above. Masking it
    # earlier makes dpkg's cache refresh emit a misleading UnitMasked warning.
    disable_service_if_present packagekit.service

    install_template /etc/apt/apt.conf.d/20auto-upgrades 0644

    install_template /etc/default/motd-news 0644
}

install_mode_commands() {
    install_template /usr/local/libexec/wasalight-set-mode 0755

    install_template /usr/local/sbin/wasalight-maintenance 0755

    install_template /usr/local/sbin/wasalight-protect 0755

    install_template /usr/local/bin/wasalight-mode-toggle 0755

    install_template /usr/local/bin/wasalight-status 0755

    install_template /etc/sudoers.d/chamsys-magicq 0440
    visudo -cf /etc/sudoers.d/chamsys-magicq >/dev/null
}

configure_boot_branding() {
    local default_logo="$PROJECT_DIR/assets/branding/boot-logo.png"
    local persistent_dir="$DATA_MOUNT/system/branding"
    local persistent_logo="$persistent_dir/boot-logo.png"
    local selected_logo="$default_logo"
    local theme_dir=/usr/share/plymouth/themes/wasalight
    local intel_graphics=0
    local early_simpledrm=0

    if lspci 2>/dev/null | grep -Eiq \
        'Intel.*(VGA|Display)|(VGA|Display).*Intel'; then
        intel_graphics=1
    fi
    if [[ -d /sys/firmware/efi ]] && \
       grep -qx 'CONFIG_DRM_SIMPLEDRM=y' "/boot/config-$(uname -r)" 2>/dev/null && \
       grep -aFq 'plymouth.use-simpledrm' /usr/sbin/plymouthd 2>/dev/null; then
        early_simpledrm=1
    fi

    [[ -s $default_logo ]] || die "default boot logo is missing: $default_logo"
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o root -g root -m 0755 "$persistent_dir"
        if [[ ! -e $persistent_logo ]]; then
            install -o root -g root -m 0644 "$default_logo" "$persistent_logo"
            log "installed the default persistent boot logo: $persistent_logo"
        fi
        selected_logo=$persistent_logo
    fi

    if ! python3 - "$selected_logo" <<'PYEOF'
import pathlib
import struct
import sys

path = pathlib.Path(sys.argv[1])
with path.open("rb") as source:
    if source.read(8) != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(1)
    length = struct.unpack(">I", source.read(4))[0]
    if source.read(4) != b"IHDR" or length != 13:
        raise SystemExit(1)
    width, height = struct.unpack(">II", source.read(8))
if not (64 <= width <= 8192 and 64 <= height <= 8192):
    raise SystemExit(1)
print(f"Boot logo: {path} ({width}x{height})")
PYEOF
    then
        warn "persistent boot logo is not a valid PNG; using the GitHub default"
        selected_logo=$default_logo
    fi

    install -d -m 0755 "$theme_dir"
    install -m 0644 "$selected_logo" "$theme_dir/boot-logo.png"
    write_file "$theme_dir/wasalight.plymouth" 0644 <<'EOF'
[Plymouth Theme]
Name=Wasalight
Description=Wasalight appliance boot screen
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/wasalight
ScriptFile=/usr/share/plymouth/themes/wasalight/wasalight.script
EOF
    write_file "$theme_dir/wasalight.script" 0644 <<'EOF'
# Near-black background shared with the Wasalight desktop panel.
Window.SetBackgroundTopColor(0.031, 0.043, 0.063);
Window.SetBackgroundBottomColor(0.031, 0.043, 0.063);

# Keep the supplied mark discreet: at most 34% of screen width and 24% of
# screen height, never larger than the stored PNG.
logo = Image("boot-logo.png");
logo_width = logo.GetWidth();
logo_height = logo.GetHeight();
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
scale = Math.Min(Math.Min((screen_width * 0.34) / logo_width,
                          (screen_height * 0.24) / logo_height), 1);
logo_width = logo_width * scale;
logo_height = logo_height * scale;
logo = logo.Scale(logo_width, logo_height);
logo_sprite = Sprite(logo);
logo_sprite.SetPosition((screen_width - logo_width) / 2,
                        (screen_height - logo_height) / 2, 100);
EOF

    # Plymouth 24.x on Ubuntu 24.04 no longer ships the legacy theme selector.
    # Debian/Ubuntu select the graphical theme through the default.plymouth
    # alternatives group used by the initramfs hook.
    update-alternatives --install \
        /usr/share/plymouth/themes/default.plymouth default.plymouth \
        "$theme_dir/wasalight.plymouth" 200
    update-alternatives --set default.plymouth "$theme_dir/wasalight.plymouth"
    install -d -m 0755 /boot/grub
    python3 - "$selected_logo" /boot/grub/wasalight-background.png <<'PYEOF'
import gi
import sys

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf

width, height = 1920, 1080
canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, width, height)
canvas.fill(0x080B10FF)
logo = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
scale = min((width * 0.34) / logo.get_width(),
            (height * 0.24) / logo.get_height(), 1.0)
logo_width = max(1, round(logo.get_width() * scale))
logo_height = max(1, round(logo.get_height() * scale))
logo = logo.scale_simple(logo_width, logo_height, GdkPixbuf.InterpType.BILINEAR)
x = (width - logo_width) // 2
y = (height - logo_height) // 2
logo.composite(canvas, x, y, logo_width, logo_height,
               x, y, 1.0, 1.0, GdkPixbuf.InterpType.BILINEAR, 255)
canvas.savev(sys.argv[2], "png", [], [])
PYEOF
    chmod 0644 /boot/grub/wasalight-background.png
    install -d -m 0755 /etc/initramfs-tools/conf.d
    install_template /etc/initramfs-tools/conf.d/wasalight-framebuffer 0644
    install -d -m 0755 /etc/default/grub.d
    if ((early_simpledrm)); then
        install_template /etc/default/grub.d/98-wasalight-early-display.cfg 0644
        log "enabled the resolution-independent UEFI SimpleDRM boot hand-off"
    else
        rm -f /etc/default/grub.d/98-wasalight-early-display.cfg
        log "using the standard DRM boot hand-off (SimpleDRM prerequisites not met)"
    fi
    install_template /etc/default/grub.d/99-wasalight.cfg 0644
    # On the HP EliteDesk target, include Intel KMS in the initramfs so
    # Plymouth can own the display before the ordinary userspace hand-off.
    if ((intel_graphics)); then
        grep -qxF i915 /etc/initramfs-tools/modules || printf 'i915\n' >>/etc/initramfs-tools/modules
    fi
    update-grub
}

configure_overlay() {
    if ((ENABLE_PROTECTION)); then
        printf '%s\n' 'overlayroot="tmpfs:swap=0,recurse=0"' >"$OVERLAY_CONF"
    else
        printf '%s\n' 'overlayroot="disabled"' >"$OVERLAY_CONF"
    fi
    update-initramfs -u
}

record_installed_version() {
    write_file /etc/wasalight/version 0644 <<EOF
$PROJECT_VERSION
EOF
    write_file /etc/wasalight/commit 0644 <<EOF
$PROJECT_COMMIT
EOF
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o root -g root -m 0755 "$DATA_MOUNT/system"
        write_file "$DATA_MOUNT/system/installed-version" 0644 <<EOF
$PROJECT_VERSION
EOF
        write_file "$DATA_MOUNT/system/installed-commit" 0644 <<EOF
$PROJECT_COMMIT
EOF
    fi
    log "installed Wasalight version: $PROJECT_VERSION ($PROJECT_COMMIT)"
}

final_checks() {
    local writable_path
    bash -n /usr/local/libexec/wasalight-usb-mount
    bash -n /usr/local/libexec/wasalight-usb-unmount
    bash -n /usr/local/libexec/wasalight-set-mode
    bash -n /usr/local/sbin/wasalight-maintenance
    bash -n /usr/local/sbin/wasalight-protect
    bash -n /usr/local/bin/wasalight-mode-toggle
    bash -n /usr/local/bin/wasalight-status
    bash -n /usr/local/bin/magicq-session
    bash -n /usr/local/sbin/magicq-root-launcher
    bash -n /usr/local/sbin/wasalight-companion-launcher
    bash -n /usr/local/sbin/magicq-root-stop
    bash -n /usr/local/bin/magicq-start
    bash -n /usr/local/bin/magicq-stop
    bash -n /usr/local/bin/wasalight-touch
    bash -n /usr/local/bin/wasalight-vnc-password
    bash -n /usr/local/bin/wasalight-vnc-start
    bash -n /usr/local/bin/wasalight-vnc-stop
    bash -n /usr/local/bin/wasalight-vnc-control
    bash -n /usr/local/bin/wasalight-power
    bash -n /usr/local/bin/wasalight-dialog
    bash -n /usr/local/sbin/wasalight-power-control
    bash -n /usr/local/bin/wasalight-desktop-status
    bash -n /usr/local/bin/wasalight-keyboard-toggle
    bash -n /usr/local/bin/wasalight-vnc-toggle
    bash -n /usr/local/bin/wasalight-ssh-toggle
    bash -n /usr/local/sbin/wasalight-ssh-control
    bash -n /usr/local/sbin/wasalight-update
    bash -n /usr/local/libexec/wasalight-update-lib.sh
    bash -n /usr/local/bin/wasalight-update-check
    bash -n /usr/local/libexec/wasalight-update-session
    bash -n /usr/local/bin/wasalight-update-terminal
    bash -n /usr/local/bin/wasalight-terminal-tool
    bash -n /usr/local/bin/wasalight-health
    bash -n /usr/local/sbin/wasalight-health-monitor
    bash -n /usr/local/bin/wasalight-first-run
    bash -n /usr/local/bin/wasalight-magicq-usb-watch
    bash -n /usr/local/sbin/wasalight-support-bundle
    bash -n /usr/local/sbin/wasalight-data-transfer
    bash -n /usr/local/sbin/wasalight-plugin-bundle
    bash -n /usr/local/sbin/wasalight-update-snapshot
    bash -n /usr/local/sbin/wasalight-rollback
    bash -n /usr/local/bin/wasalight-rollback-ui
    bash -n /usr/local/bin/wasalight-support-bundle-terminal
    bash -n /usr/local/bin/wasalight-data-transfer-terminal
    bash -n /usr/local/bin/wasalight-plugin-bundle-terminal
    bash -n /usr/local/bin/wasalight-screen-lock
    bash -n /usr/local/sbin/wasalight-ip-scan
    bash -n /usr/local/bin/wasalight-ip-scanner
    bash -n /usr/local/bin/wasalight-artnet-monitor
    bash -n /usr/local/sbin/wasalight-app-register
    bash -n /usr/local/bin/wasalight-control
    python3 -m py_compile \
        /usr/local/bin/wasalight-plugin \
        /usr/local/sbin/wasalight-plugin-admin \
        /usr/local/libexec/wasalight-control-center.py \
        /usr/local/libexec/wasalight_control/*.py \
        /usr/local/libexec/wasalight_control/pages/*.py
    test -s /usr/local/share/locale/it/LC_MESSAGES/wasalight-control.mo
    test -s /usr/local/share/locale/en/LC_MESSAGES/wasalight-control.mo
    WASALIGHT_VERSION_OVERRIDE="$PROJECT_VERSION" /usr/local/bin/wasalight-plugin doctor
    if [[ -d /opt/companion ]]; then
        bash -n /usr/local/bin/wasalight-companion-version
        bash -n /usr/local/sbin/wasalight-companion-control
        bash -n /usr/local/sbin/wasalight-companion-backup
        bash -n /usr/local/sbin/wasalight-companion-update
        bash -n /usr/local/libexec/wasalight-companion-update-session
        bash -n /usr/local/bin/wasalight-companion-update-terminal
        bash -n /usr/local/bin/wasalight-companion-panel
        bash -n /usr/local/bin/wasalight-companion-browser
        bash -n /usr/local/bin/wasalight-falkon-profile
    command -v falkon >/dev/null 2>&1 || \
            die "Falkon Companion browser is unavailable"
        mountpoint -q /home/companion || \
            die "Companion persistent home bind is unavailable"
        mountpoint -q /etc/companion || \
            die "Companion persistent configuration bind is unavailable"
        runuser -u companion -- test -w /home/companion || \
            die "Companion persistent home is not writable by its service user"
        runuser -u companion -- test -r /etc/companion/config.yaml || \
            die "Companion persistent launch configuration is not readable"
        runuser -u "$TARGET_USER" -- test -w "$DATA_MOUNT/companion/browser" || \
            die "Companion browser profile is not writable by $TARGET_USER"
        systemd-analyze verify /etc/systemd/system/companion.service
    fi
    command -v galculator >/dev/null 2>&1 || \
        die "Wasalight calculator is unavailable"
    command -v i3lock >/dev/null 2>&1 || \
        die "Wasalight manual screen locker is unavailable"
    python3 -c 'compile(open("/usr/local/libexec/wasalight-ip-scanner.py", encoding="utf-8").read(), "/usr/local/libexec/wasalight-ip-scanner.py", "exec")'
    python3 -c 'compile(open("/usr/local/sbin/wasalight-artnet-capture", encoding="utf-8").read(), "/usr/local/sbin/wasalight-artnet-capture", "exec")'
    python3 -c 'compile(open("/usr/local/libexec/wasalight-artnet-monitor.py", encoding="utf-8").read(), "/usr/local/libexec/wasalight-artnet-monitor.py", "exec")'
    [[ -s /usr/share/plymouth/themes/wasalight/boot-logo.png ]] || \
        die "Wasalight Plymouth boot logo is unavailable"
    [[ $(readlink -f /usr/share/plymouth/themes/default.plymouth) == \
       /usr/share/plymouth/themes/wasalight/wasalight.plymouth ]] || \
        die "Wasalight is not the active Plymouth theme"
    [[ -r /etc/default/grub.d/99-wasalight.cfg ]] || \
        die "Wasalight quiet GRUB configuration is unavailable"
    [[ -r /etc/initramfs-tools/conf.d/wasalight-framebuffer ]] || \
        die "Wasalight early framebuffer configuration is unavailable"
    [[ -s /boot/grub/wasalight-background.png ]] || \
        die "Wasalight early GRUB background is unavailable"
    systemd-analyze verify \
        /etc/systemd/system/wasalight-health.service \
        /etc/systemd/system/wasalight-health.timer
    logrotate --debug /etc/wasalight/wasalight-logrotate.conf >/dev/null 2>&1
    ldconfig -p | grep -F 'libGLU.so.1' >/dev/null || \
        die "OpenGL runtime check failed: libGLU.so.1 is unavailable"
    [[ -r /usr/share/alsa/alsa.conf ]] || \
        die "MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable"
    python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf; GdkPixbuf.Pixbuf.new_from_file("/usr/local/share/icons/wasalight/hub.svg")' || \
        die "desktop SVG icon loader is unavailable"
    if [[ -d /opt/companion ]]; then
        python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf; GdkPixbuf.Pixbuf.new_from_file("/usr/local/share/icons/wasalight/companion.svg")' || \
            die "Companion desktop SVG icon is unavailable"
        python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf; GdkPixbuf.Pixbuf.new_from_file("/usr/local/share/icons/wasalight/companion-web.svg")' || \
            die "Companion Web UI SVG icon is unavailable"
    fi
    if [[ -f /opt/magicq/plugins/platforms/libqxcb.so ]]; then
        if LD_LIBRARY_PATH=/opt/magicq/lib \
           ldd /opt/magicq/plugins/platforms/libqxcb.so | grep -F 'not found'; then
            die "MagicQ Qt xcb platform plugin has unresolved runtime libraries"
        fi
    fi
    if mountpoint -q "$DATA_MOUNT"; then
        for writable_path in \
            "$TARGET_HOME/Documents/MagicQ" \
            "$TARGET_HOME/.local/share" \
            "$DATA_MOUNT/log"; do
            runuser -u "$TARGET_USER" -- test -w "$writable_path" || \
                die "MagicQ persistent path is not writable by $TARGET_USER: $writable_path"
        done
    fi
    systemd-analyze verify \
        /etc/systemd/system/wasalight-usb@.service \
        /etc/systemd/system/wasalight-logrotate.service \
        /etc/systemd/system/wasalight-logrotate.timer
    systemctl daemon-reload
    netplan generate
    [[ -r /etc/netplan/99-wasalight-networkmanager.yaml ]] || \
        die "NetworkManager Netplan renderer configuration is unavailable"
    command -v wmctrl >/dev/null || \
        die "MagicQ fullscreen control is unavailable: wmctrl is missing"
    command -v fsapfsmount >/dev/null || \
        die "read-only APFS support is unavailable: fsapfsmount is missing"
    desktop-file-validate "$TARGET_HOME"/Desktop/*.desktop
    desktop-file-validate /etc/wasalight/apps.d/*.desktop
    runuser -u "$TARGET_USER" -- test ! -w "$TARGET_HOME/Desktop" || \
        die "the appliance desktop is still writable by $TARGET_USER"
    conky --version >/dev/null || die "Wasalight desktop status is unavailable"
}
