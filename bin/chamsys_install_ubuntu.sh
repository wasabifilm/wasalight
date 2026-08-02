#!/usr/bin/env bash
# MagicQ appliance installer for Ubuntu Server 24.04 LTS (amd64).
#
# The protected SHOW mode uses Ubuntu's overlayroot with a tmpfs upper layer.
# A separate, pre-existing ext4 filesystem mounted at /data remains writable
# and stores MagicQ user data and NetworkManager connections.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TARGET_USER="chamsys"
readonly TARGET_HOME="/home/${TARGET_USER}"
readonly DATA_MOUNT="/data"
readonly USB_MOUNT="/stick"
readonly OVERLAY_CONF="/etc/overlayroot.local.conf"
readonly UPDATE_CHECKOUT="/data/system/wasalight"
readonly PACKAGE_STORE="/data/system/packages"
readonly UPDATE_REPOSITORY="https://github.com/wasabifilm/wasalight.git"

DEB_PATH=""
DATA_DEVICE=""
ENABLE_SSH=0
PURGE_CLOUD_INIT=1
ENABLE_PROTECTION=1
ENABLE_ONSCREEN_KEYBOARD=0
RESET_CHAMSYS_PASSWORD=0

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

on_error() {
    local rc=$?
    printf '[%s] ERROR: command failed at line %s (exit %s): %s\n' \
        "$SCRIPT_NAME" "${BASH_LINENO[0]:-?}" "$rc" "${BASH_COMMAND:-?}" >&2
    exit "$rc"
}
trap on_error ERR

usage() {
    cat <<'EOF'
Usage:
  sudo ./chamsys_install_ubuntu.sh [options] [magicq_package.deb]

Options:
  --data-device SPEC   Existing ext4 filesystem for /data. SPEC may be a
                       device path, UUID=..., or LABEL=.... It is never formatted.
  --with-ssh           Enable OpenSSH at boot (otherwise use the SSH button).
  --with-onscreen-keyboard
                       Install Onboard and add it to the Openbox menu.
  --reset-chamsys-password
                       Interactively replace the chamsys password. The account
                       is always an administrator; its password is never stored.
  --keep-cloud-init    Disable cloud-init services but retain the package.
  --no-protection      Configure the appliance but leave overlayroot disabled.
  -h, --help           Show this help.

For protected SHOW mode, /data must be a separate mounted ext4 filesystem.
Create and format that partition beforehand; this script deliberately never
formats disks. If it is already mounted at /data, --data-device is unnecessary.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --data-device)
                (($# >= 2)) || die "--data-device requires a value"
                DATA_DEVICE=$2
                shift 2
                ;;
            --with-ssh) ENABLE_SSH=1; shift ;;
            --with-onscreen-keyboard) ENABLE_ONSCREEN_KEYBOARD=1; shift ;;
            --reset-chamsys-password) RESET_CHAMSYS_PASSWORD=1; shift ;;
            # Earlier releases used this option to enable administrator access.
            # Administrator access is now mandatory; retain the password prompt.
            --chamsys-admin) RESET_CHAMSYS_PASSWORD=1; shift ;;
            --keep-cloud-init) PURGE_CLOUD_INIT=0; shift ;;
            # Accepted for compatibility with earlier Wasalight releases.
            --purge-cloud-init) PURGE_CLOUD_INIT=1; shift ;;
            --no-protection) ENABLE_PROTECTION=0; shift ;;
            -h|--help) usage; exit 0 ;;
            --*) die "unknown option: $1" ;;
            *)
                [[ -z "$DEB_PATH" ]] || die "only one MagicQ .deb may be supplied"
                DEB_PATH=$1
                shift
                ;;
        esac
    done
}

require_host() {
    [[ $EUID -eq 0 ]] || die "run this installer as root (sudo)"
    [[ -r /etc/os-release ]] || die "/etc/os-release is missing"
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 24.04 ]] || \
        die "this release targets Ubuntu Server 24.04 LTS; found ${PRETTY_NAME:-unknown}"
    [[ $(dpkg --print-architecture) == amd64 ]] || die "MagicQ appliance requires amd64"
    [[ $(findmnt -n -o FSTYPE /) != overlay ]] || \
        die "run the installer in MAINTENANCE mode, not through the active root overlay"

    if [[ -n "$DEB_PATH" ]]; then
        DEB_PATH=$(readlink -f -- "$DEB_PATH")
        [[ -f "$DEB_PATH" ]] || die "MagicQ package not found: $DEB_PATH"
        dpkg-deb --info "$DEB_PATH" >/dev/null || die "invalid Debian package: $DEB_PATH"
        [[ $(dpkg-deb -f "$DEB_PATH" Architecture) == amd64 ]] || \
            die "the MagicQ package is not amd64"
    fi
}

apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

is_installed() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'
}

existing_groups_csv() {
    local group
    local existing=()
    for group in "$@"; do
        if getent group "$group" >/dev/null; then
            existing+=("$group")
        else
            warn "optional system group is unavailable; skipping: $group"
        fi
    done
    ((${#existing[@]})) || return 0
    local IFS=,
    printf '%s\n' "${existing[*]}"
}

write_file() {
    local path=$1 mode=$2
    local tmp
    tmp=$(mktemp)
    cat >"$tmp"
    install -D -m "$mode" "$tmp" "$path"
    rm -f "$tmp"
}

ensure_fstab_line() {
    local marker=$1 line=$2
    if ! grep -Fqx "$line" /etc/fstab; then
        printf '\n# %s\n%s\n' "$marker" "$line" >>/etc/fstab
    fi
}

configure_data_mount() {
    install -d -m 0755 "$DATA_MOUNT"

    if [[ -n "$DATA_DEVICE" ]]; then
        if [[ "$DATA_DEVICE" == UUID=* || "$DATA_DEVICE" == LABEL=* ]]; then
            local resolved
            resolved=$(findfs "$DATA_DEVICE" 2>/dev/null || true)
            [[ -b "$resolved" ]] || die "cannot resolve data filesystem: $DATA_DEVICE"
        else
            [[ -b "$DATA_DEVICE" ]] || die "data device is not a block device: $DATA_DEVICE"
            DATA_DEVICE=$(readlink -f -- "$DATA_DEVICE")
        fi
        ensure_fstab_line "MagicQ persistent data" \
            "$DATA_DEVICE $DATA_MOUNT ext4 rw,noatime,nosuid,nodev 0 2"
        mountpoint -q "$DATA_MOUNT" || mount "$DATA_MOUNT"
    fi

    if mountpoint -q "$DATA_MOUNT"; then
        local data_fs data_source root_source
        data_fs=$(findmnt -n -o FSTYPE -M "$DATA_MOUNT")
        data_source=$(findmnt -n -o SOURCE -M "$DATA_MOUNT")
        root_source=$(findmnt -n -o SOURCE -M /)
        [[ "$data_fs" == ext4 ]] || die "/data must be ext4; found $data_fs"
        [[ "$data_source" != "$root_source" ]] || die "/data must be a separate filesystem"
    elif ((ENABLE_PROTECTION)); then
        die "protected mode requires a separate ext4 filesystem mounted at /data"
    else
        warn "/data is not a separate mount; persistent bindings and SHOW protection are skipped"
        return
    fi

    install -d -m 0750 "$DATA_MOUNT/magicq/Documents/MagicQ"
    install -d -m 0750 "$DATA_MOUNT/magicq/.local/share"
    install -d -m 0700 "$DATA_MOUNT/magicq/root-home/.config"
    install -d -m 0700 "$DATA_MOUNT/magicq/root-home/.local/share"
    install -d -m 0700 "$DATA_MOUNT/system/network"
    install -d -m 0755 "$DATA_MOUNT/system/apps.d"
    install -d -m 0750 "$DATA_MOUNT/log"
}

persist_magicq_package() {
    [[ -n $DEB_PATH ]] || return 0
    mountpoint -q "$DATA_MOUNT" || {
        warn "MagicQ package cannot be persisted because /data is unavailable"
        return 0
    }

    local source destination
    source=$DEB_PATH
    install -d -o root -g root -m 0750 "$PACKAGE_STORE"
    destination="$PACKAGE_STORE/${source##*/}"

    if [[ $(readlink -f -- "$source") != $(readlink -m -- "$destination") ]]; then
        if [[ -e $destination ]] && ! cmp -s -- "$source" "$destination"; then
            die "a different persistent MagicQ package already uses this name: $destination"
        fi
        if [[ ! -e $destination ]]; then
            install -o root -g root -m 0640 "$source" "$destination"
            cmp -s -- "$source" "$destination" || \
                die "persistent MagicQ package verification failed: $destination"
            log "MagicQ package persisted in $destination"
        fi

        # Remove only installer packages from known Wasalight working copies.
        # A package supplied from USB or another arbitrary path is never removed.
        case "$source" in
            /home/*/wasalight/packages/*.deb|/root/wasalight/packages/*.deb)
                rm -f -- "$source"
                log "removed migrated package from the non-persistent checkout: $source"
                ;;
        esac
    fi
    DEB_PATH=$destination
}

install_packages() {
    log "refreshing package metadata"
    apt-get update

    # Openbox, libinput-tools, lxrandr and other appliance components are in
    # Ubuntu's official Universe component. Standard Server installations
    # normally enable it; minimal/custom images may not.
    if ! apt-cache show openbox >/dev/null 2>&1; then
        log "enabling the official Ubuntu Universe component"
        apt_install software-properties-common
        add-apt-repository -y universe
        apt-get update
    fi

    local packages=(
        ca-certificates sudo dbus-x11 xinit x11-xserver-utils xinput libinput-tools
        xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-all
        libglu1-mesa libgl1-mesa-dri
        libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0
        libxcb-keysyms1 libxcb-randr0 libxcb-render0 libxcb-render-util0
        libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0
        libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libxcb-cursor0
        libasound2-data alsa-utils
        openbox tint2 pcmanfm lxterminal lxrandr lxtask x11vnc procps wmctrl x11-utils
        conky-all zenity libglib2.0-bin desktop-file-utils librsvg2-common
        python3 python3-gi gir1.2-gtk-3.0 arp-scan iproute2
        network-manager network-manager-gnome wpasupplicant policykit-1 policykit-1-gnome
        overlayroot initramfs-tools plymouth plymouth-themes file chrony
        exfatprogs ntfs-3g dosfstools util-linux udev logrotate openssh-server git
    )
    ((ENABLE_ONSCREEN_KEYBOARD)) && packages+=(onboard)
    apt_install "${packages[@]}"

    systemctl enable NetworkManager.service chrony.service
    if ((ENABLE_SSH)); then
        systemctl enable ssh.service
    else
        systemctl disable --now ssh.service 2>/dev/null || true
    fi
}

configure_networkmanager() {
    # Ubuntu Server's installer normally leaves Netplan on systemd-networkd.
    # In that state nm-connection-editor opens but lists no usable devices.
    # A late Netplan file changes only the renderer, preserving the interface,
    # DHCP, static address, route and DNS definitions created during install.
    write_file /etc/netplan/99-wasalight-networkmanager.yaml 0600 <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF

    netplan generate
    systemctl enable NetworkManager.service
    netplan apply
    systemctl restart NetworkManager.service

    if nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | \
       grep -E '^[^:]+:(ethernet|wifi):unmanaged$' >/dev/null; then
        warn "a physical network interface is still unmanaged after applying Netplan"
    fi
}

configure_user() {
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
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/magicq-touch"

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

        mountpoint -q "$TARGET_HOME/Documents/MagicQ" || mount "$TARGET_HOME/Documents/MagicQ"
        mountpoint -q "$TARGET_HOME/.local/share" || mount "$TARGET_HOME/.local/share"
        install -d -o root -g root -m 0700 \
            /root/.config /root/.local/share /root/Documents/MagicQ
        if ! mountpoint -q /root/.config; then
            cp -an /root/.config/. "$DATA_MOUNT/magicq/root-home/.config/"
            mount /root/.config
        fi
        if ! mountpoint -q /root/.local/share; then
            cp -an /root/.local/share/. \
                "$DATA_MOUNT/magicq/root-home/.local/share/"
            mount /root/.local/share
        fi
        if ! mountpoint -q /root/Documents/MagicQ; then
            cp -an /root/Documents/MagicQ/. \
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

    if [[ ! -e "$TARGET_HOME/.config/magicq-touch/config" ]]; then
        write_file "$TARGET_HOME/.config/magicq-touch/config" 0600 <<'EOF'
# Fallback used only when /data/system/touchscreen is unavailable.
MODE=auto
DEVICE=
OUTPUT=
ROTATION=normal
EOF
    fi

    write_file "$TARGET_HOME/.bash_profile" 0644 <<'EOF'
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec startx -- -keeptty vt1
fi
EOF

    chown "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.magicq_init.sh" "$TARGET_HOME/.bash_profile" \
        "$TARGET_HOME/.config/magicq-touch/config"
}

configure_touchscreen() {
    write_file /usr/local/bin/magicq-touch 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly DATA_CONFIG=/data/system/touchscreen/config
readonly FALLBACK_CONFIG=/home/chamsys/.config/magicq-touch/config
CONFIG=$FALLBACK_CONFIG
[[ -e $DATA_CONFIG || -d ${DATA_CONFIG%/*} ]] && CONFIG=$DATA_CONFIG
[[ -n ${MAGICQ_TOUCH_CONFIG:-} ]] && CONFIG=$MAGICQ_TOUCH_CONFIG

MODE=auto
DEVICE=
OUTPUT=
ROTATION=normal
TOUCH_IDS=()
TOUCH_NAMES=()
TOUCH_NODES=()
TOUCH_KEYS=()
OUTPUTS=()
RESOLVED_ID=
RESOLVED_DEVICE=
RESOLVED_OUTPUT=

warn() { printf 'Touchscreen: %s\n' "$*" >&2; }

usage() {
    cat <<'EOT'
Usage:
  magicq-touch-status
  magicq-touch-config list
  magicq-touch-config auto [normal|right|inverted|left]
  magicq-touch-config set DEVICE OUTPUT [normal|right|inverted|left]
  magicq-touch-config disable
  magicq-touch-apply
  magicq-touch-watch

Names containing spaces must be quoted. Configuration is persistent under
/data when that filesystem is available. "auto" acts only when exactly one
touchscreen and one connected output are detected.
EOT
}

prepare_x() {
    export DISPLAY=${DISPLAY:-:0}
    export XAUTHORITY=${XAUTHORITY:-/home/chamsys/.Xauthority}
    xset q >/dev/null 2>&1
}

load_config() {
    [[ -r $CONFIG ]] || return 0
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            MODE) MODE=$value ;;
            DEVICE) DEVICE=$value ;;
            OUTPUT) OUTPUT=$value ;;
            ROTATION) ROTATION=$value ;;
        esac
    done <"$CONFIG"
}

valid_rotation() {
    case "$1" in normal|right|inverted|left) return 0 ;; *) return 1 ;; esac
}

detect_hardware() {
    TOUCH_IDS=()
    TOUCH_NAMES=()
    TOUCH_NODES=()
    TOUCH_KEYS=()
    OUTPUTS=()

    local id props node name udev_props key
    while IFS= read -r id; do
        [[ $id =~ ^[0-9]+$ ]] || continue
        props=$(xinput list-props "$id" 2>/dev/null) || continue
        node=$(sed -n 's/^[[:space:]]*Device Node ([0-9][0-9]*):[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$props")
        [[ -n $node && -e $node ]] || continue
        udev_props=$(udevadm info --query=property --name="$node" 2>/dev/null) || continue
        grep -qx 'ID_INPUT_TOUCHSCREEN=1' <<<"$udev_props" || continue
        name=$(xinput list --name-only "$id" 2>/dev/null) || continue
        key=$(sed -n 's/^ID_SERIAL_SHORT=//p' <<<"$udev_props" | head -n1)
        [[ -n $key ]] || key=$(sed -n 's/^ID_PATH=//p' <<<"$udev_props" | head -n1)
        [[ -n $key ]] || key=$(sed -n 's/^ID_SERIAL=//p' <<<"$udev_props" | head -n1)
        [[ -n $key ]] || key=$name
        TOUCH_IDS+=("$id")
        TOUCH_NAMES+=("$name")
        TOUCH_NODES+=("$node")
        TOUCH_KEYS+=("$key")
    done < <(xinput --list --short | sed -n 's/.*id=\([0-9][0-9]*\).*/\1/p' | sort -nu)

    while IFS= read -r name; do
        [[ -n $name ]] && OUTPUTS+=("$name")
    done < <(xrandr --query | awk '$2 == "connected" {print $1}')
}

find_touch_id() {
    local wanted=$1 i found=
    for i in "${!TOUCH_NAMES[@]}"; do
        if [[ ${TOUCH_NAMES[$i]} == "$wanted" || ${TOUCH_KEYS[$i]} == "$wanted" ]]; then
            [[ -z $found ]] || return 2
            found=${TOUCH_IDS[$i]}
        fi
    done
    [[ -n $found ]] || return 1
    printf '%s\n' "$found"
}

output_exists() {
    local wanted=$1 item
    for item in "${OUTPUTS[@]}"; do
        [[ $item == "$wanted" ]] && return 0
    done
    return 1
}

write_config() {
    local mode=$1 device=$2 output=$3 rotation=$4 tmp
    [[ $device != *$'\n'* && $output != *$'\n'* ]] || {
        warn 'device and output names cannot contain newlines'; return 2;
    }
    install -d -m 0750 "${CONFIG%/*}"
    tmp=$(mktemp "${CONFIG}.XXXXXX")
    chmod 0600 "$tmp"
    printf 'MODE=%s\nDEVICE=%s\nOUTPUT=%s\nROTATION=%s\n' \
        "$mode" "$device" "$output" "$rotation" >"$tmp"
    mv -f "$tmp" "$CONFIG"
}

rotation_matrix() {
    case "$1" in
        normal)   printf '1 0 0 0 1 0 0 0 1\n' ;;
        right)    printf '0 -1 1 1 0 0 0 0 1\n' ;;
        inverted) printf '%s\n' '-1 0 1 0 -1 1 0 0 1' ;;
        left)     printf '0 1 0 -1 0 1 0 0 1\n' ;;
    esac
}

calibrated_matrix() {
    local id=$1 rotation=$2 props default rotate
    props=$(xinput list-props "$id")
    default=$(sed -n \
        's/^[[:space:]]*libinput Calibration Matrix Default ([0-9][0-9]*):[[:space:]]*//p' \
        <<<"$props" | head -n1 | tr ',' ' ')
    [[ -n $default ]] || default='1 0 0 0 1 0 0 0 1'
    rotate=$(rotation_matrix "$rotation")
    awk -v a="$rotate" -v b="$default" 'BEGIN {
        split(a, A, " "); split(b, B, " ");
        for (row = 0; row < 3; row++)
            for (col = 0; col < 3; col++) {
                value = 0;
                for (k = 0; k < 3; k++)
                    value += A[row * 3 + k + 1] * B[k * 3 + col + 1];
                printf "%s%.8g", (row || col ? " " : ""), value;
            }
        print "";
    }'
}

resolve_target() {
    local id
    RESOLVED_ID=
    RESOLVED_DEVICE=
    RESOLVED_OUTPUT=
    case "$MODE" in
        disabled) return 1 ;;
        auto)
            ((${#TOUCH_IDS[@]} == 1)) || {
                warn "automatic configuration skipped: ${#TOUCH_IDS[@]} touchscreens detected";
                return 2;
            }
            ((${#OUTPUTS[@]} == 1)) || {
                warn "automatic configuration skipped: ${#OUTPUTS[@]} outputs connected";
                return 2;
            }
            RESOLVED_ID=${TOUCH_IDS[0]}
            RESOLVED_DEVICE=${TOUCH_NAMES[0]}
            RESOLVED_OUTPUT=${OUTPUTS[0]}
            ;;
        manual)
            id=$(find_touch_id "$DEVICE") || {
                warn "configured touchscreen not found or name is ambiguous: $DEVICE";
                return 2;
            }
            output_exists "$OUTPUT" || {
                warn "configured output is not connected: $OUTPUT";
                return 2;
            }
            RESOLVED_ID=$id
            for id in "${!TOUCH_IDS[@]}"; do
                if [[ ${TOUCH_IDS[$id]} == "$RESOLVED_ID" ]]; then
                    RESOLVED_DEVICE=${TOUCH_NAMES[$id]}
                    break
                fi
            done
            RESOLVED_OUTPUT=$OUTPUT
            ;;
        *) warn "invalid mode in $CONFIG: $MODE"; return 2 ;;
    esac
}

apply_config() {
    load_config
    valid_rotation "$ROTATION" || { warn "invalid rotation in $CONFIG: $ROTATION"; return 2; }
    [[ $MODE != disabled ]] || return 0
    prepare_x || { warn 'Xorg session is not available'; return 0; }
    detect_hardware
    local matrix
    local -a matrix_values
    resolve_target || return 0
    xinput map-to-output "$RESOLVED_ID" "$RESOLVED_OUTPUT"

    if xinput list-props "$RESOLVED_ID" | grep -Fq 'libinput Calibration Matrix'; then
        matrix=$(calibrated_matrix "$RESOLVED_ID" "$ROTATION")
        IFS=' ' read -r -a matrix_values <<<"$matrix"
        xinput set-prop "$RESOLVED_ID" 'libinput Calibration Matrix' "${matrix_values[@]}"
    elif [[ $ROTATION != normal ]]; then
        warn "rotation skipped: $RESOLVED_DEVICE has no libinput calibration matrix"
    fi
    logger -t magicq-touch \
        "Mapped $RESOLVED_DEVICE to $RESOLVED_OUTPUT with rotation $ROTATION"
}

watch_hardware() {
    local signature previous=
    while :; do
        if prepare_x; then
            signature=$( {
                xinput --list --short 2>/dev/null || true
                xrandr --query 2>/dev/null | awk '$2 == "connected" {print $1, $3}' || true
                stat -c '%Y:%s' "$CONFIG" 2>/dev/null || true
            } )
            if [[ $signature != "$previous" ]]; then
                apply_config || true
                previous=$signature
            fi
        fi
        sleep 3
    done
}

show_status() {
    load_config
    if ! prepare_x; then
        if [[ ${1:-} == --summary ]]; then
            printf 'X session unavailable; configured mode: %s\n' "$MODE"
        else
            printf 'Touchscreen support\nX SESSION: unavailable\nCONFIG:    %s\nMODE:      %s\n' \
                "$CONFIG" "$MODE"
        fi
        return 0
    fi
    detect_hardware

    local readiness=disabled i
    if [[ $MODE != disabled ]]; then
        if resolve_target 2>/dev/null; then readiness=ready; else readiness=attention; fi
    fi
    if [[ ${1:-} == --summary ]]; then
        printf '%s detected; mode: %s; target: %s\n' \
            "${#TOUCH_IDS[@]}" "$MODE" "$readiness"
        return 0
    fi

    printf 'Touchscreen support\n'
    printf 'X SESSION: available (%s)\n' "$DISPLAY"
    printf 'CONFIG:    %s\n' "$CONFIG"
    printf 'MODE:      %s\n' "$MODE"
    printf 'ROTATION:  %s\n' "$ROTATION"
    [[ $MODE == manual ]] && printf 'TARGET:    %s -> %s\n' "$DEVICE" "$OUTPUT"
    printf 'STATE:     %s\n' "$readiness"
    printf 'OUTPUTS (%s):\n' "${#OUTPUTS[@]}"
    for i in "${!OUTPUTS[@]}"; do printf '  - %s\n' "${OUTPUTS[$i]}"; done
    printf 'TOUCHSCREENS (%s):\n' "${#TOUCH_IDS[@]}"
    for i in "${!TOUCH_IDS[@]}"; do
        printf '  - %s [key=%s, id=%s, node=%s]\n' \
            "${TOUCH_NAMES[$i]}" "${TOUCH_KEYS[$i]}" \
            "${TOUCH_IDS[$i]}" "${TOUCH_NODES[$i]}"
    done
}

configure() {
    local action=${1:-list} rotation id
    prepare_x || { warn 'run this command inside the graphical session'; return 1; }
    detect_hardware
    case "$action" in
        list) show_status ;;
        auto)
            rotation=${2:-normal}
            valid_rotation "$rotation" || { usage >&2; return 2; }
            write_config auto '' '' "$rotation"
            apply_config
            ;;
        set)
            (($# >= 3 && $# <= 4)) || { usage >&2; return 2; }
            rotation=${4:-normal}
            valid_rotation "$rotation" || { usage >&2; return 2; }
            id=$(find_touch_id "$2") || {
                warn "touchscreen not found or name is ambiguous: $2"; return 1;
            }
            output_exists "$3" || { warn "output is not connected: $3"; return 1; }
            write_config manual "$2" "$3" "$rotation"
            apply_config
            ;;
        disable)
            write_config disabled '' '' normal
            ;;
        *) usage >&2; return 2 ;;
    esac
}

case "${0##*/}" in
    magicq-touch-status) show_status "${1:-}" ;;
    magicq-touch-apply) apply_config ;;
    magicq-touch-watch) watch_hardware ;;
    magicq-touch-config) configure "$@" ;;
    *)
        case "${1:-}" in
            status) shift; show_status "${1:-}" ;;
            apply) shift; apply_config "$@" ;;
            watch) shift; watch_hardware ;;
            config|configure) shift; configure "$@" ;;
            *) usage; exit 2 ;;
        esac
        ;;
esac
EOF

    ln -sfn magicq-touch /usr/local/bin/magicq-touch-status
    ln -sfn magicq-touch /usr/local/bin/magicq-touch-apply
    ln -sfn magicq-touch /usr/local/bin/magicq-touch-watch
    ln -sfn magicq-touch /usr/local/bin/magicq-touch-config
}

configure_vnc() {
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
        "$TARGET_HOME/.config/wasalight-vnc"
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0700 \
            "$DATA_MOUNT/system/vnc"
    fi

    write_file /usr/local/bin/magicq-vnc-password 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}

config_dir=${MAGICQ_VNC_CONFIG_DIR:-/home/chamsys/.config/wasalight-vnc}
if [[ -z ${MAGICQ_VNC_CONFIG_DIR:-} && -d /data/system/vnc && -w /data/system/vnc ]]; then
    config_dir=/data/system/vnc
fi
install -d -m 0700 "$config_dir"
password_file="$config_dir/passwd"

echo "Set the temporary VNC access password. It is independent of the Linux password."
x11vnc -storepasswd "$password_file"
chmod 0600 "$password_file"
echo "VNC password stored in $password_file"
EOF

    write_file /usr/local/bin/magicq-vnc-start 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}

case "${1:---lan}" in
    --lan) local_only=0 ;;
    --localhost) local_only=1 ;;
    -h|--help)
        cat <<'EOT'
Usage: magicq-vnc-start [--lan|--localhost]

  --lan        Listen on the local network (default; VNC traffic is not encrypted).
  --localhost  Accept only local connections, normally through an SSH tunnel.
EOT
        exit 0
        ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-/home/chamsys/.Xauthority}
xset q >/dev/null 2>&1 || {
    echo "The chamsys Xorg session is not available on $DISPLAY." >&2
    exit 1
}

config_dir=${MAGICQ_VNC_CONFIG_DIR:-/home/chamsys/.config/wasalight-vnc}
if [[ -z ${MAGICQ_VNC_CONFIG_DIR:-} && -d /data/system/vnc && -w /data/system/vnc ]]; then
    config_dir=/data/system/vnc
fi
password_file="$config_dir/passwd"
if [[ ! -r $password_file ]]; then
    /usr/local/bin/magicq-vnc-password
fi

runtime_dir=${MAGICQ_VNC_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}
[[ -d $runtime_dir && -w $runtime_dir ]] || runtime_dir=/tmp
pid_file="$runtime_dir/wasalight-x11vnc.pid"
log_file="$runtime_dir/wasalight-x11vnc.log"

if [[ -r $pid_file ]]; then
    old_pid=$(<"$pid_file")
    if [[ $old_pid =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null && \
       [[ $(ps -p "$old_pid" -o comm= 2>/dev/null | tr -d ' ') == x11vnc ]]; then
        echo "VNC is already running (PID $old_pid)."
        exit 0
    fi
    rm -f "$pid_file"
fi

args=(
    x11vnc
    -display "$DISPLAY"
    -auth "$XAUTHORITY"
    -rfbauth "$password_file"
    -rfbport 5900
    -forever
    -shared
    -noxdamage
)
((local_only)) && args+=(-localhost)

nohup "${args[@]}" >"$log_file" 2>&1 &
vnc_pid=$!
printf '%s\n' "$vnc_pid" >"$pid_file"
sleep 1
if ! kill -0 "$vnc_pid" 2>/dev/null; then
    echo "VNC failed to start. Log: $log_file" >&2
    tail -n 40 "$log_file" >&2 || true
    rm -f "$pid_file"
    exit 1
fi

if ((local_only)); then
    echo "VNC is listening only on localhost:5900 (PID $vnc_pid)."
    echo "Use an SSH tunnel, then connect the viewer to vnc://localhost:5900."
else
    ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "VNC started (PID $vnc_pid). Connect to vnc://${ip_address:-SERVER_IP}:5900"
    echo "WARNING: classic VNC traffic is not encrypted; use only on a trusted LAN."
fi
echo "Log: $log_file"
echo "Stop with: magicq-vnc-stop"
EOF

    write_file /usr/local/bin/magicq-vnc-stop 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}

runtime_dir=${MAGICQ_VNC_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}
[[ -d $runtime_dir && -w $runtime_dir ]] || runtime_dir=/tmp
pid_file="$runtime_dir/wasalight-x11vnc.pid"
[[ -r $pid_file ]] || { echo "Managed VNC server is not running."; exit 0; }
vnc_pid=$(<"$pid_file")

if [[ $vnc_pid =~ ^[0-9]+$ ]] && kill -0 "$vnc_pid" 2>/dev/null && \
   [[ $(ps -p "$vnc_pid" -o comm= 2>/dev/null | tr -d ' ') == x11vnc ]]; then
    kill "$vnc_pid"
    for _ in 1 2 3 4 5; do
        kill -0 "$vnc_pid" 2>/dev/null || break
        sleep 1
    done
    echo "VNC stopped."
else
    echo "Removing stale VNC state; no managed x11vnc process was found."
fi
rm -f "$pid_file"
EOF

    write_file /usr/local/bin/wasalight-vnc-toggle 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}

if pgrep -u chamsys -x x11vnc >/dev/null 2>&1; then
    zenity --question --width=460 --title="VNC · Wasalight" \
        --text="<big><b>VNC è attivo.</b></big>\n\nFermare la condivisione della sessione corrente?" \
        --ok-label="Stop VNC" --cancel-label="Cancel" || exit 0
    output=$(/usr/local/bin/magicq-vnc-stop 2>&1) || {
        zenity --error --width=460 --title="VNC · Wasalight" --text="$output"
        exit 1
    }
    zenity --info --width=420 --title="VNC · Wasalight" --text="$output"
    exit 0
fi

password_file=/home/chamsys/.config/wasalight-vnc/passwd
[[ ! -r /data/system/vnc/passwd ]] || password_file=/data/system/vnc/passwd
if [[ ! -r $password_file ]]; then
    # x11vnc deliberately reads the new password from a terminal so it never
    # appears in a process argument, temporary file or Wasalight log.
    lxterminal --title="VNC password · Wasalight" -e bash -lc \
        '/usr/local/bin/magicq-vnc-start; rc=$?; echo; echo "Premere Invio per chiudere."; read -r _; exit "$rc"'
    exit 0
fi

output=$(/usr/local/bin/magicq-vnc-start 2>&1) || {
    zenity --error --width=520 --title="VNC · Wasalight" --text="$output"
    exit 1
}
ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
zenity --info --width=500 --title="VNC · Wasalight" \
    --text="<big><b>VNC attivo nella sessione corrente</b></big>\n\nIndirizzo: vnc://${ip_address:-SERVER_IP}:5900\n\nUsare soltanto su una rete locale fidata."
EOF
}

configure_ssh() {
    write_file /usr/local/sbin/wasalight-ssh-control 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || {
    echo "Wasalight SSH control must be run through sudo." >&2
    exit 1
}

case ${1:-} in
    start)
        systemctl start ssh.service
        systemctl is-active --quiet ssh.service
        echo "SSH started."
        ;;
    stop)
        systemctl stop ssh.service
        echo "SSH stopped."
        ;;
    *) echo "Usage: wasalight-ssh-control start|stop" >&2; exit 2 ;;
esac
EOF

    write_file /usr/local/bin/wasalight-ssh-toggle 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}

ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
if systemctl is-active --quiet ssh.service; then
    next_boot=""
    if systemctl is-enabled --quiet ssh.service; then
        next_boot="\n\nNota: SSH è configurato per riattivarsi al prossimo avvio."
    fi
    zenity --question --width=500 --title="SSH · Wasalight" \
        --text="<big><b>SSH è attivo.</b></big>\n\nIndirizzo: ssh://chamsys@${ip_address:-SERVER_IP}:22${next_boot}\n\nFermare ora l’accesso SSH?" \
        --ok-label="Stop SSH" --cancel-label="Cancel" || exit 0
    output=$(sudo -n /usr/local/sbin/wasalight-ssh-control stop 2>&1) || {
        zenity --error --width=500 --title="SSH · Wasalight" --text="$output"
        exit 1
    }
    zenity --info --width=420 --title="SSH · Wasalight" --text="$output"
    exit 0
fi

zenity --question --width=520 --title="SSH · Wasalight" \
    --text="<big><b>Attivare SSH?</b></big>\n\nL’accesso userà l’utente chamsys e la sua password Linux. Attivarlo soltanto su una rete fidata." \
    --ok-label="Start SSH" --cancel-label="Cancel" || exit 0
output=$(sudo -n /usr/local/sbin/wasalight-ssh-control start 2>&1) || {
    zenity --error --width=500 --title="SSH · Wasalight" --text="$output"
    exit 1
}
ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
zenity --info --width=500 --title="SSH · Wasalight" \
    --text="<big><b>SSH attivo</b></big>\n\nIndirizzo: ssh://chamsys@${ip_address:-SERVER_IP}:22\nUtente: chamsys\nPassword: la password Linux di chamsys"
EOF
}

configure_update() {
    write_file /usr/local/sbin/wasalight-update 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

readonly repository=https://github.com/wasabifilm/wasalight.git
readonly checkout=/data/system/wasalight
readonly package_store=/data/system/packages
readonly log_file=/data/log/wasalight-update.log

protect=0
code_only=0
reboot_after=0
ssh_mode=preserve

usage() {
    cat <<'EOT'
Usage: sudo wasalight-update [options]

Scarica e verifica l'ultima versione di Wasalight, conserva il pacchetto
MagicQ e aggiorna la macchina in modalità MAINTENANCE.

Opzioni:
  --protect       Prepara SHOW / PROTECTED per il prossimo avvio.
  --code-only     Scarica e verifica il codice senza installarlo.
  --reboot        Riavvia automaticamente dopo un aggiornamento riuscito.
  --with-ssh      Mantiene SSH attivo automaticamente dopo il riavvio.
  --without-ssh   Mantiene SSH spento all'avvio; il pulsante resta disponibile.
  -h, --help      Mostra questo aiuto.
EOT
}

while (($#)); do
    case $1 in
        --protect) protect=1 ;;
        --code-only) code_only=1 ;;
        --reboot) reboot_after=1 ;;
        --with-ssh) ssh_mode=enabled ;;
        --without-ssh) ssh_mode=disabled ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Opzione sconosciuta: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if ((code_only && reboot_after)); then
    echo "--code-only e --reboot non possono essere usati insieme." >&2
    exit 2
fi

[[ $EUID -eq 0 ]] || { echo "Esegui con: sudo wasalight-update" >&2; exit 1; }
[[ $(findmnt -n -o FSTYPE / 2>/dev/null) != overlay ]] || {
    echo "Serve la modalità MAINTENANCE. Esegui sudo magicq-maintenance e riavvia." >&2
    exit 1
}
mountpoint -q /data || { echo "/data non è montata: aggiornamento interrotto." >&2; exit 1; }
install -d -o root -g root -m 0755 /data/system
install -d -o chamsys -g chamsys -m 0750 /data/log
install -d -o root -g root -m 0750 "$package_store"
touch "$log_file"
chown root:adm "$log_file" 2>/dev/null || chown root:root "$log_file"
chmod 0640 "$log_file"
exec > >(tee -a "$log_file") 2>&1

step() { printf '\n==> %s\n' "$*"; }
update_failed() {
    local rc=$?
    trap - ERR
    printf '\nAGGIORNAMENTO INTERROTTO (errore %d).\n' "$rc" >&2
    echo "La macchina non verrà riavviata. Dettagli: $log_file" >&2
    exit "$rc"
}
trap update_failed ERR

printf '\n========================================\n'
printf '       WASALIGHT · AGGIORNAMENTO\n'
printf '========================================\n'
echo "Avvio: $(date --iso-8601=seconds)"
echo "Log:   $log_file"

migrate_package() {
    local source=$1 destination
    [[ -f $source ]] || return 0
    dpkg-deb --info "$source" >/dev/null 2>&1 || {
        echo "Ignoro un pacchetto Debian non valido: $source" >&2
        return 0
    }
    [[ $(dpkg-deb -f "$source" Architecture) == amd64 ]] || {
        echo "Ignoro un pacchetto non amd64: $source" >&2
        return 0
    }
    destination="$package_store/${source##*/}"
    [[ $(readlink -f -- "$source") != $(readlink -m -- "$destination") ]] || return 0
    if [[ -e $destination ]] && ! cmp -s -- "$source" "$destination"; then
        echo "Esiste già un pacchetto diverso con lo stesso nome: $destination" >&2
        return 1
    fi
    if [[ ! -e $destination ]]; then
        install -o root -g root -m 0640 "$source" "$destination"
        cmp -s -- "$source" "$destination" || {
            echo "Verifica della copia del pacchetto non riuscita: $destination" >&2
            return 1
        }
    fi
    rm -f -- "$source"
    echo "Pacchetto MagicQ conservato in $destination"
}

step "1/4 · Controllo dei pacchetti MagicQ"
while IFS= read -r -d '' legacy_package; do
    migrate_package "$legacy_package"
done < <(find /home /root -maxdepth 4 -type f \
    -path '*/wasalight/packages/*.deb' -print0 2>/dev/null)

if [[ -e $checkout && ! -d $checkout/.git ]]; then
    echo "Il percorso aggiornamenti esiste ma non è un repository Git: $checkout" >&2
    exit 1
fi

step "2/4 · Download dell'ultima versione"
if [[ -d $checkout/.git ]]; then
    if ! git -C "$checkout" diff --quiet || ! git -C "$checkout" diff --cached --quiet; then
        echo "Il repository persistente contiene modifiche locali: aggiornamento interrotto." >&2
        exit 1
    fi
    git -C "$checkout" remote set-url origin "$repository"
    git -C "$checkout" fetch origin main
    git -C "$checkout" merge --ff-only FETCH_HEAD
else
    temporary_checkout="${checkout}.new.$$"
    cleanup() { rm -rf -- "$temporary_checkout"; }
    trap cleanup EXIT
    git clone --branch main "$repository" "$temporary_checkout"
    mv "$temporary_checkout" "$checkout"
    trap - EXIT
fi

step "3/4 · Verifica del progetto scaricato"
"$checkout/tests/verify-project.sh"
echo "Codice verificato e pronto in $checkout"
if ((code_only)); then
    echo
    echo "Aggiornamento del codice completato. Nessuna modifica applicata al sistema."
    exit 0
fi

installer_args=()
((protect)) || installer_args+=(--no-protection)
if [[ $ssh_mode == enabled ]] || \
   [[ $ssh_mode == preserve ]] && systemctl is-enabled --quiet ssh.service; then
    installer_args+=(--with-ssh)
fi
command -v onboard >/dev/null 2>&1 && installer_args+=(--with-onscreen-keyboard)

mapfile -t packages < <(find "$package_store" -maxdepth 1 -type f -name '*.deb' -print | sort -V)
if ((${#packages[@]})); then
    selected_package=${packages[-1]}
    echo "Pacchetto MagicQ selezionato: $selected_package"
    installer_args+=("$selected_package")
else
    echo "ATTENZIONE: nessun pacchetto MagicQ trovato in $package_store" >&2
fi

step "4/4 · Installazione della configurazione Wasalight"
"$checkout/install.sh" "${installer_args[@]}"

trap - ERR
printf '\n========================================\n'
printf '       AGGIORNAMENTO COMPLETATO\n'
printf '========================================\n'
echo "Fine: $(date --iso-8601=seconds)"
if ((protect)); then
    echo "Prossimo avvio: SHOW / PROTECTED"
else
    echo "Prossimo avvio: MAINTENANCE"
fi

if ((reboot_after)); then
    echo "Riavvio in corso…"
    sync
    systemctl reboot
else
    echo "Riavvia per rendere effettive tutte le modifiche."
fi
EOF

    write_file /usr/local/libexec/wasalight-update-session 0755 <<'EOF'
#!/usr/bin/env bash
set -u

clear
printf '\n  WASALIGHT UPDATE\n'
printf '  Scarico, verifico e installo l’ultima versione.\n'
printf '  La password richiesta è quella Linux di chamsys.\n\n'

sudo /usr/local/sbin/wasalight-update
rc=$?
if ((rc == 0)); then
    echo
    echo "Aggiornamento completato correttamente."
    if zenity --question --width=520 --title="Wasalight aggiornato" \
        --text="<big><b>Aggiornamento completato.</b></big>\n\nRiavviare ora per applicare la nuova configurazione?" \
        --ok-label="Riavvia ora" --cancel-label="Più tardi"; then
        echo "Riavvio in corso…"
        sudo -n /usr/local/sbin/wasalight-power-control reboot
        exit $?
    fi
    zenity --info --width=500 --title="Wasalight aggiornato" \
        --text="Aggiornamento installato.\n\nRicordati di riavviare prima del prossimo utilizzo." \
        --ok-label="Chiudi"
    exit 0
fi

echo
echo "Aggiornamento non completato. La macchina non verrà riavviata."
zenity --error --width=560 --title="Aggiornamento non riuscito" \
    --text="<big><b>Wasalight non è stato aggiornato.</b></big>\n\nLa macchina non verrà riavviata.\nControlla: /data/log/wasalight-update.log" \
    --ok-label="Chiudi" 2>/dev/null || true
exit "$rc"
EOF

    write_file /usr/local/bin/wasalight-update-terminal 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exec lxterminal --title="Wasalight Update" -e /usr/local/libexec/wasalight-update-session
EOF

    if mountpoint -q "$DATA_MOUNT" && [[ ! -d $UPDATE_CHECKOUT/.git ]]; then
        log "initializing the persistent Wasalight update checkout"
        /usr/local/sbin/wasalight-update --code-only || \
            warn "persistent update checkout could not be initialized; retry later with sudo wasalight-update --code-only"
    fi
}

configure_graphical_session() {
    write_file /etc/X11/Xwrapper.config 0644 <<'EOF'
allowed_users=console
needs_root_rights=yes
EOF

    write_file "$TARGET_HOME/.xinitrc" 0755 <<'EOF'
#!/bin/sh
exec dbus-run-session -- openbox-session
EOF

    # Start from Ubuntu's complete Openbox configuration, changing only the
    # appliance theme and title-button layout. NLC keeps a large close target
    # and removes tiny minimise/maximise controls that are awkward on touch.
    install -m 0644 /etc/xdg/openbox/rc.xml "$TARGET_HOME/.config/openbox/rc.xml"
    sed -i \
        -e '0,/<name>.*<\/name>/s//<name>Wasalight<\/name>/' \
        -e 's#<titleLayout>.*</titleLayout>#<titleLayout>NLC</titleLayout>#' \
        "$TARGET_HOME/.config/openbox/rc.xml"

    install -d -m 0755 /usr/share/themes/Wasalight/openbox-3
    write_file /usr/share/themes/Wasalight/openbox-3/themerc 0644 <<'EOF'
# Wasalight: large touch title bar, dark in both active and inactive states.
window.active.title.bg: flat
window.active.title.bg.color: #11151b
window.active.label.bg: parentrelative
window.active.label.text.color: #f0f3f6
window.active.button.unpressed.bg: flat
window.active.button.unpressed.bg.color: #232933
window.active.button.unpressed.image.color: #f0f3f6
window.active.button.hover.bg: flat
window.active.button.hover.bg.color: #b4232c
window.active.button.hover.image.color: #ffffff
window.active.button.pressed.bg: flat
window.active.button.pressed.bg.color: #7d1920
window.active.button.pressed.image.color: #ffffff
window.active.border.color: #30363d
window.active.client.color: #11151b

window.inactive.title.bg: flat
window.inactive.title.bg.color: #0b0e12
window.inactive.label.bg: parentrelative
window.inactive.label.text.color: #9da7b3
window.inactive.button.unpressed.bg: flat
window.inactive.button.unpressed.bg.color: #171b22
window.inactive.button.unpressed.image.color: #c9d1d9
window.inactive.button.hover.bg: flat
window.inactive.button.hover.bg.color: #6e2026
window.inactive.button.hover.image.color: #ffffff
window.inactive.button.pressed.bg: flat
window.inactive.button.pressed.bg.color: #50171b
window.inactive.button.pressed.image.color: #ffffff
window.inactive.border.color: #20252d
window.inactive.client.color: #0b0e12

window.label.text.justify: left
padding.width: 10
padding.height: 9
border.width: 1
menu.items.active.bg: flat
menu.items.active.bg.color: #30363d
menu.items.active.text.color: #ffffff
menu.items.text.color: #d0d7de
menu.items.bg.color: #11151b
menu.title.bg.color: #080b10
menu.title.text.color: #ffffff
EOF

    write_file /usr/share/themes/Wasalight/openbox-3/close.xbm 0644 <<'EOF'
#define close_width 16
#define close_height 16
static unsigned char close_bits[] = {
  0x03,0xc0, 0x07,0xe0, 0x0e,0x70, 0x1c,0x38,
  0x38,0x1c, 0x70,0x0e, 0xe0,0x07, 0xc0,0x03,
  0xc0,0x03, 0xe0,0x07, 0x70,0x0e, 0x38,0x1c,
  0x1c,0x38, 0x0e,0x70, 0x07,0xe0, 0x03,0xc0 };
EOF

    write_file "$TARGET_HOME/.config/pcmanfm/default/desktop-items-0.conf" 0644 <<'EOF'
[*]
wallpaper_mode=color
wallpaper_common=1
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 14
desktop_icon_size=64
show_wm_menu=1
sort=name;ascending;
show_documents=0
show_trash=0
show_mounts=0
EOF

    write_file "$TARGET_HOME/.config/libfm/libfm.conf" 0644 <<'EOF'
[config]
single_click=1
quick_exec=1
auto_selection_delay=600
use_trash=1
confirm_del=1
thumbnail_local=1
EOF

    install -d -m 0755 /usr/local/share/icons/wasalight
    write_file /usr/local/share/icons/wasalight/start.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="48" cy="48" r="44" fill="#238636"/><path d="M39 29 70 48 39 67Z" fill="#fff"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/stop.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="48" cy="48" r="44" fill="#da3633"/><rect x="31" y="31" width="34" height="34" rx="3" fill="#fff"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/network.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="48" cy="48" r="44" fill="#1f6feb"/><g fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round"><path d="M22 38c15-14 37-14 52 0"/><path d="M32 50c9-8 23-8 32 0"/></g><circle cx="48" cy="65" r="6" fill="#fff"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/ip-scanner.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="42" cy="42" r="29" fill="#0969da"/><circle cx="42" cy="42" r="17" fill="none" stroke="#fff" stroke-width="6"/><path d="m62 62 22 22" stroke="#fff" stroke-width="9" stroke-linecap="round"/><circle cx="30" cy="37" r="4" fill="#79c0ff"/><circle cx="48" cy="50" r="4" fill="#79c0ff"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/artnet-monitor.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="7" y="12" width="82" height="72" rx="13" fill="#161b22" stroke="#39d353" stroke-width="5"/><path d="M17 55h12l8-23 11 41 10-29 8 11h13" fill="none" stroke="#39d353" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/><circle cx="76" cy="26" r="5" fill="#f85149"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/files.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="10" y="25" width="76" height="56" rx="8" fill="#d29922"/><path d="M12 32V23c0-5 4-8 9-8h23l10 12h24c5 0 8 4 8 9v4H12Z" fill="#f2cc60"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/terminal.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="6" y="12" width="84" height="72" rx="10" fill="#30363d" stroke="#8b949e" stroke-width="4"/><path d="m24 34 14 14-14 14M46 63h24" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/power.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="48" cy="48" r="44" fill="#b62324"/><path d="M48 20v28M31 31a27 27 0 1 0 34 0" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/reboot.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <circle cx="48" cy="48" r="44" fill="#bc6b00"/><path d="M69 34A27 27 0 1 0 73 57" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round"/><path d="m66 18 4 17-17-3Z" fill="#fff"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/hub.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="6" y="6" width="84" height="84" rx="20" fill="#8957e5"/><g fill="#fff"><rect x="23" y="23" width="20" height="20" rx="5"/><rect x="53" y="23" width="20" height="20" rx="5"/><rect x="23" y="53" width="20" height="20" rx="5"/><rect x="53" y="53" width="20" height="20" rx="5"/></g>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/vnc.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="8" y="14" width="80" height="58" rx="10" fill="#0969da"/><rect x="16" y="22" width="64" height="42" rx="4" fill="#dbeafe"/><path d="M35 84h26M48 72v12" stroke="#fff" stroke-width="7" stroke-linecap="round"/><circle cx="48" cy="43" r="10" fill="#0969da"/><path d="M29 58c5-9 12-13 19-13s14 4 19 13" fill="none" stroke="#0969da" stroke-width="6" stroke-linecap="round"/>
</svg>
EOF
    write_file /usr/local/share/icons/wasalight/ssh.svg 0644 <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
 <rect x="7" y="14" width="82" height="68" rx="14" fill="#238636"/><path d="m25 34 14 14-14 14M48 63h24" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><path d="M68 20v17m-7-9h14" stroke="#9be9a8" stroke-width="5" stroke-linecap="round"/>
</svg>
EOF

    # Remove launchers and the short-lived system-link experiment from earlier
    # runs before recreating protected regular desktop files.
    rm -f -- \
        "$TARGET_HOME/Desktop/Start-MagicQ.desktop" \
        "$TARGET_HOME/Desktop/Stop-MagicQ.desktop" \
        "$TARGET_HOME/Desktop/Wasalight-Hub.desktop" \
        "$TARGET_HOME/Desktop/Files.desktop" \
        "$TARGET_HOME/Desktop/VNC.desktop" \
        "$TARGET_HOME/Desktop/SSH.desktop" \
        "$TARGET_HOME/Desktop/Power-Off.desktop" \
        "$TARGET_HOME/Desktop/Reboot.desktop" \
        /usr/local/share/applications/wasalight-Start-MagicQ.desktop \
        /usr/local/share/applications/wasalight-Stop-MagicQ.desktop \
        /usr/local/share/applications/wasalight-Wasalight-Hub.desktop \
        /usr/local/share/applications/wasalight-VNC.desktop \
        /usr/local/share/applications/wasalight-SSH.desktop \
        /usr/local/share/applications/wasalight-Power-Off.desktop \
        /usr/local/share/applications/wasalight-Reboot.desktop

    write_file "$TARGET_HOME/Desktop/Start-MagicQ.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Start MagicQ
Comment=Avvia MagicQ e il supervisore Wasalight
Exec=/usr/local/bin/magicq-start
Icon=/usr/local/share/icons/wasalight/start.svg
Terminal=false
StartupNotify=false
EOF

    write_file "$TARGET_HOME/Desktop/Stop-MagicQ.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Stop MagicQ
Comment=Ferma MagicQ e lo mantiene chiuso
Exec=/usr/local/bin/magicq-stop
Icon=/usr/local/share/icons/wasalight/stop.svg
Terminal=false
StartupNotify=false
EOF

    # The Hub replaces the less frequently used support launchers. Keep the
    # File Manager as a first-class touch target on both desktop and panel.
    rm -f "$TARGET_HOME/Desktop/Network.desktop" \
        "$TARGET_HOME/Desktop/Terminal.desktop"

    write_file "$TARGET_HOME/Desktop/Wasalight-Hub.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Wasalight Hub
Comment=Applicazioni MagicQ, programmi e strumenti di supporto
Exec=/usr/local/bin/wasalight-hub
Icon=/usr/local/share/icons/wasalight/hub.svg
Terminal=false
StartupNotify=true
EOF

    write_file "$TARGET_HOME/Desktop/Files.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=File Manager
Comment=Apre dati persistenti e chiavette USB
Exec=pcmanfm /data
Icon=/usr/local/share/icons/wasalight/files.svg
Terminal=false
StartupNotify=true
EOF

    write_file "$TARGET_HOME/Desktop/VNC.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=VNC
Comment=Avvia o ferma VNC nella sessione grafica corrente
Exec=/usr/local/bin/wasalight-vnc-toggle
Icon=/usr/local/share/icons/wasalight/vnc.svg
Terminal=false
StartupNotify=true
EOF

    write_file "$TARGET_HOME/Desktop/SSH.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=SSH
Comment=Avvia o ferma l’accesso remoto SSH
Exec=/usr/local/bin/wasalight-ssh-toggle
Icon=/usr/local/share/icons/wasalight/ssh.svg
Terminal=false
StartupNotify=true
EOF

    write_file "$TARGET_HOME/Desktop/Power-Off.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Power off
Comment=Spegne la postazione dopo una conferma
Exec=/usr/local/bin/wasalight-power poweroff
Icon=/usr/local/share/icons/wasalight/power.svg
Terminal=false
StartupNotify=false
EOF

    write_file "$TARGET_HOME/Desktop/Reboot.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Reboot
Comment=Riavvia la postazione dopo una conferma
Exec=/usr/local/bin/wasalight-power reboot
Icon=/usr/local/share/icons/wasalight/reboot.svg
Terminal=false
StartupNotify=false
EOF

    write_file /usr/local/bin/magicq-fullscreen-watch 0755 <<'EOF'
#!/bin/sh
set -u

# MagicQ 1.9.x requests a maximized window, not the EWMH fullscreen state.
# Watch the Openbox desktop so this also covers manual starts in MAINTENANCE.
export DISPLAY=${DISPLAY:-:0}
last_window=

while :; do
    window_id=$(wmctrl -l 2>/dev/null | \
        awk 'tolower($0) ~ /magicq pc/ { print $1; exit }')
    if [ -n "$window_id" ]; then
        if [ "$window_id" != "$last_window" ]; then
            if wmctrl -ir "$window_id" -b add,fullscreen; then
                logger -t magicq-fullscreen "MagicQ window set to fullscreen: $window_id"
                last_window=$window_id
            fi
        fi
    else
        last_window=
    fi
    sleep 1
done
EOF

    write_file /usr/local/bin/magicq-audio-test 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ -r /usr/share/alsa/alsa.conf ]] || {
    echo "ALSA configuration is unavailable: /usr/share/alsa/alsa.conf" >&2
    exit 1
}

echo "ALSA playback devices:"
aplay -l
echo
echo "Playing the left and right test samples once through the default device."
speaker-test -D default -c 2 -t wav -l 1
EOF

    write_file /usr/local/bin/wasalight-power 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

action=${1:-}
case "$action" in
    poweroff)
        title="Power off Wasalight"
        question="Spegnere completamente la postazione?"
        confirm="Power off"
        ;;
    reboot)
        title="Reboot Wasalight"
        question="Riavviare adesso la postazione?"
        confirm="Reboot"
        ;;
    *)
        echo "Usage: wasalight-power poweroff|reboot" >&2
        exit 2
        ;;
esac

zenity --question --width=460 --title="$title" \
    --text="<big><b>$question</b></big>\n\nGli show salvati in /data resteranno persistenti." \
    --ok-label="$confirm" --cancel-label="Cancel" || exit 0
sudo -n /usr/local/sbin/wasalight-power-control "$action"
EOF

    write_file /usr/local/sbin/wasalight-power-control 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || {
    echo "Wasalight power control must be run through sudo." >&2
    exit 1
}

case ${1:-} in
    poweroff) exec systemctl poweroff ;;
    reboot) exec systemctl reboot ;;
    *) echo "Usage: wasalight-power-control poweroff|reboot" >&2; exit 2 ;;
esac
EOF

    write_file /usr/local/bin/wasalight-desktop-status 0755 <<'EOF'
#!/usr/bin/env bash
set -u

readonly green='#3fb950'
readonly yellow='#d29922'
readonly red='#f85149'
readonly blue='#58a6ff'

status_line() {
    printf '${color %s}%-13s${color white}%s\n' "$1" "$2" "$3"
}

root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown)
if [[ $root_fs == overlay ]]; then
    status_line "$green" 'CURRENT' 'PROTECTED'
else
    status_line "$yellow" 'CURRENT' 'MAINTENANCE'
fi

if grep -Eq '^overlayroot="tmpfs:' /etc/overlayroot.local.conf 2>/dev/null; then
    status_line "$green" 'NEXT BOOT' 'PROTECTED'
elif grep -Fqx 'overlayroot="disabled"' /etc/overlayroot.local.conf 2>/dev/null; then
    status_line "$yellow" 'NEXT BOOT' 'MAINTENANCE'
else
    status_line "$red" 'NEXT BOOT' 'UNKNOWN'
fi

if pgrep -x mqqt >/dev/null 2>&1; then
    status_line "$green" 'MAGICQ' 'RUNNING'
else
    status_line "$yellow" 'MAGICQ' 'STOPPED'
fi
if pgrep -u chamsys -f '/usr/local/bin/magicq-session' >/dev/null 2>&1; then
    status_line "$green" 'SUPERVISOR' 'RUNNING'
else
    status_line "$yellow" 'SUPERVISOR' 'STOPPED'
fi

if mountpoint -q /data; then
    data_free=$(df -h --output=avail /data 2>/dev/null | tail -n 1 | xargs)
    status_line "$green" 'DATA' "MOUNTED · ${data_free:-?} free"
else
    status_line "$red" 'DATA' 'NOT MOUNTED'
fi
if [[ -d /data/log && -w /data/log ]]; then
    status_line "$green" 'LOGS' 'PERSISTENT'
else
    status_line "$red" 'LOGS' 'UNAVAILABLE'
fi

unmanaged=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | \
    awk -F: '$2 == "ethernet" || $2 == "wifi" { if ($3 == "unmanaged") print $1 }' | \
    paste -sd, -)
ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -n $unmanaged ]]; then
    status_line "$red" 'NETWORK' "UNMANAGED: $unmanaged"
elif [[ -n $ip_address ]]; then
    status_line "$green" 'NETWORK' "$ip_address"
else
    status_line "$yellow" 'NETWORK' 'DISCONNECTED'
fi

touch_state=$(/usr/local/bin/magicq-touch-status --summary 2>/dev/null || true)
if [[ $touch_state == *ready* ]]; then
    status_line "$green" 'TOUCH' 'READY'
elif [[ -n $touch_state ]]; then
    status_line "$yellow" 'TOUCH' "${touch_state:0:32}"
else
    status_line "$yellow" 'TOUCH' 'NOT DETECTED'
fi

usb_count=$(findmnt -rn -o TARGET 2>/dev/null | \
    awk '$0 ~ "^/stick/" { count++ } END { print count+0 }')
if ((usb_count > 0)); then
    status_line "$green" 'USB' "$usb_count MOUNTED"
else
    status_line "$yellow" 'USB' 'EMPTY'
fi

if pgrep -u chamsys -x x11vnc >/dev/null 2>&1; then
    status_line "$blue" 'VNC' 'ACTIVE'
else
    status_line "$yellow" 'VNC' 'OFF'
fi
if systemctl is-active --quiet ssh.service; then
    if systemctl is-enabled --quiet ssh.service; then
        status_line "$blue" 'SSH' 'ACTIVE · AUTO'
    else
        status_line "$blue" 'SSH' 'ACTIVE · SESSION'
    fi
else
    status_line "$yellow" 'SSH' 'OFF'
fi
if aplay -l 2>/dev/null | grep -q '^card '; then
    status_line "$green" 'AUDIO' 'READY'
else
    status_line "$red" 'AUDIO' 'NO DEVICE'
fi
EOF

    write_file "$TARGET_HOME/.config/conky/wasalight.conf" 0644 <<'EOF'
conky.config = {
    alignment = 'top_right',
    background = true,
    double_buffer = true,
    update_interval = 2,
    gap_x = 24,
    gap_y = 24,
    minimum_width = 460,
    maximum_width = 520,
    use_xft = true,
    font = 'Sans:size=12',
    default_color = 'white',
    own_window = true,
    own_window_type = 'normal',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_argb_visual = true,
    own_window_argb_value = 215,
    own_window_colour = '#161b22',
    draw_borders = false,
    draw_outline = false,
    draw_shades = false,
};

conky.text = [[
${font Sans:bold:size=22}${color #58a6ff}WASALIGHT${color white}${font}
${font Sans:size=11}Michele Moser · Wasabi Lightbulbfarm${font}
${color #30363d}${hr 2}${color white}
${execpi 2 /usr/local/bin/wasalight-desktop-status}
]];
EOF

    write_file /usr/local/bin/wasalight-terminal-tool 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
case ${1:-} in
    status) command_to_run=/usr/local/bin/magicq-status ;;
    touch) command_to_run=/usr/local/bin/magicq-touch-status ;;
    audio) command_to_run=/usr/local/bin/magicq-audio-test ;;
    *) echo "Usage: wasalight-terminal-tool status|touch|audio" >&2; exit 2 ;;
esac
exec lxterminal --title="Wasalight support" -e bash -lc \
    '"$1"; rc=$?; echo; echo "Premere Invio per chiudere."; read -r _; exit "$rc"' \
    _ "$command_to_run"
EOF

    write_file /usr/local/sbin/wasalight-ip-scan 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "wasalight-ip-scan requires root" >&2; exit 1; }
(($# == 0)) || { echo "wasalight-ip-scan accepts no arguments" >&2; exit 2; }

mapfile -t interfaces < <(
    nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | \
        awk -F: '($2 == "ethernet" || $2 == "wifi") && $3 == "connected" { print $1 }'
)
((${#interfaces[@]} > 0)) || { echo "!\tNessuna interfaccia di rete connessa"; exit 0; }

for interface in "${interfaces[@]}"; do
    echo "#\t$interface"
    /usr/sbin/arp-scan --interface="$interface" --localnet --plain --ignoredups \
        2>/dev/null | awk -v dev="$interface" 'NF >= 2 { vendor=""; for (i=3;i<=NF;i++) vendor=vendor (i==3?"":" ") $i; print dev "\t" $1 "\t" $2 "\t" vendor }'
done
EOF

    write_file /usr/local/libexec/wasalight-ip-scanner.py 0755 <<'PYEOF'
#!/usr/bin/env python3
import subprocess
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk


class Scanner(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight IP Scanner")
        self.set_default_size(900, 560)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("destroy", Gtk.main_quit)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(16)
        title = Gtk.Label()
        title.set_markup("<span size='21000' weight='bold'>IP Scanner</span>\n"
                         "<span size='11000'>Dispositivi raggiungibili nella rete locale</span>")
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str)
        view = Gtk.TreeView(model=self.store)
        for index, label in enumerate(("Interfaccia", "Indirizzo IP", "MAC", "Produttore")):
            renderer = Gtk.CellRendererText()
            renderer.set_property("ypad", 9)
            column = Gtk.TreeViewColumn(label, renderer, text=index)
            column.set_resizable(True)
            column.set_expand(index == 3)
            view.append_column(column)
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)

        controls = Gtk.Box(spacing=10)
        self.status = Gtk.Label(label="Pronto")
        self.status.set_xalign(0)
        self.scan_button = Gtk.Button(label="Scansiona rete")
        self.scan_button.set_size_request(210, 58)
        self.scan_button.connect("clicked", self.start_scan)
        close = Gtk.Button(label="Chiudi")
        close.set_size_request(150, 58)
        close.connect("clicked", lambda _button: self.destroy())
        controls.pack_start(self.status, True, True, 0)
        controls.pack_start(self.scan_button, False, False, 0)
        controls.pack_start(close, False, False, 0)
        box.pack_start(controls, False, False, 0)
        self.add(box)
        self.start_scan()

    def start_scan(self, _button=None):
        self.store.clear()
        self.status.set_text("Scansione in corso…")
        self.scan_button.set_sensitive(False)
        threading.Thread(target=self.scan_worker, daemon=True).start()

    def scan_worker(self):
        try:
            result = subprocess.run(
                ["sudo", "-n", "/usr/local/sbin/wasalight-ip-scan"],
                text=True, capture_output=True, timeout=60, check=False)
            rows, message = [], ""
            for line in result.stdout.splitlines():
                if line.startswith("!\t"):
                    message = line.split("\t", 1)[1]
                elif not line.startswith("#\t"):
                    fields = line.split("\t", 3)
                    if len(fields) == 4:
                        rows.append(fields)
            if result.returncode and not message:
                message = result.stderr.strip() or "Scansione non riuscita"
            GLib.idle_add(self.finish_scan, rows, message)
        except Exception as error:
            GLib.idle_add(self.finish_scan, [], str(error))

    def finish_scan(self, rows, message):
        for row in rows:
            self.store.append(row)
        self.status.set_text(message or f"{len(rows)} dispositivi trovati")
        self.scan_button.set_sensitive(True)
        return False


css = Gtk.CssProvider()
css.load_from_data(b"button { font-size: 17px; padding: 10px; } treeview { font-size: 16px; }")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(),
    css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = Scanner()
window.show_all()
Gtk.main()
PYEOF

    write_file /usr/local/bin/wasalight-ip-scanner 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log_file=/tmp/wasalight-network-tools.log
[[ -d /data/log && -w /data/log ]] && log_file=/data/log/wasalight-network-tools.log
exec /usr/local/libexec/wasalight-ip-scanner.py >>"$log_file" 2>&1
EOF

    write_file /usr/local/sbin/wasalight-artnet-capture 0755 <<'PYEOF'
#!/usr/bin/env python3
import datetime
import os
import socket
import struct
import sys

if os.geteuid() != 0:
    raise SystemExit("wasalight-artnet-capture requires root")
if len(sys.argv) != 1:
    raise SystemExit("wasalight-artnet-capture accepts no arguments")

capture = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
capture.settimeout(1.0)
parent_pid = os.getppid()
while os.getppid() == parent_pid:
    try:
        frame = capture.recv(65535)
    except socket.timeout:
        continue
    if len(frame) < 42:
        continue
    offset = 14
    ether_type = struct.unpack("!H", frame[12:14])[0]
    if ether_type in (0x8100, 0x88A8) and len(frame) >= 46:
        ether_type = struct.unpack("!H", frame[16:18])[0]
        offset = 18
    if ether_type != 0x0800 or len(frame) < offset + 28:
        continue
    ihl = (frame[offset] & 0x0F) * 4
    if ihl < 20 or frame[offset + 9] != 17:
        continue
    udp = offset + ihl
    if len(frame) < udp + 8:
        continue
    source_port, destination_port = struct.unpack("!HH", frame[udp:udp + 4])
    if source_port != 6454 and destination_port != 6454:
        continue
    payload = frame[udp + 8:]
    if len(payload) < 12 or payload[:8] != b"Art-Net\x00":
        continue
    opcode = struct.unpack("<H", payload[8:10])[0]
    source = socket.inet_ntoa(frame[offset + 12:offset + 16])
    destination = socket.inet_ntoa(frame[offset + 16:offset + 20])
    universe, length = -1, 0
    if opcode == 0x5000 and len(payload) >= 18:
        universe = payload[14] | (payload[15] << 8)
        length = struct.unpack("!H", payload[16:18])[0]
    timestamp = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"{timestamp}\t{source}\t{destination}\t0x{opcode:04x}\t{universe}\t{length}", flush=True)
PYEOF

    write_file /usr/local/libexec/wasalight-artnet-monitor.py 0755 <<'PYEOF'
#!/usr/bin/env python3
import subprocess
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk

OPCODES = {"0x2000": "Poll", "0x2100": "Poll Reply", "0x5000": "ArtDMX", "0x5200": "Sync"}


class Monitor(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight Art-Net Monitor")
        self.set_default_size(1000, 580)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.process = None
        self.rows = {}
        self.connect("destroy", self.close)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(16)
        title = Gtk.Label()
        title.set_markup("<span size='21000' weight='bold'>Art-Net Monitor</span>\n"
                         "<span size='11000'>Traffico UDP Art-Net su tutte le interfacce</span>")
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str, int, int, str)
        view = Gtk.TreeView(model=self.store)
        labels = ("Sorgente", "Destinazione", "Tipo", "Universo", "Canali", "Pacchetti", "Ultimo")
        for index, label in enumerate(labels):
            renderer = Gtk.CellRendererText()
            renderer.set_property("ypad", 8)
            column = Gtk.TreeViewColumn(label, renderer, text=index)
            column.set_resizable(True)
            column.set_expand(index in (0, 1))
            view.append_column(column)
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)

        controls = Gtk.Box(spacing=10)
        self.status = Gtk.Label(label="In ascolto sulla porta UDP 6454")
        self.status.set_xalign(0)
        clear = Gtk.Button(label="Azzera")
        clear.set_size_request(150, 58)
        clear.connect("clicked", self.clear)
        close = Gtk.Button(label="Chiudi")
        close.set_size_request(150, 58)
        close.connect("clicked", lambda _button: self.destroy())
        controls.pack_start(self.status, True, True, 0)
        controls.pack_start(clear, False, False, 0)
        controls.pack_start(close, False, False, 0)
        box.pack_start(controls, False, False, 0)
        self.add(box)
        self.start_capture()

    def start_capture(self):
        try:
            self.process = subprocess.Popen(
                ["sudo", "-n", "/usr/local/sbin/wasalight-artnet-capture"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
            threading.Thread(target=self.read_packets, daemon=True).start()
        except Exception as error:
            self.status.set_text(str(error))

    def read_packets(self):
        for line in self.process.stdout:
            fields = line.rstrip().split("\t")
            if len(fields) == 6:
                GLib.idle_add(self.add_packet, *fields)
        error = self.process.stderr.read().strip()
        if error:
            GLib.idle_add(self.status.set_text, error)

    def add_packet(self, timestamp, source, destination, opcode, universe, length):
        kind = OPCODES.get(opcode, opcode)
        shown_universe = "—" if universe == "-1" else str(int(universe) + 1)
        key = (source, destination, opcode, universe)
        if key in self.rows:
            row = self.rows[key]
            self.store[row][5] += 1
            self.store[row][6] = timestamp
        else:
            self.rows[key] = self.store.append(
                [source, destination, kind, shown_universe, int(length), 1, timestamp])
        return False

    def clear(self, _button):
        self.store.clear()
        self.rows.clear()

    def close(self, _window):
        if self.process and self.process.poll() is None:
            self.process.terminate()
        Gtk.main_quit()


css = Gtk.CssProvider()
css.load_from_data(b"button { font-size: 17px; padding: 10px; } treeview { font-size: 15px; }")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(),
    css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = Monitor()
window.show_all()
Gtk.main()
PYEOF

    write_file /usr/local/bin/wasalight-artnet-monitor 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
log_file=/tmp/wasalight-network-tools.log
[[ -d /data/log && -w /data/log ]] && log_file=/data/log/wasalight-network-tools.log
exec /usr/local/libexec/wasalight-artnet-monitor.py >>"$log_file" 2>&1
EOF

    install -d -m 0755 /etc/wasalight/apps.d
    write_file /etc/wasalight/apps.d/network.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Network
Comment=Configura Ethernet e Wi-Fi
Exec=nm-connection-editor
Icon=/usr/local/share/icons/wasalight/network.svg
TryExec=nm-connection-editor
X-Wasalight-Section=Support
X-Wasalight-Order=10
EOF
    write_file /etc/wasalight/apps.d/display.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Display
Comment=Configura monitor e risoluzione
Exec=lxrandr
Icon=video-display
TryExec=lxrandr
X-Wasalight-Section=Support
X-Wasalight-Order=20
EOF
    write_file /etc/wasalight/apps.d/touch.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Touchscreen
Comment=Mostra dispositivi e associazione touch
Exec=/usr/local/bin/wasalight-terminal-tool touch
Icon=input-touchpad
TryExec=/usr/local/bin/magicq-touch-status
X-Wasalight-Section=Support
X-Wasalight-Order=30
EOF
    write_file /etc/wasalight/apps.d/audio.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Audio test
Comment=Prova il dispositivo ALSA predefinito
Exec=/usr/local/bin/wasalight-terminal-tool audio
Icon=audio-card
TryExec=/usr/local/bin/magicq-audio-test
X-Wasalight-Section=Support
X-Wasalight-Order=40
EOF
    write_file /etc/wasalight/apps.d/files.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Files
Comment=Apre dati persistenti e chiavette USB
Exec=pcmanfm /data
Icon=/usr/local/share/icons/wasalight/files.svg
TryExec=pcmanfm
X-Wasalight-Section=Support
X-Wasalight-Order=50
EOF
    write_file /etc/wasalight/apps.d/ip-scanner.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=IP Scanner
Comment=Trova dispositivi, indirizzi IP e produttori nella rete locale
Exec=/usr/local/bin/wasalight-ip-scanner
Icon=/usr/local/share/icons/wasalight/ip-scanner.svg
TryExec=/usr/local/bin/wasalight-ip-scanner
X-Wasalight-Section=Support
X-Wasalight-Order=55
EOF
    write_file /etc/wasalight/apps.d/artnet-monitor.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Art-Net Monitor
Comment=Mostra sorgenti, universi e pacchetti Art-Net in tempo reale
Exec=/usr/local/bin/wasalight-artnet-monitor
Icon=/usr/local/share/icons/wasalight/artnet-monitor.svg
TryExec=/usr/local/bin/wasalight-artnet-monitor
X-Wasalight-Section=Support
X-Wasalight-Order=56
EOF
    write_file /etc/wasalight/apps.d/system-monitor.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=System Monitor
Comment=Mostra processi e utilizzo di CPU e memoria
Exec=lxtask
Icon=utilities-system-monitor
TryExec=lxtask
X-Wasalight-Section=Support
X-Wasalight-Order=58
EOF
    write_file /etc/wasalight/apps.d/terminal.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Comment=Apre il terminale di manutenzione
Exec=lxterminal
Icon=/usr/local/share/icons/wasalight/terminal.svg
TryExec=lxterminal
X-Wasalight-Section=Support
X-Wasalight-Order=60
EOF
    write_file /etc/wasalight/apps.d/status.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=System status
Comment=Mostra lo stato completo Wasalight
Exec=/usr/local/bin/wasalight-terminal-tool status
Icon=utilities-system-monitor
TryExec=/usr/local/bin/magicq-status
X-Wasalight-Section=Support
X-Wasalight-Order=70
EOF
    write_file /etc/wasalight/apps.d/vnc.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=VNC session
Comment=Avvia o ferma la condivisione corrente
Exec=/usr/local/bin/wasalight-vnc-toggle
Icon=/usr/local/share/icons/wasalight/vnc.svg
TryExec=/usr/local/bin/wasalight-vnc-toggle
X-Wasalight-Section=Support
X-Wasalight-Order=80
EOF
    write_file /etc/wasalight/apps.d/ssh.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=SSH access
Comment=Avvia o ferma il server SSH
Exec=/usr/local/bin/wasalight-ssh-toggle
Icon=/usr/local/share/icons/wasalight/ssh.svg
TryExec=/usr/local/bin/wasalight-ssh-toggle
X-Wasalight-Section=Support
X-Wasalight-Order=90
EOF
    write_file /etc/wasalight/apps.d/update.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Update Wasalight
Comment=Scarica e installa l’ultima versione in MAINTENANCE
Exec=/usr/local/bin/wasalight-update-terminal
Icon=system-software-update
TryExec=/usr/local/bin/wasalight-update-terminal
X-Wasalight-Section=Support
X-Wasalight-Order=100
EOF

    write_file /usr/local/sbin/wasalight-app-register 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
destination=/etc/wasalight/apps.d
mountpoint -q /data && destination=/data/system/apps.d
install -d -m 0755 "$destination"

case ${1:-} in
    --list)
        {
            for registry in /etc/wasalight/apps.d /data/system/apps.d; do
                [[ ! -d $registry ]] || find "$registry" -maxdepth 1 \
                    -type f -name '*.desktop' -print
            done
        } | sort
        exit 0
        ;;
    --remove)
        name=${2##*/}
        [[ $name =~ ^[A-Za-z0-9._+-]+\.desktop$ ]] || {
            echo "Invalid launcher name: $name" >&2; exit 2;
        }
        rm -f "$destination/$name"
        echo "Removed: $destination/$name"
        exit 0
        ;;
esac

source_file=${1:?usage: wasalight-app-register FILE.desktop | --list | --remove NAME.desktop}
[[ -f $source_file && ${source_file##*.} == desktop ]] || {
    echo "A readable .desktop file is required: $source_file" >&2; exit 2;
}
desktop-file-validate "$source_file"
name=${source_file##*/}
install -m 0644 "$source_file" "$destination/$name"
echo "Registered in Wasalight Hub: $destination/$name"
EOF

    write_file /usr/local/libexec/wasalight-hub.py 0755 <<'PYEOF'
#!/usr/bin/env python3
import configparser
import glob
import os
import re
import shlex
import shutil
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gtk

SECTIONS = ("MagicQ", "Applications", "Support")
COMPANION = re.compile(r"magicvis|magichd|magicq[ -]?remote|chamsys.*(?:remote|viewer|media)", re.I)
FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")


def desktop_bool(item, key, default=False):
    try:
        return item.getboolean(key, fallback=default)
    except ValueError:
        return default


def read_launcher(path, forced_section=None):
    parser = configparser.RawConfigParser(interpolation=None, strict=False)
    try:
        parser.read(path, encoding="utf-8")
        item = parser["Desktop Entry"]
    except (OSError, KeyError, configparser.Error):
        return None
    if item.get("Type", "Application") != "Application":
        return None
    if desktop_bool(item, "Hidden") or desktop_bool(item, "NoDisplay"):
        return None
    name = item.get("Name", "").strip()
    command = item.get("Exec", "").strip()
    try_exec = item.get("TryExec", "").strip()
    if not name or not command:
        return None
    if try_exec and not (os.path.exists(try_exec) if os.path.isabs(try_exec) else shutil.which(try_exec)):
        return None
    section = forced_section or item.get("X-Wasalight-Section", "Applications")
    if section not in SECTIONS:
        section = "Applications"
    try:
        order = int(item.get("X-Wasalight-Order", "500"))
    except ValueError:
        order = 500
    return {
        "name": name,
        "comment": item.get("Comment", ""),
        "exec": command,
        "icon": item.get("Icon", "application-x-executable"),
        "terminal": desktop_bool(item, "Terminal"),
        "path": item.get("Path", "").strip() or None,
        "section": section,
        "order": order,
    }


def installed_launchers():
    result, seen = [], set()
    for pattern in ("/etc/wasalight/apps.d/*.desktop", "/data/system/apps.d/*.desktop"):
        for path in sorted(glob.glob(pattern)):
            launcher = read_launcher(path)
            if launcher and (launcher["name"], launcher["exec"]) not in seen:
                result.append(launcher)
                seen.add((launcher["name"], launcher["exec"]))
    for path in sorted(glob.glob("/usr/share/applications/*.desktop")):
        launcher = read_launcher(path, "MagicQ")
        if not launcher:
            continue
        searchable = " ".join((launcher["name"], launcher["exec"], launcher["comment"]))
        if COMPANION.search(searchable) and (launcher["name"], launcher["exec"]) not in seen:
            result.append(launcher)
            seen.add((launcher["name"], launcher["exec"]))
    return sorted(result, key=lambda value: (SECTIONS.index(value["section"]), value["order"], value["name"].lower()))


def launcher_image(icon):
    if os.path.isabs(icon) and os.path.isfile(icon):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon, 72, 72, True)
            return Gtk.Image.new_from_pixbuf(pixbuf)
        except Exception:
            pass
    image = Gtk.Image.new_from_icon_name(icon or "application-x-executable", Gtk.IconSize.DIALOG)
    image.set_pixel_size(72)
    return image


def companion_kind(command):
    """Return the supported ChamSys companion selected by a desktop Exec."""
    try:
        executable = os.path.basename(shlex.split(command)[0])
    except (ValueError, IndexError):
        return None
    return {
        "runmagichd.sh": "magichd",
        "mqhd": "magichd",
        "runmagicvis.sh": "magicvis",
        "mqvis": "magicvis",
    }.get(executable)


class Hub(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight Hub")
        self.set_default_size(900, 650)
        self.set_position(Gtk.WindowPosition.CENTER)
        try:
            self.set_icon_from_file("/usr/local/share/icons/wasalight/hub.svg")
        except Exception:
            pass
        self.connect("destroy", Gtk.main_quit)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_border_width(18)
        header = Gtk.Label()
        header.set_markup("<span size='22000' weight='bold'>Wasalight Hub</span>\n"
                          "<span size='11000'>MagicQ · applicazioni · supporto</span>")
        header.set_xalign(0)
        outer.pack_start(header, False, False, 0)

        notebook = Gtk.Notebook()
        launchers = installed_launchers()
        for section in SECTIONS:
            flow = Gtk.FlowBox()
            flow.set_selection_mode(Gtk.SelectionMode.NONE)
            flow.set_row_spacing(14)
            flow.set_column_spacing(14)
            flow.set_max_children_per_line(4)
            flow.set_min_children_per_line(2)
            section_items = [item for item in launchers if item["section"] == section]
            if not section_items:
                empty = Gtk.Label(label="Nessuna applicazione registrata")
                empty.set_margin_top(40)
                flow.add(empty)
            for item in section_items:
                button = Gtk.Button()
                button.set_size_request(190, 145)
                button.set_tooltip_text(item["comment"])
                content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
                content.pack_start(launcher_image(item["icon"]), True, True, 0)
                label = Gtk.Label(label=item["name"])
                label.set_line_wrap(True)
                label.set_justify(Gtk.Justification.CENTER)
                content.pack_start(label, False, False, 0)
                button.add(content)
                button.connect("clicked", self.launch, item)
                flow.add(button)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            scroll.add(flow)
            notebook.append_page(scroll, Gtk.Label(label=section))
        outer.pack_start(notebook, True, True, 0)

        close = Gtk.Button(label="Close")
        close.set_size_request(-1, 56)
        close.connect("clicked", lambda _button: self.destroy())
        outer.pack_start(close, False, False, 0)
        self.add(outer)

    def launch(self, _button, item):
        command = FIELD_CODE.sub("", item["exec"])
        try:
            companion = companion_kind(command)
            if companion:
                # The target's proprietary Qt/OpenGL bundle works with the
                # same root X11 environment required by MagicQ itself.
                arguments = ["sudo", "-n", "/usr/local/sbin/wasalight-companion-launcher", companion]
            else:
                arguments = shlex.split(command)
            if item["terminal"]:
                arguments = ["lxterminal", "-e"] + arguments
            subprocess.Popen(arguments, cwd=item["path"], start_new_session=True)
            self.destroy()
        except (OSError, ValueError) as error:
            dialog = Gtk.MessageDialog(self, 0, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE,
                                       "Impossibile avviare l'applicazione")
            dialog.format_secondary_text(str(error))
            dialog.run()
            dialog.destroy()


css = Gtk.CssProvider()
css.load_from_data(b"button { font-size: 18px; padding: 12px; } notebook tab { padding: 14px 28px; font-size: 17px; }")
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = Hub()
window.show_all()
Gtk.main()
PYEOF

    write_file /usr/local/bin/wasalight-hub 0755 <<'EOF'
#!/usr/bin/env bash
set -u

log_dir=/tmp
if [[ -d /data/log && -w /data/log ]]; then
    log_dir=/data/log
fi
log_file="$log_dir/wasalight-hub.log"

if /usr/local/libexec/wasalight-hub.py >>"$log_file" 2>&1; then
    exit 0
else
    rc=$?
fi
details=$(tail -n 16 "$log_file" 2>/dev/null || true)
zenity --error --width=620 --title="Wasalight Hub" \
    --text="<big><b>Wasalight Hub non è riuscito ad avviarsi.</b></big>\n\n$details\n\nLog: $log_file" \
    2>/dev/null || true
exit "$rc"
EOF

    write_file "$TARGET_HOME/.config/tint2/tint2rc" 0644 <<EOF
# Wasalight touch panel: always visible, with a discreet near-black theme.
rounded = 0
border_width = 0
background_color = #080b10 98
border_color = #080b10 100

rounded = 8
border_width = 1
background_color = #20252d 100
border_color = #3d444d 100

panel_items = LTSC
panel_size = 100% 64
panel_margin = 0 0
panel_padding = 10 6 10
panel_background_id = 1
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_dock = 0
wm_menu = 0
strut_policy = follow_size
autohide = 0

launcher_padding = 8 4 8
launcher_background_id = 2
launcher_icon_background_id = 0
launcher_icon_size = 46
launcher_item_app = $TARGET_HOME/Desktop/Wasalight-Hub.desktop
launcher_item_app = $TARGET_HOME/Desktop/Files.desktop

taskbar_mode = single_desktop
taskbar_padding = 4 0 4
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_if_empty = 0
taskbar_distribute_size = 1

task_icon = 1
task_text = 1
task_centered = 1
task_maximum_size = 220 52
task_padding = 10 4 10
task_font = Sans 12
task_font_color = #ffffff 100
task_active_font_color = #ffffff 100
task_background_id = 0
task_active_background_id = 2

systray_padding = 8 4 8
systray_icon_size = 30
systray_icon_asb = 100 0 0

time1_format = %H:%M
time1_font = Sans Bold 13
clock_font_color = #ffffff 100
clock_padding = 12 0
clock_background_id = 0

mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = none
mouse_scroll_down = none
EOF

    write_file /usr/local/sbin/wasalight-companion-launcher 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || {
    echo "Wasalight companion launcher must be run through sudo." >&2
    exit 1
}

case ${1:-} in
    magichd) launcher=/opt/magicq/runmagichd.sh ;;
    magicvis) launcher=/opt/magicq/runmagicvis.sh ;;
    *) echo "Usage: wasalight-companion-launcher magichd|magicvis" >&2; exit 2 ;;
esac
[[ -x $launcher ]] || {
    echo "ChamSys companion launcher not found: $launcher" >&2
    exit 127
}

# MagicHD and MagicVis use the same proprietary Qt/OpenGL runtime as MagicQ.
# Match the root X11 environment already proven on the target while keeping
# root's Documents/MagicQ directory backed by persistent /data bind mounts.
export HOME=/root
export USER=root
export LOGNAME=root
export XDG_DATA_HOME=/root/.local/share
export XDG_CONFIG_HOME=/root/.config
export DISPLAY=:0
export XAUTHORITY=/home/chamsys/.Xauthority
unset DBUS_SESSION_BUS_ADDRESS XDG_CACHE_HOME XDG_RUNTIME_DIR
umask 0022

cd /opt/magicq
exec "$launcher"
EOF

    write_file /usr/local/sbin/magicq-root-launcher 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly magicq_user=chamsys
readonly magicq_home=/home/chamsys
readonly magicq_data=/data/magicq

[[ $EUID -eq 0 ]] || {
    echo "MagicQ root launcher must be run through sudo." >&2
    exit 1
}
id "$magicq_user" >/dev/null 2>&1 || {
    echo "Required user is unavailable: $magicq_user" >&2
    exit 1
}

install -d -o "$magicq_user" -g "$magicq_user" -m 2770 \
    "$magicq_home/Documents/MagicQ" "$magicq_home/.local/share"

# Match the manual sudo launch that works on the target. Root's MagicQ config
# and local data are bind-mounted from /data; user-dirs.dirs sends the Documents
# location to /home/chamsys/Documents. /root/Documents/MagicQ is also a bind
# fallback to the same persistent show directory.
export HOME=/root
export USER=root
export LOGNAME=root
export XDG_DATA_HOME=/root/.local/share
export XDG_CONFIG_HOME=/root/.config
export DISPLAY=:0
export XAUTHORITY=/home/chamsys/.Xauthority
unset DBUS_SESSION_BUS_ADDRESS XDG_CACHE_HOME XDG_RUNTIME_DIR
umask 0022

repair_magicq_ownership() {
    if mountpoint -q /data; then
        chown -R "$magicq_user:$magicq_user" \
            "$magicq_data/Documents/MagicQ" "$magicq_data/.local/share" \
            2>/dev/null || true
        find "$magicq_data/Documents/MagicQ" "$magicq_data/.local/share" \
            -type d -exec chmod g+rwx {} + 2>/dev/null || true
    fi
}
trap repair_magicq_ownership EXIT

cd /opt/magicq
if [[ -x ./runmagicq.sh ]]; then
    ./runmagicq.sh
elif [[ -x ./bin/mqqt ]]; then
    ./bin/mqqt
else
    echo "MagicQ executable not found under /opt/magicq." >&2
    exit 127
fi
EOF

    write_file /usr/local/sbin/magicq-root-stop 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || {
    echo "MagicQ root stop must be run through sudo." >&2
    exit 1
}

if ! pgrep -x mqqt >/dev/null 2>&1; then
    echo "MagicQ is already stopped."
    exit 0
fi

pkill -TERM -x mqqt
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x mqqt >/dev/null 2>&1 || {
        echo "MagicQ stopped."
        exit 0
    }
    sleep 1
done

pkill -KILL -x mqqt 2>/dev/null || true
echo "MagicQ required a forced stop."
EOF

    write_file /usr/local/bin/magicq-session 0755 <<'EOF'
#!/bin/sh
set -u
log_dir=${MAGICQ_LOG_DIR:-/data/log}
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

if [ ! -d "$log_dir" ] || [ ! -w "$log_dir" ]; then
    log_dir="$runtime_dir"
    logger -t magicq-session "Persistent log directory unavailable; using $log_dir"
fi
console_log="$log_dir/wasalight-magicq-console.log"
session_log="$log_dir/wasalight-magicq-session.log"
touch "$console_log" "$session_log"
chmod 0640 "$console_log" "$session_log" 2>/dev/null || true

# Openbox menu actions and autostart may overlap. Keep one supervisor only.
exec 9>"$runtime_dir/wasalight-magicq-session.lock"
flock -n 9 || exit 0
pid_file="$runtime_dir/wasalight-magicq-session.pid"

session_event() {
    event_message=$1
    printf '%s %s\n' "$(date -Is)" "$event_message" >>"$session_log"
    logger -t magicq-session "$event_message"
}

cleanup_session() {
    if [ -r "$pid_file" ] && [ "$(cat "$pid_file")" = "$$" ]; then
        rm -f "$pid_file"
    fi
}

stop_session() {
    session_event "MagicQ supervisor stopped by operator"
    exit 0
}

printf '%s\n' "$$" >"$pid_file"
trap stop_session HUP INT TERM
trap cleanup_session EXIT

session_event "MagicQ supervisor started"
while :; do
    if [ -x /usr/local/sbin/magicq-root-launcher ]; then
        # The fixed sudo command grants only the dedicated launcher. That
        # launcher keeps root's working environment while its MagicQ paths are
        # persistent bind mounts backed by /data.
        session_event "Starting MagicQ"
        printf '\n===== %s MagicQ launch =====\n' "$(date -Is)" >>"$console_log"
        sudo -n /usr/local/sbin/magicq-root-launcher \
            >>"$console_log" 2>&1
    else
        session_event "MagicQ root launcher not found; retrying in 30 seconds"
        sleep 30
        continue
    fi
    rc=$?
    session_event "MagicQ exited with status $rc; restarting in 3 seconds"
    sleep 3
done
EOF

    write_file /usr/local/bin/magicq-start 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
exec 9>"$runtime_dir/wasalight-magicq-session.lock"
if ! flock -n 9; then
    echo "MagicQ supervisor is already running."
    exit 0
fi
flock -u 9
nohup /usr/local/bin/magicq-session >/dev/null 2>&1 &
echo "MagicQ supervisor started."
EOF

    write_file /usr/local/bin/magicq-stop 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -un) == chamsys ]] || {
    echo "Run this command as the chamsys desktop user." >&2
    exit 1
}
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
pid_file="$runtime_dir/wasalight-magicq-session.pid"
supervisor_pid=

valid_supervisor() {
    local candidate=${1:-}
    [[ $candidate =~ ^[0-9]+$ ]] && \
    [[ $(ps -o uid= -p "$candidate" 2>/dev/null | tr -d ' ') == $(id -u) ]] && \
    [[ $(ps -o args= -p "$candidate" 2>/dev/null) == *'/usr/local/bin/magicq-session'* ]]
}

if [[ -r $pid_file ]]; then
    supervisor_pid=$(<"$pid_file")
fi
if ! valid_supervisor "$supervisor_pid"; then
    supervisor_pid=
    while read -r candidate; do
        if valid_supervisor "$candidate"; then
            supervisor_pid=$candidate
            break
        fi
    done < <(pgrep -u "$(id -u)" -f '/usr/local/bin/magicq-session' 2>/dev/null || true)
fi
[[ -z $supervisor_pid ]] || kill -TERM "$supervisor_pid" 2>/dev/null || true

# Stop the root-owned application only after disabling its supervisor, so it
# cannot be interpreted as a crash and immediately restarted.
sudo -n /usr/local/sbin/magicq-root-stop
for _ in 1 2 3 4 5; do
    [[ ! -r $pid_file ]] && break
    sleep 1
done
rm -f "$pid_file"
echo "MagicQ will remain stopped until magicq-start or the next login/reboot."
EOF

    write_file "$TARGET_HOME/.config/openbox/autostart" 0755 <<'EOF'
#!/bin/sh
xset s off
xset s noblank
xset -dpms
wmctrl -n 1
pcmanfm --desktop --profile=default &
conky --config="$HOME/.config/conky/wasalight.conf" --daemonize --pause=2
tint2 -c "$HOME/.config/tint2/tint2rc" &
nm-applet --indicator &
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
/usr/local/bin/magicq-touch-watch &
/usr/local/bin/magicq-fullscreen-watch &
if findmnt -n -o FSTYPE / 2>/dev/null | grep -qx overlay; then
    /usr/local/bin/magicq-session &
else
    logger -t magicq-session "MAINTENANCE mode: automatic MagicQ start skipped"
fi
EOF

    if ((ENABLE_ONSCREEN_KEYBOARD)); then
        write_file /etc/wasalight/apps.d/keyboard.desktop 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=On-screen keyboard
Comment=Apre la tastiera touch Onboard
Exec=onboard
Icon=input-keyboard
TryExec=onboard
X-Wasalight-Section=Support
X-Wasalight-Order=110
EOF
    else
        rm -f /etc/wasalight/apps.d/keyboard.desktop
    fi
    write_file "$TARGET_HOME/.config/openbox/menu.xml" 0644 <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Wasalight">
    <item label="Start MagicQ"><action name="Execute"><command>/usr/local/bin/magicq-start</command></action></item>
    <item label="Stop MagicQ"><action name="Execute"><command>/usr/local/bin/magicq-stop</command></action></item>
    <separator />
    <item label="Wasalight Hub"><action name="Execute"><command>/usr/local/bin/wasalight-hub</command></action></item>
    <item label="File Manager"><action name="Execute"><command>pcmanfm /data</command></action></item>
    <item label="Terminal"><action name="Execute"><command>lxterminal</command></action></item>
    <item label="Update Wasalight"><action name="Execute"><command>/usr/local/bin/wasalight-update-terminal</command></action></item>
    <item label="VNC"><action name="Execute"><command>/usr/local/bin/wasalight-vnc-toggle</command></action></item>
    <item label="SSH"><action name="Execute"><command>/usr/local/bin/wasalight-ssh-toggle</command></action></item>
    <separator />
    <item label="Reboot"><action name="Execute"><command>/usr/local/bin/wasalight-power reboot</command></action></item>
    <item label="Power off"><action name="Execute"><command>/usr/local/bin/wasalight-power poweroff</command></action></item>
  </menu>
</openbox_menu>
EOF

    write_file "$TARGET_HOME/.config/pcmanfm/default/pcmanfm.conf" 0644 <<'EOF'
[volume]
mount_on_startup=0
mount_removable=0
autorun=0
EOF

    install -d -m 0755 /etc/polkit-1/rules.d
    write_file /etc/polkit-1/rules.d/49-chamsys-network.rules 0644 <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "chamsys" && subject.local && subject.active &&
        action.id.indexOf("org.freedesktop.NetworkManager.") == 0) {
        return polkit.Result.YES;
    }
});
EOF

    chown -R "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.config" "$TARGET_HOME/.xinitrc"
    # LibFM recognises readable application/x-desktop files without an execute
    # bit. Keeping the root-owned launchers at 0444 prevents its fast MIME pass
    # from misclassifying them as generic executables, so their SVGs are used.
    chown -R root:root "$TARGET_HOME/Desktop"
    chmod 0755 "$TARGET_HOME/Desktop"
    find "$TARGET_HOME/Desktop" -maxdepth 1 -type f -name '*.desktop' \
        -exec chmod 0444 {} +

    install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
    write_file /etc/systemd/system/getty@tty1.service.d/autologin.conf 0644 <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
Type=idle
EOF
    systemctl set-default multi-user.target
}

configure_persistent_logs() {
    local log_file old_log new_log
    if mountpoint -q "$DATA_MOUNT"; then
        install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$DATA_MOUNT/log"
        for old_log in magicq-console.log magicq-session.log; do
            new_log="wasalight-$old_log"
            if [[ -e "$DATA_MOUNT/log/$old_log" && ! -e "$DATA_MOUNT/log/$new_log" ]]; then
                mv "$DATA_MOUNT/log/$old_log" "$DATA_MOUNT/log/$new_log"
            elif [[ -e "$DATA_MOUNT/log/$old_log" ]]; then
                warn "legacy log retained because the new file already exists: $DATA_MOUNT/log/$old_log"
            fi
        done
        for log_file in wasalight-magicq-console.log wasalight-magicq-session.log wasalight-hub.log wasalight-network-tools.log; do
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
    write_file /etc/wasalight/magicq-logrotate.conf 0644 <<'EOF'
/data/log/wasalight-magicq-console.log /data/log/wasalight-magicq-session.log /data/log/wasalight-hub.log /data/log/wasalight-network-tools.log {
    size 5M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 chamsys chamsys
    su chamsys chamsys
}
EOF

    write_file /etc/systemd/system/magicq-logrotate.service 0644 <<'EOF'
[Unit]
Description=Rotate persistent Wasalight MagicQ logs
RequiresMountsFor=/data/log
ConditionPathIsMountPoint=/data

[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate --state /run/magicq-logrotate.status /etc/wasalight/magicq-logrotate.conf
EOF

    write_file /etc/systemd/system/magicq-logrotate.timer 0644 <<'EOF'
[Unit]
Description=Periodically limit persistent Wasalight MagicQ logs

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
AccuracySec=1min
Unit=magicq-logrotate.service

[Install]
WantedBy=timers.target
EOF

    systemctl enable magicq-logrotate.timer
}

configure_usb() {
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 "$USB_MOUNT"

    write_file /usr/local/libexec/magicq-usb-mount 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
dev_name=${1:?missing block device name}
dev="/dev/$dev_name"
base=/stick
state_dir=/run/magicq-usb

[[ $dev_name =~ ^[a-zA-Z0-9._-]+$ ]] || exit 1
mountpoint="$base/$dev_name"
state="$state_dir/$dev_name.mount"

exec 9>/run/magicq-usb.lock
flock 9

[[ -b "$dev" ]] || exit 0
props=$(udevadm info --query=property --name="$dev")
grep -qx 'ID_BUS=usb' <<<"$props" || exit 0
fs=$(sed -n 's/^ID_FS_TYPE=//p' <<<"$props" | head -n1)

case "$fs" in
    vfat)   type=vfat;    opts='rw,nosuid,nodev,noexec,sync,flush,uid=chamsys,gid=chamsys,umask=0022,shortname=mixed,utf8=1' ;;
    exfat)  type=exfat;   opts='rw,nosuid,nodev,noexec,sync,uid=chamsys,gid=chamsys,umask=0022' ;;
    ntfs)   type=ntfs-3g; opts='rw,nosuid,nodev,noexec,sync,uid=chamsys,gid=chamsys,umask=0022' ;;
    *) logger -t magicq-usb "Ignoring $dev: unsupported filesystem '$fs'"; exit 0 ;;
esac

install -d -m 0755 "$state_dir"
install -d -o chamsys -g chamsys -m 0755 "$base" "$mountpoint"
mountpoint -q "$mountpoint" && exit 0
if mount -t "$type" -o "$opts" "$dev" "$mountpoint"; then
    printf '%s\n' "$mountpoint" >"$state"
    logger -t magicq-usb "Mounted $dev ($fs) at $mountpoint with synchronous writes"
else
    logger -t magicq-usb "Failed to mount $dev ($fs)"
    exit 1
fi
EOF

    write_file /usr/local/libexec/magicq-usb-unmount 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
dev_name=${1:?missing block device name}
base=/stick
state_dir=/run/magicq-usb

[[ $dev_name =~ ^[a-zA-Z0-9._-]+$ ]] || exit 1
state="$state_dir/$dev_name.mount"

exec 9>/run/magicq-usb.lock
flock 9

[[ -r "$state" ]] || exit 0
mountpoint=$(<"$state")
[[ $mountpoint == "$base/$dev_name" ]] || exit 1

# If removal has already happened, sync may fail; lazy detach still cleans the
# namespace and prevents a stale device directory from affecting other sticks.
sync -f "$mountpoint" 2>/dev/null || true
umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null || true
rm -f "$state"
rmdir "$mountpoint" 2>/dev/null || true
logger -t magicq-usb "Cleaned up $dev_name from $mountpoint"
EOF

    write_file /etc/systemd/system/magicq-usb@.service 0644 <<'EOF'
[Unit]
Description=MagicQ USB mount for /dev/%I
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/libexec/magicq-usb-mount %I
ExecStop=/usr/local/libexec/magicq-usb-unmount %I
TimeoutStopSec=10
EOF

    write_file /etc/udev/rules.d/90-magicq-usb.rules 0644 <<'EOF'
# Start a systemd unit for supported USB filesystem partitions. Mounting is
# intentionally not performed inside udev.
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition|disk", ENV{ID_BUS}=="usb", ENV{ID_FS_TYPE}=="vfat|exfat|ntfs", TAG+="systemd", ENV{SYSTEMD_WANTS}+="magicq-usb@%k.service"
EOF

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

configure_volatile_runtime() {
    install -d -m 0755 /etc/systemd/journald.conf.d
    write_file /etc/systemd/journald.conf.d/10-magicq-volatile.conf 0644 <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=128M
RuntimeKeepFree=64M
Compress=yes
ForwardToSyslog=no
EOF

    ensure_fstab_line "MagicQ volatile temporary files" \
        "tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,mode=1777,size=1G 0 0"
    ensure_fstab_line "MagicQ volatile var temporary files" \
        "tmpfs /var/tmp tmpfs rw,nosuid,nodev,noatime,mode=1777,size=512M 0 0"

    install -d -m 0755 /etc/systemd/logind.conf.d
    write_file /etc/systemd/logind.conf.d/10-magicq-no-sleep.conf 0644 <<'EOF'
[Login]
HandlePowerKey=poweroff
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
IdleAction=ignore
EOF
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
    local candidates=(snapd modemmanager cups cups-daemon bluez avahi-daemon whoopsie apport unattended-upgrades)
    local installed=() pkg
    for pkg in "${candidates[@]}"; do
        is_installed "$pkg" && installed+=("$pkg")
    done
    if ((${#installed[@]})); then
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    fi

    disable_service_if_present \
        snapd.service snapd.socket ModemManager.service cups.service cups.socket \
        bluetooth.service avahi-daemon.service avahi-daemon.socket whoopsie.service \
        apport.service unattended-upgrades.service

    disable_service_if_present apt-daily.timer apt-daily-upgrade.timer

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
    local cleanup_candidates=(pollinate)
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

    # Mask PackageKit only after every APT/dpkg operation above. Masking it
    # earlier makes dpkg's cache refresh emit a misleading UnitMasked warning.
    disable_service_if_present packagekit.service

    write_file /etc/apt/apt.conf.d/20auto-upgrades 0644 <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

    write_file /etc/default/motd-news 0644 <<'EOF'
ENABLED=0
EOF
}

install_mode_commands() {
    write_file /usr/local/libexec/magicq-set-mode 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mode=${1:?usage: magicq-set-mode show|maintenance}
[[ $EUID -eq 0 ]] || { echo "Must run as root" >&2; exit 1; }

case "$mode" in
    show)
        printf '%s\n' 'overlayroot="tmpfs:swap=0,recurse=0"' >/etc/overlayroot.local.conf
        ;;
    maintenance)
        printf '%s\n' 'overlayroot="disabled"' >/etc/overlayroot.local.conf
        ;;
    *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac
update-initramfs -u
echo "Next boot mode: ${mode^^}. Reboot when ready."
EOF

    write_file /usr/local/sbin/magicq-maintenance 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
if findmnt -n -o FSTYPE / | grep -qx overlay; then
    command -v overlayroot-chroot >/dev/null || { echo "overlayroot-chroot is missing" >&2; exit 1; }
    overlayroot-chroot /usr/local/libexec/magicq-set-mode maintenance
else
    /usr/local/libexec/magicq-set-mode maintenance
fi
EOF

    write_file /usr/local/sbin/magicq-protect 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
if ! mountpoint -q /data || [[ $(findmnt -n -o FSTYPE -M /data) != ext4 ]]; then
    echo "Refusing protected mode: /data is not a separate mounted ext4 filesystem" >&2
    exit 1
fi
if findmnt -n -o FSTYPE / | grep -qx overlay; then
    overlayroot-chroot /usr/local/libexec/magicq-set-mode show
else
    /usr/local/libexec/magicq-set-mode show
fi
EOF

    write_file /usr/local/bin/magicq-status 0755 <<'EOF'
#!/usr/bin/env bash
set -u
os=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")
root_fs=$(findmnt -n -o FSTYPE / 2>/dev/null || echo unknown)
if [[ $root_fs == overlay ]]; then mode=PROTECTED; else mode=MAINTENANCE; fi
data="NOT MOUNTED"
mountpoint -q /data && data="$(findmnt -n -o SOURCE,FSTYPE,OPTIONS -M /data)"
usb=$(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS 2>/dev/null | \
    awk '$2 ~ "^/stick/"' || true)
[[ -n $usb ]] || usb="empty"
magicq="missing"
magicq_pid=$(pgrep -o -x mqqt 2>/dev/null || true)
if [[ $magicq_pid =~ ^[0-9]+$ ]]; then
    magicq="running as $(ps -o user= -p "$magicq_pid" | tr -d ' ')"
elif [[ -x /opt/magicq/runmagicq.sh || -x /opt/magicq/bin/mqqt ]]; then
    magicq="installed, stopped"
fi
supervisor="stopped"
supervisor_pid_file="/run/user/$(id -u chamsys)/wasalight-magicq-session.pid"
if [[ -r $supervisor_pid_file ]]; then
    supervisor_pid=$(<"$supervisor_pid_file")
    [[ $supervisor_pid =~ ^[0-9]+$ ]] && kill -0 "$supervisor_pid" 2>/dev/null && \
        supervisor="running"
fi
network="volatile"
mountpoint -q /etc/NetworkManager/system-connections && network="persistent bind"
unmanaged_devices=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | \
    awk -F: '$2 == "ethernet" || $2 == "wifi" { if ($3 == "unmanaged") print $1 }' | \
    paste -sd, -)
if [[ -n $unmanaged_devices ]]; then
    network="$network; unmanaged: $unmanaged_devices"
else
    network="$network; managed"
fi
touch="unavailable"
[[ -x /usr/local/bin/magicq-touch-status ]] && \
    touch=$(/usr/local/bin/magicq-touch-status --summary 2>/dev/null || echo unavailable)
vnc="stopped"
pgrep -u chamsys -x x11vnc >/dev/null 2>&1 && vnc="running on TCP 5900"
ssh="stopped"
if systemctl is-active --quiet ssh.service; then
    ssh="running on TCP 22 (session)"
    systemctl is-enabled --quiet ssh.service && ssh="running on TCP 22 (automatic)"
fi
logs="unavailable"
[[ -d /data/log && -w /data/log ]] && logs="persistent in /data/log"

cat <<EOT
MagicQ Appliance
OS:         $os
MODE:       $mode
ROOT:       $root_fs
DATA:       $data
MAGICQ:     $magicq
SUPERVISOR: $supervisor
NETWORK:    $network
TOUCH:      $touch
VNC:        $vnc
SSH:        $ssh
USB:        $usb
LOGS:       $logs
EOT
EOF

    write_file /etc/sudoers.d/chamsys-magicq 0440 <<'EOF'
chamsys ALL=(root) NOPASSWD: /usr/local/sbin/magicq-maintenance, /usr/local/sbin/magicq-protect, /usr/local/sbin/magicq-root-launcher, /usr/local/sbin/magicq-root-stop, /usr/local/sbin/wasalight-companion-launcher magichd, /usr/local/sbin/wasalight-companion-launcher magicvis, /usr/local/sbin/wasalight-ip-scan, /usr/local/sbin/wasalight-artnet-capture, /usr/local/sbin/wasalight-power-control poweroff, /usr/local/sbin/wasalight-power-control reboot, /usr/local/sbin/wasalight-ssh-control start, /usr/local/sbin/wasalight-ssh-control stop
EOF
    visudo -cf /etc/sudoers.d/chamsys-magicq >/dev/null
}

configure_boot_branding() {
    local default_logo="$PROJECT_DIR/assets/branding/boot-logo.png"
    local persistent_dir="$DATA_MOUNT/system/branding"
    local persistent_logo="$persistent_dir/boot-logo.png"
    local selected_logo="$default_logo"
    local theme_dir=/usr/share/plymouth/themes/wasalight

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

    plymouth-set-default-theme wasalight
    install -d -m 0755 /etc/default/grub.d
    write_file /etc/default/grub.d/99-wasalight.cfg 0644 <<'EOF'
# Quiet normal boot. Hold Esc during firmware/GRUB hand-off for the boot menu.
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=1
GRUB_RECORDFAIL_TIMEOUT=3
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3 vt.global_cursor_default=0"
EOF
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

final_checks() {
    local writable_path
    bash -n /usr/local/libexec/magicq-usb-mount
    bash -n /usr/local/libexec/magicq-usb-unmount
    bash -n /usr/local/libexec/magicq-set-mode
    bash -n /usr/local/sbin/magicq-maintenance
    bash -n /usr/local/sbin/magicq-protect
    bash -n /usr/local/bin/magicq-status
    bash -n /usr/local/bin/magicq-session
    bash -n /usr/local/sbin/magicq-root-launcher
    bash -n /usr/local/sbin/wasalight-companion-launcher
    bash -n /usr/local/sbin/magicq-root-stop
    bash -n /usr/local/bin/magicq-start
    bash -n /usr/local/bin/magicq-stop
    bash -n /usr/local/bin/magicq-touch
    bash -n /usr/local/bin/magicq-vnc-password
    bash -n /usr/local/bin/magicq-vnc-start
    bash -n /usr/local/bin/magicq-vnc-stop
    bash -n /usr/local/bin/wasalight-power
    bash -n /usr/local/sbin/wasalight-power-control
    bash -n /usr/local/bin/wasalight-desktop-status
    bash -n /usr/local/bin/wasalight-vnc-toggle
    bash -n /usr/local/bin/wasalight-ssh-toggle
    bash -n /usr/local/sbin/wasalight-ssh-control
    bash -n /usr/local/sbin/wasalight-update
    bash -n /usr/local/libexec/wasalight-update-session
    bash -n /usr/local/bin/wasalight-update-terminal
    bash -n /usr/local/bin/wasalight-terminal-tool
    bash -n /usr/local/sbin/wasalight-ip-scan
    bash -n /usr/local/bin/wasalight-ip-scanner
    bash -n /usr/local/bin/wasalight-artnet-monitor
    bash -n /usr/local/sbin/wasalight-app-register
    bash -n /usr/local/bin/wasalight-hub
    python3 -c 'compile(open("/usr/local/libexec/wasalight-hub.py", encoding="utf-8").read(), "/usr/local/libexec/wasalight-hub.py", "exec")'
    python3 -c 'compile(open("/usr/local/libexec/wasalight-ip-scanner.py", encoding="utf-8").read(), "/usr/local/libexec/wasalight-ip-scanner.py", "exec")'
    python3 -c 'compile(open("/usr/local/sbin/wasalight-artnet-capture", encoding="utf-8").read(), "/usr/local/sbin/wasalight-artnet-capture", "exec")'
    python3 -c 'compile(open("/usr/local/libexec/wasalight-artnet-monitor.py", encoding="utf-8").read(), "/usr/local/libexec/wasalight-artnet-monitor.py", "exec")'
    [[ -s /usr/share/plymouth/themes/wasalight/boot-logo.png ]] || \
        die "Wasalight Plymouth boot logo is unavailable"
    [[ $(plymouth-set-default-theme) == wasalight ]] || \
        die "Wasalight is not the active Plymouth theme"
    [[ -r /etc/default/grub.d/99-wasalight.cfg ]] || \
        die "Wasalight quiet GRUB configuration is unavailable"
    logrotate --debug /etc/wasalight/magicq-logrotate.conf >/dev/null 2>&1
    ldconfig -p | grep -F 'libGLU.so.1' >/dev/null || \
        die "OpenGL runtime check failed: libGLU.so.1 is unavailable"
    [[ -r /usr/share/alsa/alsa.conf ]] || \
        die "MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable"
    python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf; GdkPixbuf.Pixbuf.new_from_file("/usr/local/share/icons/wasalight/start.svg")' || \
        die "desktop SVG icon loader is unavailable"
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
        /etc/systemd/system/magicq-usb@.service \
        /etc/systemd/system/magicq-logrotate.service \
        /etc/systemd/system/magicq-logrotate.timer
    systemctl daemon-reload
    netplan generate
    [[ -r /etc/netplan/99-wasalight-networkmanager.yaml ]] || \
        die "NetworkManager Netplan renderer configuration is unavailable"
    command -v wmctrl >/dev/null || \
        die "MagicQ fullscreen control is unavailable: wmctrl is missing"
    desktop-file-validate "$TARGET_HOME"/Desktop/*.desktop
    desktop-file-validate /etc/wasalight/apps.d/*.desktop
    runuser -u "$TARGET_USER" -- test ! -w "$TARGET_HOME/Desktop" || \
        die "the appliance desktop is still writable by $TARGET_USER"
    conky --version >/dev/null || die "Wasalight desktop status is unavailable"
}

main() {
    parse_args "$@"
    require_host
    configure_data_mount
    persist_magicq_package
    install_packages
    configure_user
    configure_networkmanager
    configure_persistent_logs
    configure_touchscreen
    configure_vnc
    configure_ssh
    configure_update
    configure_graphical_session
    configure_usb
    install_magicq
    repair_magicq_persistent_permissions
    configure_volatile_runtime
    optimize_system
    install_mode_commands
    configure_boot_branding
    configure_overlay
    final_checks

    log "installation completed"
    if ((ENABLE_PROTECTION)); then
        cat <<'EOF'

Next boot: PROTECTED SHOW mode.
  Status:       magicq-status
  Maintenance: sudo magicq-maintenance  (then reboot)
  Protect:     sudo magicq-protect      (then reboot)

Every supported USB medium is mounted in its own /stick/<device> directory.
Synchronous writes reduce, but cannot eliminate, corruption if a stick is
removed during an active write.
EOF
    else
        warn "overlay protection is disabled; run sudo magicq-protect when /data is ready"
    fi
}

main "$@"
