# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

installer_progress() {
    local message=$* temporary
    if [[ -n ${INSTALLER_PREVIOUS_PROGRESS:-} ]]; then
        log "✓ $INSTALLER_PREVIOUS_PROGRESS"
    fi
    INSTALLER_PREVIOUS_PROGRESS=$message
    log "→ $message"
    [[ ${WASALIGHT_PROGRESS_FILE:-} == /run/wasalight-update-progress-detail ]] || return 0
    temporary=$(mktemp /run/.wasalight-progress.XXXXXX)
    printf '%s\n' "$message" >"$temporary"
    chmod 0644 "$temporary"
    mv -f -- "$temporary" "$WASALIGHT_PROGRESS_FILE"
}

installer_progress_complete() {
    [[ -n ${INSTALLER_PREVIOUS_PROGRESS:-} ]] || return 0
    log "✓ $INSTALLER_PREVIOUS_PROGRESS"
    INSTALLER_PREVIOUS_PROGRESS=
}

verify_project_sources() {
    if [[ ${WASALIGHT_UPDATE_TRANSACTION:-0} == 1 && \
          ${WASALIGHT_VERIFIED_COMMIT:-} == "$PROJECT_COMMIT" && \
          $PROJECT_COMMIT =~ ^[0-9a-f]{40}$ ]]; then
        log "project commit $PROJECT_COMMIT was already verified by WasaUpdate"
        return 0
    fi

    log "verifying project sources with the installed runtime"
    "$PROJECT_DIR/tests/verify-project.sh"
}

on_error() {
    local rc=$?
    printf '[%s] ERROR: command failed at line %s (exit %s): %s\n' \
        "$SCRIPT_NAME" "${BASH_LINENO[0]:-?}" "$rc" "${BASH_COMMAND:-?}" >&2
    exit "$rc"
}
trap on_error ERR

cleanup_bootstrap_mounts() {
    local mount_dir
    set +e
    for mount_dir in "${BOOTSTRAP_TEMP_MOUNTS[@]-}"; do
        [[ -n $mount_dir ]] || continue
        mountpoint -q "$mount_dir" && umount "$mount_dir"
        rmdir "$mount_dir" 2>/dev/null || true
    done
    case $BOOTSTRAP_MAGICQ_PATH in
        "$PACKAGE_STORE"/.wasalight-usb-candidate.*)
            rm -f -- "$BOOTSTRAP_MAGICQ_PATH"
            ;;
    esac
}
trap cleanup_bootstrap_mounts EXIT

usage() {
    cat <<'EOF'
Usage:
  sudo ./chamsys_install_ubuntu.sh [options] [magicq_package.deb]

Options:
  --data-device SPEC   Existing ext4 filesystem for /data. SPEC may be a
                       device path, UUID=..., or LABEL=.... It is never formatted.
  --with-ssh           Persistently enable OpenSSH after every reboot.
  --without-ssh        Persistently disable automatic OpenSSH startup.
  --with-companion     Install the pinned Bitfocus Companion headless build,
                       persist its configuration in /data and enable its service.
  --plugin ID          Enable a Wasalight plugin. May be repeated. Built-in IDs:
                       companion, ssh, vnc. --with-companion remains supported.
  --reset-chamsys-password
                       Interactively replace the chamsys password. The account
                       is always an administrator; its password is never stored.
  --keep-cloud-init    Disable cloud-init services but retain the package.
  --no-protection      Configure the appliance but leave overlayroot disabled.
  --allow-missing-magicq
                       Continue explicitly when MagicQ is neither installed nor
                       available as a valid amd64 .deb.
  --version            Show the Wasalight installer version and exit.
  -h, -help, --help    Show this complete help.

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
            --with-ssh) SSH_AUTOSTART_MODE=enabled; shift ;;
            --without-ssh) SSH_AUTOSTART_MODE=disabled; shift ;;
            --with-companion) ENABLE_COMPANION=1; shift ;;
            --plugin)
                (($# >= 2)) || die "--plugin requires an id"
                case $2 in
                    companion) ENABLE_COMPANION=1 ;;
                    ssh) ;;
                    vnc) ;;
                    *) die "unknown Wasalight plugin: $2" ;;
                esac
                REQUESTED_PLUGINS+=("$2")
                shift 2
                ;;
            --reset-chamsys-password) RESET_CHAMSYS_PASSWORD=1; shift ;;
            --keep-cloud-init) PURGE_CLOUD_INIT=0; shift ;;
            --no-protection) ENABLE_PROTECTION=0; shift ;;
            --allow-missing-magicq) ALLOW_MISSING_MAGICQ=1; shift ;;
            --version) printf '%s\n' "$PROJECT_VERSION"; exit 0 ;;
            -h|-help|--help) usage; exit 0 ;;
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
    [[ $PROJECT_VERSION =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]] || \
        die "invalid or missing Wasalight VERSION: $PROJECT_VERSION"
    [[ $EUID -eq 0 ]] || die "run this installer as root (sudo)"
    [[ -r /etc/os-release ]] || die "/etc/os-release is missing"
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ ${ID:-} == ubuntu && ${VERSION_ID:-} == "$TARGET_UBUNTU_VERSION" ]] || \
        die "this release targets Ubuntu Server $TARGET_UBUNTU_VERSION LTS; found ${PRETTY_NAME:-unknown}"
    [[ $(dpkg --print-architecture) == "$TARGET_ARCHITECTURE" ]] || \
        die "MagicQ appliance requires $TARGET_ARCHITECTURE"
    [[ $(findmnt -n -o FSTYPE /) != overlay ]] || \
        die "run the installer in MAINTENANCE mode, not through the active root overlay"

    if [[ -n "$DEB_PATH" ]]; then
        DEB_PATH=$(readlink -f -- "$DEB_PATH")
        [[ -f "$DEB_PATH" ]] || die "MagicQ package not found: $DEB_PATH"
        dpkg-deb --info "$DEB_PATH" >/dev/null || die "invalid Debian package: $DEB_PATH"
        [[ $(dpkg-deb -f "$DEB_PATH" Package) == "$MAGICQ_PACKAGE_NAME" ]] || \
            die "the Debian package is not ChamSys MagicQ: $DEB_PATH"
        [[ $(dpkg-deb -f "$DEB_PATH" Architecture) == "$MAGICQ_ARCHITECTURE" ]] || \
            die "the MagicQ package is not amd64"
        local magicq_deb_version
        magicq_deb_version=$(dpkg-deb -f "$DEB_PATH" Version)
        dpkg --validate-version "$magicq_deb_version" >/dev/null 2>&1 || \
            die "the MagicQ package has an invalid version: $magicq_deb_version"
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

install_template() {
    local path=$1 mode=$2
    local source="$PROJECT_DIR/installer/templates/rootfs$path"
    [[ -f $source ]] || die "installer template is missing: $source"
    install -D -m "$mode" "$source" "$path"
}

ensure_fstab_line() {
    local marker=$1 line=$2
    if ! grep -Fqx "$line" /etc/fstab; then
        printf '\n# %s\n%s\n' "$marker" "$line" >>/etc/fstab
    fi
}
