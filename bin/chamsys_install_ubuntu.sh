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
readonly RELEASE_MANIFEST="$PROJECT_DIR/release-manifest.ini"
# shellcheck source=../lib/wasalight-release-manifest.sh
. "$PROJECT_DIR/lib/wasalight-release-manifest.sh"
# shellcheck source=../lib/wasalight-operation-lock.sh
. "$PROJECT_DIR/lib/wasalight-operation-lock.sh"
readonly VERSION_FILE_NAME="$(require_manifest_value "$RELEASE_MANIFEST" Wasalight VersionFile)"
readonly PROJECT_VERSION="$(<"$PROJECT_DIR/$VERSION_FILE_NAME")"
PROJECT_COMMIT=unknown
if command -v git >/dev/null 2>&1 && [[ -d $PROJECT_DIR/.git ]]; then
    detected_project_commit=$(git -C "$PROJECT_DIR" rev-parse --verify HEAD 2>/dev/null || true)
    [[ $detected_project_commit =~ ^[0-9a-f]{40}$ ]] && PROJECT_COMMIT=$detected_project_commit
fi
readonly PROJECT_COMMIT
unset detected_project_commit
readonly TARGET_UBUNTU_VERSION="$(require_manifest_value "$RELEASE_MANIFEST" Platform UbuntuVersion)"
readonly TARGET_ARCHITECTURE="$(require_manifest_value "$RELEASE_MANIFEST" Platform Architecture)"
readonly TARGET_USER="chamsys"
readonly TARGET_HOME="/home/${TARGET_USER}"
readonly DATA_MOUNT="/data"
readonly USB_MOUNT="/stick"
readonly OVERLAY_CONF="/etc/overlayroot.local.conf"
readonly UPDATE_CHECKOUT="/data/system/wasalight"
readonly PACKAGE_STORE="/data/system/packages"
readonly UPDATE_REPOSITORY="$(require_manifest_value "$RELEASE_MANIFEST" Wasalight Repository)"
readonly UPDATE_BRANCH="$(require_manifest_value "$RELEASE_MANIFEST" Wasalight Branch)"
readonly COMPANION_REPOSITORY="$(require_manifest_value "$RELEASE_MANIFEST" Companion Repository)"
readonly COMPANION_PI_COMMIT="$(require_manifest_value "$RELEASE_MANIFEST" Companion Commit)"
readonly COMPANION_VERSION="$(require_manifest_value "$RELEASE_MANIFEST" Companion Version)"
readonly COMPANION_ICON_COMMIT="$(require_manifest_value "$RELEASE_MANIFEST" Companion IconCommit)"
readonly COMPANION_ICON_SHA256="$(require_manifest_value "$RELEASE_MANIFEST" Companion IconSHA256)"
readonly MAGICQ_PACKAGE_NAME="$(require_manifest_value "$RELEASE_MANIFEST" MagicQ Package)"
readonly MAGICQ_ARCHITECTURE="$(require_manifest_value "$RELEASE_MANIFEST" MagicQ Architecture)"

DEB_PATH=""
DATA_DEVICE=""
SSH_AUTOSTART_MODE=preserve
PURGE_CLOUD_INIT=1
ENABLE_PROTECTION=1
ENABLE_COMPANION=0
REQUESTED_PLUGINS=()
RESET_CHAMSYS_PASSWORD=0
ALLOW_MISSING_MAGICQ=0
BOOTSTRAP_MAGICQ_PATH=""
BOOTSTRAP_MAGICQ_VERSION=""
BOOTSTRAP_TEMP_MOUNTS=()


readonly INSTALLER_MODULE_DIR="$PROJECT_DIR/installer/modules"
for installer_module in "$INSTALLER_MODULE_DIR"/*.sh; do
    # shellcheck source=/dev/null
    . "$installer_module"
done
unset installer_module

main() {
    parse_args "$@"
    require_host
    wasalight_acquire_operation_lock "installazione Wasalight"
    log "starting Wasalight installer version $PROJECT_VERSION"
    configure_data_mount
    discover_magicq_from_usb
    persist_magicq_package
    require_magicq_or_override
    install_packages
    configure_user
    configure_networkmanager
    configure_persistent_logs
    configure_touchscreen
    configure_vnc
    configure_ssh
    configure_remote_persistence
    configure_update
    configure_companion
    configure_graphical_session
    configure_plugins
    configure_management_tools
    configure_usb
    install_magicq
    repair_magicq_persistent_permissions
    configure_volatile_runtime
    optimize_system
    install_mode_commands
    configure_boot_branding
    configure_overlay
    final_checks
    record_installed_version

    log "installation completed: Wasalight $PROJECT_VERSION"
    if ((ENABLE_PROTECTION)); then
        cat <<'EOF'

Next boot: PROTECTED SHOW mode.
  Status:       wasalight-status
  Maintenance: sudo wasalight-maintenance  (then reboot)
  Protect:     sudo wasalight-protect      (then reboot)

Every supported USB medium is mounted in its own /stick/<device> directory.
Synchronous writes reduce, but cannot eliminate, corruption if a stick is
removed during an active write.
EOF
    else
        warn "overlay protection is disabled; run sudo wasalight-protect when /data is ready"
    fi
}

main "$@"
