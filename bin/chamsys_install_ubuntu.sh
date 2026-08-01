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
readonly TARGET_USER="chamsys"
readonly TARGET_HOME="/home/${TARGET_USER}"
readonly DATA_MOUNT="/data"
readonly USB_MOUNT="/stick"
readonly OVERLAY_CONF="/etc/overlayroot.local.conf"

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
  --with-ssh           Install and enable OpenSSH server.
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
    install -d -m 0750 "$DATA_MOUNT/log"
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
        openbox tint2 pcmanfm lxterminal lxrandr x11vnc procps
        network-manager network-manager-gnome policykit-1 policykit-1-gnome
        overlayroot initramfs-tools chrony
        exfatprogs ntfs-3g dosfstools util-linux udev logrotate
    )
    ((ENABLE_SSH)) && packages+=(openssh-server)
    ((ENABLE_ONSCREEN_KEYBOARD)) && packages+=(onboard)
    apt_install "${packages[@]}"

    systemctl enable NetworkManager.service chrony.service
    if ((ENABLE_SSH)); then
        systemctl enable ssh.service
    else
        systemctl disable --now ssh.service 2>/dev/null || true
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
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.local/share"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/openbox"
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/pcmanfm/default"
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

session_event() {
    event_message=$1
    printf '%s %s\n' "$(date -Is)" "$event_message" >>"$session_log"
    logger -t magicq-session "$event_message"
}

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

    write_file "$TARGET_HOME/.config/openbox/autostart" 0755 <<'EOF'
#!/bin/sh
xset s off
xset s noblank
xset -dpms
tint2 &
nm-applet --indicator &
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
/usr/local/bin/magicq-touch-watch &
/usr/local/bin/magicq-session &
EOF

    local keyboard_item=''
    if ((ENABLE_ONSCREEN_KEYBOARD)); then
        keyboard_item='    <item label="On-screen keyboard"><action name="Execute"><command>onboard</command></action></item>'
    fi
    write_file "$TARGET_HOME/.config/openbox/menu.xml" 0644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="MagicQ Appliance">
    <item label="Start MagicQ"><action name="Execute"><command>/usr/local/bin/magicq-session</command></action></item>
    <separator />
    <item label="Network settings"><action name="Execute"><command>nm-connection-editor</command></action></item>
    <item label="Display settings"><action name="Execute"><command>lxrandr</command></action></item>
${keyboard_item}
    <item label="Touchscreen status"><action name="Execute"><command>lxterminal -e magicq-touch-status</command></action></item>
    <item label="File manager"><action name="Execute"><command>pcmanfm</command></action></item>
    <item label="Terminal"><action name="Execute"><command>lxterminal</command></action></item>
    <separator />
    <item label="System status"><action name="Execute"><command>lxterminal -e magicq-status</command></action></item>
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

    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" "$TARGET_HOME/.xinitrc"

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
        for log_file in wasalight-magicq-console.log wasalight-magicq-session.log; do
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
/data/log/wasalight-magicq-console.log /data/log/wasalight-magicq-session.log {
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
[[ -x /opt/magicq/runmagicq.sh || -x /opt/magicq/bin/mqqt ]] && magicq="installed"
network="volatile"
mountpoint -q /etc/NetworkManager/system-connections && network="persistent bind"
touch="unavailable"
[[ -x /usr/local/bin/magicq-touch-status ]] && \
    touch=$(/usr/local/bin/magicq-touch-status --summary 2>/dev/null || echo unavailable)
vnc="stopped"
pgrep -u chamsys -x x11vnc >/dev/null 2>&1 && vnc="running on TCP 5900"
logs="unavailable"
[[ -d /data/log && -w /data/log ]] && logs="persistent in /data/log"

cat <<EOT
MagicQ Appliance
OS:         $os
MODE:       $mode
ROOT:       $root_fs
DATA:       $data
MAGICQ:     $magicq
NETWORK:    $network
TOUCH:      $touch
VNC:        $vnc
USB:        $usb
LOGS:       $logs
EOT
EOF

    write_file /etc/sudoers.d/chamsys-magicq 0440 <<'EOF'
chamsys ALL=(root) NOPASSWD: /usr/local/sbin/magicq-maintenance, /usr/local/sbin/magicq-protect, /usr/local/sbin/magicq-root-launcher
EOF
    visudo -cf /etc/sudoers.d/chamsys-magicq >/dev/null
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
    bash -n /usr/local/bin/magicq-touch
    bash -n /usr/local/bin/magicq-vnc-password
    bash -n /usr/local/bin/magicq-vnc-start
    bash -n /usr/local/bin/magicq-vnc-stop
    logrotate --debug /etc/wasalight/magicq-logrotate.conf >/dev/null 2>&1
    ldconfig -p | grep -F 'libGLU.so.1' >/dev/null || \
        die "OpenGL runtime check failed: libGLU.so.1 is unavailable"
    [[ -r /usr/share/alsa/alsa.conf ]] || \
        die "MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable"
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
    systemctl restart NetworkManager.service
}

main() {
    parse_args "$@"
    require_host
    configure_data_mount
    install_packages
    configure_user
    configure_persistent_logs
    configure_touchscreen
    configure_vnc
    configure_graphical_session
    configure_usb
    install_magicq
    configure_volatile_runtime
    optimize_system
    install_mode_commands
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
