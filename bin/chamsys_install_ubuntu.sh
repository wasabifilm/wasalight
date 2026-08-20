#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
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
    installer_progress "1/25 · Preparazione partizione dati"
    configure_data_mount
    installer_progress "2/25 · Ricerca del pacchetto MagicQ"
    discover_magicq_from_usb
    persist_magicq_package
    require_magicq_or_override
    installer_progress "3/25 · Installazione pacchetti di sistema"
    install_packages
    installer_progress "4/25 · Configurazione utente chamsys"
    configure_user
    installer_progress "5/25 · Configurazione rete persistente"
    configure_networkmanager
    installer_progress "6/25 · Configurazione log persistenti"
    configure_persistent_logs
    installer_progress "7/25 · Configurazione touchscreen"
    configure_touchscreen
    installer_progress "8/25 · Configurazione VNC"
    configure_vnc
    installer_progress "9/25 · Configurazione SSH"
    configure_ssh
    configure_remote_persistence
    installer_progress "10/25 · Configurazione aggiornamenti"
    configure_update
    installer_progress "11/25 · Configurazione Companion"
    configure_companion
    installer_progress "12/25 · Configurazione desktop"
    configure_graphical_session
    installer_progress "13/25 · Configurazione plugin"
    configure_plugins
    installer_progress "14/25 · Installazione strumenti di gestione"
    configure_management_tools
    installer_progress "15/25 · Configurazione supporti USB"
    configure_usb
    installer_progress "16/25 · Installazione MagicQ"
    install_magicq
    installer_progress "17/25 · Verifica permessi MagicQ"
    repair_magicq_persistent_permissions
    installer_progress "18/25 · Configurazione runtime volatile"
    configure_volatile_runtime
    installer_progress "19/25 · Installazione licenze e crediti"
    install_wasalight_legal_notices
    installer_progress "20/25 · Ottimizzazione del sistema"
    optimize_system
    installer_progress "21/25 · Installazione comandi SHOW e MAINTENANCE"
    install_mode_commands
    installer_progress "22/25 · Configurazione grafica di avvio"
    configure_boot_branding
    installer_progress "23/25 · Configurazione protezione overlayroot"
    configure_overlay
    installer_progress "24/25 · Controlli finali"
    final_checks
    installer_progress "25/25 · Registrazione versione installata"
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
