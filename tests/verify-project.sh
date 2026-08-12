#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER_ENTRY="$PROJECT_DIR/bin/chamsys_install_ubuntu.sh"
INSTALLER="$INSTALLER_ENTRY"
INSTALLER_MODULE_DIR="$PROJECT_DIR/installer/modules"
INSTALLER_TEMPLATE_ROOT="$PROJECT_DIR/installer/templates/rootfs"
ENTRYPOINT="$PROJECT_DIR/install.sh"
VERSION_FILE="$PROJECT_DIR/VERSION"
RELEASE_MANIFEST="$PROJECT_DIR/release-manifest.ini"
ISO_BUILDER_RELEASE_TEST="$PROJECT_DIR/Minimal-ISO-Builder/tests/verify-release-config.sh"
tmp_dir=$(mktemp -d)
vnc_test_pid=
cleanup() {
    if [[ ${vnc_test_pid:-} =~ ^[0-9]+$ ]]; then
        kill "$vnc_test_pid" 2>/dev/null || true
    fi
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'ERRORE: %s\n' "$*" >&2
    exit 1
}

"$PROJECT_DIR/tests/behavior/run.sh"

[[ -x "$INSTALLER" ]] || fail "installer mancante o non eseguibile"
[[ -x "$ENTRYPOINT" ]] || fail "install.sh mancante o non eseguibile"
[[ -s "$VERSION_FILE" ]] || fail "file VERSION mancante"
project_version=$(<"$VERSION_FILE")
[[ $project_version =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]] || \
    fail "VERSION non usa il formato AAAA.MM.GG.BUILD"
[[ $("$ENTRYPOINT" --version) == "$project_version" ]] || \
    fail "install.sh --version non corrisponde a VERSION"
help_output=$("$ENTRYPOINT" -help)
grep -Fq -- '--allow-missing-magicq' <<<"$help_output" || \
    fail "-help non mostra l'opzione per continuare senza MagicQ"
grep -Fq -- '--data-device SPEC' <<<"$help_output" || \
    fail "-help non mostra tutte le opzioni dell'installer"
grep -Fq -- '--with-companion' <<<"$help_output" || \
    fail "-help non mostra l'installazione opzionale di Bitfocus Companion"
grep -Fq -- '--without-ssh' <<<"$help_output" || \
    fail "-help non mostra la disattivazione persistente di SSH"
grep -Fq -- '--plugin ID' <<<"$help_output" || \
    fail "-help non mostra il sistema plugin Wasalight"
grep -Fq '/data/system/packages/*.deb' "$ENTRYPOINT" || \
    fail "install.sh non riutilizza il pacchetto MagicQ persistente"
grep -Fq '^/stick/[^/]+$' "$ENTRYPOINT" || \
    fail "install.sh non cerca MagicQ nelle USB realmente montate"
grep -Fq '$usb_mount/packages' "$ENTRYPOINT" || \
    fail "install.sh non cerca MagicQ nella cartella packages della USB"
grep -Fq 'dpkg --compare-versions' "$ENTRYPOINT" || \
    fail "install.sh sceglie MagicQ dal nome file invece che dalla versione Debian"
grep -Fq "dpkg-query -W -f='\${db:Status-Abbrev}' magicq" "$ENTRYPOINT" || \
    fail "install.sh non riconosce una MagicQ già installata quando manca il .deb"

bash -n "$INSTALLER"
bash -n "$ENTRYPOINT"
[[ -d $INSTALLER_MODULE_DIR ]] || fail "directory moduli installer mancante"
installer_modules=()
while IFS= read -r module; do
    installer_modules+=("$module")
done < <(find "$INSTALLER_MODULE_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
((${#installer_modules[@]} >= 8)) || fail "installer non sufficientemente suddiviso in moduli"
for module in "${installer_modules[@]}"; do
    bash -n "$module"
done
[[ -d $INSTALLER_TEMPLATE_ROOT ]] || fail "directory template installer mancante"
template_count=0
while IFS= read -r template; do
    template_count=$((template_count + 1))
    case $(head -n 1 "$template") in
        '#!/usr/bin/env bash'|'#!/bin/bash') bash -n "$template" ;;
        '#!/usr/bin/env python3')
            python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
                "$template" ;;
    esac
done < <(find "$INSTALLER_TEMPLATE_ROOT" -type f | sort)
((template_count >= 100)) || fail "troppi file statici sono ancora incorporati nei moduli"
installer_combined="$tmp_dir/chamsys-installer-combined.sh"
{
    cat "$INSTALLER_ENTRY"
    for module in "${installer_modules[@]}"; do cat "$module"; done
    while IFS= read -r template; do cat "$template"; done \
        < <(find "$INSTALLER_TEMPLATE_ROOT" -type f | sort)
} >"$installer_combined"
INSTALLER="$installer_combined"

[[ -s $RELEASE_MANIFEST ]] || fail "release-manifest.ini mancante"
for declaration in \
    '[Wasalight]' 'VersionFile=VERSION' \
    'Repository=https://github.com/wasabifilm/wasalight.git' 'Branch=main' \
    'VersionURL=https://raw.githubusercontent.com/wasabifilm/wasalight/main/VERSION' \
    '[Platform]' 'UbuntuVersion=24.04' 'Architecture=amd64' \
    '[ISOBuilder]' 'VersionFile=Minimal-ISO-Builder/VERSION' \
    'UbuntuPointRelease=24.04.4' \
    'LiveISOFile=ubuntu-24.04.4-live-server-amd64.iso' \
    'LiveISOURL=https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso' \
    'LiveISOSize=3405469696' \
    'LiveISOSHA256=e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433' \
    'MiniISOFile=ubuntu-mini-iso-24.04.4-mini-iso-amd64.iso' \
    'MiniISOSHA256=57bfe99e776698ae08358145cf3a58bfb74beafe8c8cf965ca86552233d2f53f' \
    '[Companion]' 'Version=5.0.3' \
    'Commit=07024263dbb54512f3acdc705eca70cd74dbae43'; do
    grep -Fqx "$declaration" "$RELEASE_MANIFEST" || \
        fail "valore release centralizzato mancante: $declaration"
done
[[ -s $ISO_BUILDER_RELEASE_TEST ]] || fail "test configurazione ISO Builder mancante"
bash "$ISO_BUILDER_RELEASE_TEST"

lock_library="$PROJECT_DIR/lib/wasalight-operation-lock.sh"
[[ -s $lock_library ]] || fail "libreria lock globale mancante"
grep -Fq 'wasalight_acquire_operation_lock "installazione Wasalight"' "$ENTRYPOINT" || \
    fail "install.sh non acquisisce il lock globale"
for locked_tool in \
    "$INSTALLER_TEMPLATE_ROOT/usr/local/sbin/wasalight-update" \
    "$PROJECT_DIR/libexec/wasalight-update-snapshot" \
    "$PROJECT_DIR/libexec/wasalight-data-transfer"; do
    grep -Fq 'wasalight_acquire_operation_lock' "$locked_tool" || \
        fail "operazione mutante priva di lock globale: $locked_tool"
done
rollback_tool="$PROJECT_DIR/libexec/wasalight-rollback"
rollback_ui="$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-rollback-ui"
grep -Fq 'head -n 5' "$rollback_tool" || fail "il rollback non limita la lista agli ultimi cinque snapshot"
grep -Fq 'sha256sum -c' "$rollback_tool" || fail "il rollback non verifica i checksum"
grep -Fq '!= overlay' "$rollback_tool" || fail "il rollback non richiede MAINTENANCE"
grep -Fq 'pkexec /usr/local/sbin/wasalight-rollback restore' "$rollback_ui" || \
    fail "l’interfaccia rollback non richiede autenticazione amministrativa"
grep -Fq 'pkexec /usr/local/sbin/wasalight-rollback delete' "$rollback_ui" || \
    fail "l’interfaccia rollback non protegge l’eliminazione con autenticazione"
grep -Fq 'Elimina definitivamente' "$rollback_ui" || \
    fail "l’interfaccia rollback elimina snapshot senza seconda conferma"
delete_branch_line=$(grep -n "^if \[\[ \$action == 'Elimina snapshot' \]\]; then$" \
    "$rollback_ui" | cut -d: -f1)
integrity_block_line=$(grep -n '^if \[\[ \$integrity != OK \]\]; then$' \
    "$rollback_ui" | cut -d: -f1)
[[ $delete_branch_line =~ ^[0-9]+$ && $integrity_block_line =~ ^[0-9]+$ ]] || \
    fail "ordine eliminazione/checksum snapshot non verificabile"
((integrity_block_line > delete_branch_line)) || \
    fail "una snapshot non integra non può essere eliminata dalla GUI"
grep -Fq 'delete) operation="eliminazione snapshot Wasalight"' \
    "$PROJECT_DIR/libexec/wasalight-update-snapshot" || \
    fail "l’eliminazione snapshot non acquisisce il lock globale"
grep -Fq 'exec "$snapshot_tool" delete "$archive"' "$rollback_tool" || \
    fail "il rollback non delega la cancellazione al gestore snapshot"
if grep -Fq 'wasalight-rollback' \
        "$INSTALLER_TEMPLATE_ROOT/etc/sudoers.d/wasalight-management"; then
    fail "il rollback non deve essere autorizzato permanentemente senza password"
fi
companion_web_launcher="$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/companion-web.desktop"
grep -Fq 'Icon=/usr/local/share/icons/wasalight/companion-official.png' \
    "$companion_web_launcher" || fail "Falkon Companion non usa l’icona ufficiale"
grep -Fq 'StartupWMClass=WasalightCompanion' "$companion_web_launcher" || \
    fail "il launcher Companion non usa una classe finestra dedicata"

management_helpers=(
    wasalight-health wasalight-health-monitor wasalight-support-bundle wasalight-data-transfer
    wasalight-first-run wasalight-magicq-usb-watch wasalight-plugin-bundle
    wasalight-update-snapshot wasalight-rollback
)
for helper in "${management_helpers[@]}"; do
    [[ -x "$PROJECT_DIR/libexec/$helper" ]] || fail "helper non eseguibile: $helper"
    bash -n "$PROJECT_DIR/libexec/$helper"
done
for helper in \
    "$PROJECT_DIR/libexec/wasalight-plugin" \
    "$PROJECT_DIR/libexec/wasalight-plugin-admin" \
    "$PROJECT_DIR/ui/wasalight-control-center.py"; do
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$helper"
done

required_patterns=(
    'VERSION_ID:-} == "$TARGET_UBUNTU_VERSION"'
    'PROJECT_VERSION="$(<"$PROJECT_DIR/$VERSION_FILE_NAME")"'
    'PROJECT_COMMIT=unknown'
    '/etc/wasalight/version'
    '/etc/wasalight/commit'
    '$DATA_MOUNT/system/installed-version'
    '$DATA_MOUNT/system/installed-commit'
    "status_line \"\$blue\" 'VERSION'"
    "status_line \"\$yellow\" 'UPDATE' \"READY · \$checked_version\""
    'checked_version=$(cat /data/system/update-check/latest-version'
    '${goto 150}'
    "status_line \"\$blue\" 'MAGICQ VER'"
    "status_line \"\$red\" 'MAGICQ VER' 'NOT INSTALLED'"
    "dpkg-query -W -f='\${db:Status-Abbrev}\\t\${Version}' magicq"
    'WASALIGHT:  $version'
    'MAGICQ VER: $magicq_version'
    'record_installed_version'
    'add-apt-repository -y universe'
    'overlayroot="tmpfs:swap=0,recurse=0"'
    '$TARGET_HOME/Documents/MagicQ'
    '$TARGET_HOME/.local/share'
    '/etc/NetworkManager/system-connections'
    'wasalight-usb@%k.service'
    'discover_magicq_from_usb'
    'ID_BUS=usb'
    '/run/wasalight-usb-scan'
    'mount -o ro,nosuid,nodev,noexec'
    'scan_bootstrap_magicq_directory "$mount_dir"'
    'require_magicq_or_override'
    'readonly USB_MOUNT="/stick"'
    'mountpoint="$base/$dev_name"'
    'state="$state_dir/$dev_name.mount"'
    '[[ $(dpkg-deb -f "$DEB_PATH" Package) == "$MAGICQ_PACKAGE_NAME" ]]'
    'wasalight-maintenance'
    'wasalight-protect'
    'wasalight-mode-toggle'
    'wasalight-status'
    'OS:         $os'
    'xinput libinput-tools'
    'libglu1-mesa libgl1-mesa-dri'
    'libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0'
    'libxcb-keysyms1 libxcb-randr0 libxcb-render0 libxcb-render-util0'
    'libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0'
    'libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libxcb-cursor0'
    'libasound2-data alsa-utils'
    'openbox tint2 picom pcmanfm lxterminal lxrandr lxtask x11vnc procps wmctrl x11-utils'
    'conky-all zenity libnotify-bin libglib2.0-bin desktop-file-utils librsvg2-common'
    'python3 python3-gi gir1.2-gtk-3.0'
    'arp-scan iproute2'
    'plymouth plymouth-themes file'
    '/etc/netplan/99-wasalight-networkmanager.yaml'
    'renderer: NetworkManager'
    'netplan apply'
    'network-manager network-manager-gnome wpasupplicant'
    'libfsapfs-utils util-linux udev logrotate'
    'fsapfsmount -X ro,allow_other,nosuid,nodev,noexec'
    'Mounted $dev (APFS) read-only'
    'ID_FS_TYPE}=="vfat|exfat|ntfs|apfs"'
    "grep -F 'libGLU.so.1'"
    'MagicQ has unresolved runtime libraries'
    'MagicQ Qt xcb platform plugin has unresolved runtime libraries'
    'MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable'
    '--with-onscreen-keyboard'
    '--allow-missing-magicq'
    'MagicQ is not installed and no valid .deb was found locally or on USB.'
    '--reset-chamsys-password'
    'audio video plugdev sudo adm systemd-journal'
    'passwd "$TARGET_USER"'
    '/data/system/touchscreen/config'
    'wasalight-touch-status'
    'wasalight-touch-config'
    'wasalight-touch-watch'
    'wasalight-vnc-start'
    'wasalight-vnc-stop'
    'wasalight-remote-auto-toggle'
    'wasalight-remote-autostart'
    'wasalight-remote-persistence'
    'magicq-fullscreen-watch'
    'wasalight-audio-test'
    'wmctrl -n 1'
    '/usr/local/bin/wasalight-desktop-wallpaper'
    'wallpaper_mode=stretch'
    'wallpapers_configured=1'
    'desktop_bg=#080b10'
    'pcmanfm --desktop --profile=default'
    '$TARGET_HOME/.config/wasalight/dock/Wasalight-Control.desktop'
    '$TARGET_HOME/.config/wasalight/dock/Files.desktop'
    '$TARGET_HOME/Desktop/MagicQ.desktop'
    '$TARGET_HOME/Desktop/Power-Off.desktop'
    '$TARGET_HOME/Desktop/Reboot.desktop'
    'Icon=/usr/local/share/icons/wasalight/hub.svg'
    'Icon=/usr/local/share/icons/wasalight/files.svg'
    'Icon=/usr/local/share/icons/wasalight/power.svg'
    'Icon=/usr/local/share/icons/wasalight/reboot.svg'
    'conky --config="$HOME/.config/conky/wasalight.conf"'
    'wasalight-desktop-status'
    'wasalight-power-control poweroff'
    'wasalight-vnc-toggle'
    'wasalight-ssh-toggle'
    'wasalight-update'
    '${execpi 2 /usr/local/bin/wasalight-desktop-status}'
    '/data/system/wasalight'
    '/data/system/packages'
    'candidate_checkout=$(mktemp -d "${checkout}.candidate.XXXXXX")'
    '/etc/wasalight/apps.d/network.desktop'
    '/data/system/apps.d'
    'wasalight-app-register'
    'taskbar_name = 0'
    'autohide = 0'
    'strut_policy = follow_size'
    'launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Wasalight-Control.desktop'
    'launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Files.desktop'
    'quick_exec=1'
    'chown -R root:root "$TARGET_HOME/Desktop"'
    '-exec chmod 0444 {} +'
    'desktop SVG icon loader is unavailable'
    'background_color = #080b10 98'
    '/usr/share/themes/Wasalight/openbox-3/themerc'
    '/usr/share/themes/Wasalight/openbox-3/close.xbm'
    '<titleLayout>NLC</titleLayout>'
    '<font place="ActiveWindow">'
    '<font place="InactiveWindow">'
    '<size>16</size>'
    'padding.width: 8'
    'padding.height: 6'
    'window.active.button.close.hover.bg.color: #b4232c'
    'close_hover close_pressed close_disabled'
    '$TARGET_HOME/.config/picom/wasalight.conf'
    'unredir-if-possible = true'
    'picom --config "$HOME/.config/picom/wasalight.conf" --daemon'
    'own_window_argb_value = 165'
    'border_inner_margin = 16'
    '/etc/wasalight/apps.d/ip-scanner.desktop'
    '/etc/wasalight/apps.d/artnet-monitor.desktop'
    '/etc/wasalight/apps.d/system-monitor.desktop'
    'TryExec=lxtask'
    '/usr/local/sbin/wasalight-ip-scan'
    '/usr/local/sbin/wasalight-artnet-capture'
    'wasalight-network-tools.log'
    'wasalight-xorg-startup.log'
    '$TARGET_HOME/.hushlogin'
    '--noclear --noissue'
    "printf '\\033[2J\\033[H\\033[?25l'"
    'startx -- -keeptty vt1 >"$xorg_log" 2>&1'
    'assets/branding/boot-logo.png'
    '$DATA_MOUNT/system/branding'
    '/usr/share/plymouth/themes/wasalight'
    'update-alternatives --set default.plymouth'
    'GRUB_TIMEOUT_STYLE=hidden'
    'quiet splash loglevel=3'
    'screen_width * 0.34'
    'screen_height * 0.24'
    'wasalight-companion-launcher magichd'
    'wasalight-companion-launcher magicvis'
    'wasalight-vnc-password'
    'cleanup_candidates=(pollinate os-prober)'
    'purge_safe_unused_packages'
    'apt-get autoremove --purge -y'
    'apt-get clean'
    'export GTK_A11Y=none'
    'GRUB_DISABLE_OS_PROBER=true'
    'cleanup_candidates+=(multipath-tools)'
    'cleanup_candidates+=(open-iscsi)'
    '--keep-cloud-init'
    'install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$DATA_MOUNT/log"'
    'runuser -u "$TARGET_USER" -- test -w "$writable_path"'
    'magicq-root-launcher'
    'export HOME=/root'
    'XDG_DOCUMENTS_DIR="$TARGET_HOME/Documents"'
    '$DATA_MOUNT/magicq/root-home/.config /root/.config none bind'
    '$DATA_MOUNT/magicq/Documents/MagicQ /root/Documents/MagicQ none bind'
    'sudo -n /usr/local/sbin/magicq-root-launcher'
    '>>"$console_log" 2>&1'
    '/data/log/wasalight-magicq-console.log /data/log/wasalight-magicq-session.log'
    'size 5M'
    'rotate 5'
    'wasalight-logrotate.timer'
    'LOGS:       $logs'
    'unmanaged: $unmanaged_devices'
    'magicq-start'
    'magicq-stop'
    'magicq-root-stop'
    '--with-companion'
    'COMPANION_VERSION="$(require_manifest_value "$RELEASE_MANIFEST" Companion Version)"'
    'COMPANION_PI_COMMIT="$(require_manifest_value "$RELEASE_MANIFEST" Companion Commit)"'
    '$DATA_MOUNT/companion/home /home/companion none bind'
    '$DATA_MOUNT/companion/etc /etc/companion none bind'
    'RequiresMountsFor=/data/companion/home /data/companion/etc /data/companion/log'
    'StandardOutput=append:/data/companion/log/companion.log'
    'Companion requested $COMPANION_VERSION but BUILD reports $companion_build'
    'installed_companion_version=${installed_companion_version%%+*}'
    'wasalight-companion-control start'
    'wasalight-companion-control stop'
    'wasalight-companion-control restart'
    'wasalight-companion-backup'
    'wasalight-companion-update'
    'Companion updates require MAINTENANCE mode.'
    'COMPANION:  $companion'
    "status_line \"\$green\" 'COMPANION'"
    '/etc/wasalight/apps.d/companion.desktop'
    'Icon=/usr/local/share/icons/wasalight/companion-official.png'
    'readonly COMPANION_ICON_SHA256='
    '/etc/wasalight/apps.d/companion-web.desktop'
    'configure_plugins'
    '/usr/lib/wasalight/plugins'
    '/data/system/plugins-state'
    '/usr/local/bin/wasalight-plugin'
    '/usr/local/sbin/wasalight-plugin-admin'
    '/usr/local/libexec/wasalight-control-center.py'
    'Name=Wasalight Control'
    'Exec=/usr/local/bin/wasalight-control'
    'Icon=/usr/local/share/icons/wasalight/companion-official.png'
    '/data/companion/browser/config'
    'XDG_CACHE_HOME="$runtime_base/wasalight-companion-browser-cache"'
    '/usr/local/share/applications/wasalight-companion-web.desktop'
    '/usr/local/bin/wasalight-falkon-profile'
    'plugin == "internal:adblock"'
    'profile_marker="$profile_root/.wasalight-profile-$profile_schema"'
    'set_ini_value Web-URL-Settings afterLaunch 1'
    'set_ini_value Web-Browser-Settings DefaultZoomLevel 8'
    "set_ini_value NavigationBar Layout 'button-backforward, button-reloadstop, button-home, locationbar, button-tools'"
    '#navigationbar QToolButton'
    'falkon --wmclass=WasalightCompanion --profile wasalight-companion "$url"'
    'add,maximized_vert,maximized_horz'
    'web) exec /usr/local/bin/wasalight-companion-browser'
    'http://${ip_address:-SERVER_IP}:8000'
    'configure_management_tools'
    'wasalight-support-bundle'
    'wasalight-health-monitor'
    'wasalight-health.timer'
    'wasalight-data-transfer'
    'wasalight-update-snapshot'
    'wasalight-rollback-ui'
    'wasalight-magicq-usb-watch'
    'wasalight-first-run'
    'wasalight-plugin-bundle'
    'galculator i3lock mousepad'
    '/usr/local/bin/wasalight-screen-lock'
    '/etc/wasalight/apps.d/calculator.desktop'
    '/etc/wasalight/apps.d/mousepad.desktop'
    '/etc/wasalight/apps.d/screen-lock.desktop'
    'i3lock -n -c 080b10'
    'xset -dpms'
    'GRUB_BACKGROUND="/boot/grub/wasalight-background.png"'
    'FRAMEBUFFER=y'
    'plymouth.use-simpledrm'
    'CONFIG_DRM_SIMPLEDRM=y'
    '98-wasalight-early-display.cfg'
    'grep -qxF i915 /etc/initramfs-tools/modules'
    'remote_commit=$(git -C "$candidate_checkout" rev-parse --verify FETCH_HEAD)'
    'snapshot=$(bash "$snapshot_tool" create)'
    'bash "$snapshot_tool" restore "$snapshot"'
    'SSH:        $ssh'
    'MAINTENANCE mode: automatic MagicQ start skipped'
)

for pattern in "${required_patterns[@]}"; do
    grep -Fq -- "$pattern" "$INSTALLER" || fail "funzione richiesta non trovata: $pattern"
done

if grep -Fq 'SESSION:    $session' "$INSTALLER" || \
   grep -Eq "status_line .*'SESSION'" "$INSTALLER"; then
    fail "lo stato operatore mostra ancora la sessione tecnica MagicQ"
fi
close_mask="$INSTALLER_TEMPLATE_ROOT/usr/share/themes/Wasalight/openbox-3/close.xbm"
[[ -s $close_mask ]] || fail "maschera XBM del pulsante chiudi mancante"
grep -Fq '#define close_width 24' "$close_mask" || fail "la X Openbox non e larga 24 px"
grep -Fq '#define close_height 24' "$close_mask" || fail "la X Openbox non e alta 24 px"
if grep -Fq 'i915.fastboot' "$INSTALLER"; then
    fail "l'installer usa il parametro i915.fastboot rimosso dai kernel moderni"
fi

main_body=$(awk '/^main\(\) \{/,/^}/' "$INSTALLER")
final_checks_line=$(grep -n '^    final_checks$' <<<"$main_body" | cut -d: -f1)
record_version_line=$(grep -n '^    record_installed_version$' <<<"$main_body" | cut -d: -f1)
[[ $final_checks_line =~ ^[0-9]+$ && $record_version_line =~ ^[0-9]+$ ]] || \
    fail "ordine di registrazione versione non verificabile"
((record_version_line > final_checks_line)) || \
    fail "la versione viene registrata prima dei controlli finali"

update_config_line=$(grep -n '^    configure_update$' <<<"$main_body" | cut -d: -f1)
companion_config_line=$(grep -n '^    configure_companion$' <<<"$main_body" | cut -d: -f1)
graphical_config_line=$(grep -n '^    configure_graphical_session$' <<<"$main_body" | cut -d: -f1)
[[ $update_config_line =~ ^[0-9]+$ && $companion_config_line =~ ^[0-9]+$ && \
   $graphical_config_line =~ ^[0-9]+$ ]] || \
    fail "ordine dell'integrazione Companion non verificabile"
((companion_config_line > update_config_line && graphical_config_line > companion_config_line)) || \
    fail "Companion deve essere configurato dopo rete/update e prima del Hub"

data_mount_line=$(grep -n '^    configure_data_mount$' <<<"$main_body" | cut -d: -f1)
usb_discovery_line=$(grep -n '^    discover_magicq_from_usb$' <<<"$main_body" | cut -d: -f1)
persist_package_line=$(grep -n '^    persist_magicq_package$' <<<"$main_body" | cut -d: -f1)
require_magicq_line=$(grep -n '^    require_magicq_or_override$' <<<"$main_body" | cut -d: -f1)
[[ $data_mount_line =~ ^[0-9]+$ && $usb_discovery_line =~ ^[0-9]+$ && \
   $persist_package_line =~ ^[0-9]+$ && $require_magicq_line =~ ^[0-9]+$ ]] || \
    fail "ordine del bootstrap MagicQ da USB non verificabile"
((usb_discovery_line > data_mount_line && persist_package_line > usb_discovery_line && \
   require_magicq_line > persist_package_line)) || \
    fail "il bootstrap USB non avviene tra il mount di /data e il controllo MagicQ"
grep -Fq 'trap cleanup_bootstrap_mounts EXIT' "$INSTALLER" || \
    fail "i mount USB temporanei non hanno una pulizia garantita"
grep -Fq 'case $target in' "$INSTALLER" || \
    fail "il bootstrap USB non esclude i filesystem di sistema montati"
grep -Fq 'target=$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n1 || true)' \
    "$INSTALLER" || \
    fail "una USB non montata fa terminare il bootstrap a causa di findmnt"
grep -Fq "while IFS=\$' \\t' read -r device device_type filesystem; do" \
    "$INSTALLER" || \
    fail "il bootstrap USB non separa le colonne di lsblk con un IFS locale"
if grep -Eq 'cp[[:space:]]+-[^[:space:]]*n([^[:alnum:]_]|$)' "$INSTALLER"; then
    fail "cp -n è deprecato/non portabile: usare --update=none"
fi
grep -Fq 'cp -a --update=none /root/.config/.' "$INSTALLER" || \
    fail "l'inizializzazione persistente non preserva i file esistenti senza cp -n"
if grep -Fq 'apfs-dkms' "$INSTALLER"; then
    fail "il driver APFS kernel sperimentale non deve essere installato"
fi
if grep -Eq 'fsapfsmount[^\n]*readwrite|apfs;[^\n]*opts=.*rw' "$INSTALLER"; then
    fail "APFS non deve essere abilitato in scrittura"
fi
if grep -Eq 'docker (run|compose)|ghcr\.io/bitfocus/companion' "$INSTALLER"; then
    fail "Companion non deve usare Docker: le superfici USB locali non sono supportate"
fi
grep -Fq 'libfontconfig1 libatomic1 libasound2t64 falkon' "$INSTALLER" || \
    fail "Falkon non viene installato insieme a Companion"
grep -Fq -- "-name 'fsapfs[0-9]*'" "$ENTRYPOINT" || \
    fail "install.sh non cerca MagicQ nei volumi APFS esposti da libfsapfs"

install_packages_body=$(awk '/^install_packages\(\) \{/,/^}/' "$INSTALLER")
metadata_line=$(grep -n '^        apt-get update$' <<<"$install_packages_body" | head -n1 | cut -d: -f1)
safe_purge_line=$(grep -n '^    purge_safe_unused_packages$' <<<"$install_packages_body" | cut -d: -f1)
required_install_line=$(grep -n '^        apt_install "${missing_packages\[@\]}"$' <<<"$install_packages_body" | cut -d: -f1)
[[ $metadata_line =~ ^[0-9]+$ && $safe_purge_line =~ ^[0-9]+$ && \
   $required_install_line =~ ^[0-9]+$ ]] || \
    fail "ordine della pulizia APT iniziale non verificabile"
((safe_purge_line < metadata_line && metadata_line < required_install_line)) || \
    fail "i pacchetti inutili non vengono rimossi prima dell'installazione Wasalight"
grep -Fq 'all required packages are installed; skipping apt metadata refresh' \
    <<<"$install_packages_body" || \
    fail "l'installer aggiorna APT anche quando tutti i pacchetti sono presenti"
[[ $(grep -Fc 'apt-get autoremove --purge -y' "$INSTALLER") == 1 ]] || \
    fail "autoremove deve essere eseguito una sola volta alla fine"

optimize_body=$(awk '/^optimize_system\(\) \{/,/^}/' "$INSTALLER")
storage_purge_line=$(grep -n 'apt-get purge -y "${cleanup_installed\[@\]}"' \
    <<<"$optimize_body" | cut -d: -f1)
autoremove_line=$(grep -n 'apt-get autoremove --purge -y' \
    <<<"$optimize_body" | cut -d: -f1)
[[ $storage_purge_line =~ ^[0-9]+$ && $autoremove_line =~ ^[0-9]+$ ]] || \
    fail "ordine della pulizia APT finale non verificabile"
((autoremove_line > storage_purge_line)) || \
    fail "autoremove viene eseguito prima della pulizia storage-aware"

helpers=(
    /usr/local/libexec/wasalight-usb-mount
    /usr/local/libexec/wasalight-usb-unmount
    /usr/local/libexec/wasalight-set-mode
    /usr/local/sbin/wasalight-maintenance
    /usr/local/sbin/wasalight-protect
    /usr/local/bin/wasalight-mode-toggle
    /usr/local/bin/wasalight-status
    /usr/local/bin/magicq-session
    /usr/local/sbin/magicq-root-launcher
    /usr/local/sbin/magicq-root-stop
    /usr/local/bin/magicq-start
    /usr/local/bin/magicq-stop
    /usr/local/bin/wasalight-touch
    /usr/local/bin/wasalight-vnc-password
    /usr/local/bin/wasalight-vnc-start
    /usr/local/bin/wasalight-vnc-stop
    /usr/local/bin/wasalight-vnc-control
    /usr/local/bin/magicq-fullscreen-watch
    /usr/local/bin/wasalight-audio-test
    /usr/local/bin/wasalight-power
    /usr/local/bin/wasalight-dialog
    /usr/local/sbin/wasalight-power-control
    /usr/local/bin/wasalight-desktop-status
    /usr/local/bin/wasalight-desktop-wallpaper
    /usr/local/bin/wasalight-vnc-toggle
    /usr/local/bin/wasalight-ssh-toggle
    /usr/local/sbin/wasalight-ssh-control
    /usr/local/sbin/wasalight-remote-persistence
    /usr/local/bin/wasalight-remote-auto-toggle
    /usr/local/bin/wasalight-remote-autostart
    /usr/local/sbin/wasalight-update
    /usr/local/libexec/wasalight-update-lib.sh
    /usr/local/libexec/wasalight-update-session
    /usr/local/bin/wasalight-update-terminal
    /usr/local/bin/wasalight-update-check
    /usr/local/bin/wasalight-control
    /usr/local/bin/wasalight-terminal-tool
    /usr/local/bin/wasalight-screen-lock
    /usr/local/sbin/wasalight-app-register
)

for helper in "${helpers[@]}"; do
    output="$tmp_dir/${helper##*/}"
    if [[ -f $INSTALLER_TEMPLATE_ROOT$helper ]]; then
        cp "$INSTALLER_TEMPLATE_ROOT$helper" "$output"
    else
        awk -v needle="write_file $helper" '
            index($0, needle) { capture=1; next }
            capture && /^EOF$/ { exit }
            capture { print }
        ' "$INSTALLER" >"$output"
    fi
    [[ -s "$output" ]] || fail "impossibile estrarre $helper"
    bash -n "$output"
done

if grep -Eq '(^|[[:space:]])(xss-lock|xautolock)([[:space:]]|$)' "$INSTALLER"; then
    fail "il blocco schermo non deve essere armato automaticamente"
fi

wallpaper_python="$tmp_dir/wasalight-desktop-wallpaper.py"
awk '/^python3 .*PYEOF/ { capture=1; next }
     capture && /^PYEOF$/ { exit }
     capture { print }' \
    "$tmp_dir/wasalight-desktop-wallpaper" >"$wallpaper_python"
[[ -s $wallpaper_python ]] || fail "renderer Python dello sfondo non estraibile"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$wallpaper_python"
grep -Fq 'screen_width * 0.34' "$wallpaper_python" || \
    fail "lo sfondo desktop non usa la larghezza del logo Plymouth"
grep -Fq 'screen_height * 0.24' "$wallpaper_python" || \
    fail "lo sfondo desktop non usa l'altezza del logo Plymouth"
grep -Fq 'wallpaper.fill(0x080B10FF)' "$wallpaper_python" || \
    fail "lo sfondo desktop non usa il colore Plymouth"

grep -Fq 'sudo -n /usr/local/sbin/magicq-root-launcher' "$tmp_dir/magicq-session" || \
    fail "MagicQ non viene avviato tramite il launcher root controllato"
grep -Fq '>>"$console_log" 2>&1' "$tmp_dir/magicq-session" || \
    fail "stdout e stderr di MagicQ non sono salvati nel log persistente"
grep -Fq 'flock -n 9' "$tmp_dir/magicq-session" || \
    fail "la sessione MagicQ consente ancora istanze duplicate"
grep -Fq 'wasalight-magicq-console.log' "$tmp_dir/magicq-session" || \
    fail "il log di console non è distinto dai log nativi MagicQ"
grep -Fq 'wasalight-magicq-session.pid' "$tmp_dir/magicq-session" || \
    fail "la sessione MagicQ non registra il proprio PID"
grep -Fq 'automatic restart disabled' "$tmp_dir/magicq-session" || \
    fail "la sessione MagicQ non documenta la chiusura senza riavvio"
if grep -Eq 'while :|restarting in|retrying in' "$tmp_dir/magicq-session"; then
    fail "MagicQ viene ancora riavviato automaticamente dopo la chiusura"
fi
grep -Fq 'sudo -n /usr/local/sbin/magicq-root-stop' "$tmp_dir/magicq-stop" || \
    fail "magicq-stop non arresta il processo root tramite il comando ristretto"
grep -Fq 'flock -n 9' "$tmp_dir/magicq-start" || \
    fail "magicq-start non impedisce sessioni duplicate"
grep -Fq 'findmnt -n -o FSTYPE /' "$INSTALLER" || \
    fail "l'autostart MagicQ non distingue SHOW da MAINTENANCE"
grep -Fq 'cd /opt/magicq' "$tmp_dir/magicq-root-launcher" || \
    fail "il launcher root non usa la directory richiesta da ChamSys"
grep -Fq 'HOME=/root' "$tmp_dir/magicq-root-launcher" || \
    fail "il launcher non riproduce l'ambiente root dell'avvio manuale funzionante"
if grep -Fq 'setpriv' "$tmp_dir/magicq-root-launcher"; then
    fail "il launcher altera ancora gruppo o privilegi rispetto al sudo manuale"
fi
grep -Fq 'chamsys ALL=(root) NOPASSWD:' "$INSTALLER" || \
    fail "il launcher MagicQ non dispone della regola sudo controllata"
if grep -Fq '/run/wasalight-usb.device' "$INSTALLER"; then
    fail "la vecchia gestione USB a dispositivo singolo è ancora presente"
fi
grep -Fq 'LD_LIBRARY_PATH=/opt/magicq/lib' "$INSTALLER" || \
    fail "il controllo binario XCB non usa le librerie incluse da MagicQ"
grep -Fq 'wmctrl -ir "$window_id" -b add,fullscreen' \
    "$tmp_dir/magicq-fullscreen-watch" || \
    fail "MagicQ non viene portato automaticamente in fullscreen"
grep -Fq 'speaker-test -D default -c 2 -t wav -l 1' \
    "$tmp_dir/wasalight-audio-test" || \
    fail "il test audio ALSA non verifica il dispositivo predefinito"
grep -Fq 'desktop_icon_size=64' "$INSTALLER" || \
    fail "i pulsanti desktop non sono dimensionati per l'uso touch"
grep -Fq '/usr/local/bin/wasalight-dialog --question' "$tmp_dir/wasalight-power" || \
    fail "spegnimento e riavvio non richiedono una conferma touch"
grep -Fq 'exec /usr/bin/zenity --modal "$@"' \
    "$tmp_dir/wasalight-dialog" || \
    fail "i dialoghi Wasalight non usano la modalità compatibile con Zenity 4"
grep -Fq 'export GTK_A11Y=none' "$tmp_dir/wasalight-dialog" || \
    fail "i dialoghi Zenity 4 non disabilitano il bus accessibilità assente"
if grep -Fq -- '--class=WasalightConfirm' "$INSTALLER"; then
    fail "i dialoghi usano ancora l'opzione rimossa da Zenity 4"
fi
grep -Fq '<application name="zenity" class="zenity">' "$INSTALLER" || \
    fail "Openbox non riconosce i dialoghi Zenity"
grep -Fq '<x>center</x>' "$INSTALLER" || \
    fail "Openbox non centra i dialoghi Wasalight"
grep -Fq '<layer>above</layer>' "$INSTALLER" || \
    fail "Openbox non mantiene i dialoghi Wasalight in primo piano"
grep -Fq 'systemctl poweroff' "$tmp_dir/wasalight-power-control" || \
    fail "il controllo di alimentazione non gestisce lo spegnimento"
grep -Fq 'systemctl reboot' "$tmp_dir/wasalight-power-control" || \
    fail "il controllo di alimentazione non gestisce il riavvio"
grep -Fq 'command=/usr/local/sbin/wasalight-maintenance' \
    "$tmp_dir/wasalight-mode-toggle" || \
    fail "il selettore modalità non prepara MAINTENANCE"
grep -Fq 'command=/usr/local/sbin/wasalight-protect' \
    "$tmp_dir/wasalight-mode-toggle" || \
    fail "il selettore modalità non prepara SHOW"
grep -Fq 'wasalight-power-control reboot' "$tmp_dir/wasalight-mode-toggle" || \
    fail "il selettore modalità non propone il riavvio"
grep -Fq 'wasalight-vnc-start' "$tmp_dir/wasalight-vnc-toggle" || \
    fail "il pulsante VNC non avvia la sessione condivisa"
grep -Fq 'wasalight-vnc-stop' "$tmp_dir/wasalight-vnc-toggle" || \
    fail "il pulsante VNC non ferma la sessione condivisa"
grep -Fq 'wasalight-vnc-start' "$tmp_dir/wasalight-vnc-control" || \
    fail "il toggle VNC non avvia la sessione condivisa"
grep -Fq 'wasalight-vnc-stop' "$tmp_dir/wasalight-vnc-control" || \
    fail "il toggle VNC non ferma la sessione condivisa"
grep -Fq 'wasalight-ssh-control start' "$tmp_dir/wasalight-ssh-toggle" || \
    fail "il pulsante SSH non avvia il servizio controllato"
grep -Fq 'wasalight-ssh-control stop' "$tmp_dir/wasalight-ssh-toggle" || \
    fail "il pulsante SSH non ferma il servizio controllato"
grep -Fq 'systemctl start ssh.service' "$tmp_dir/wasalight-ssh-control" || \
    fail "il controllo SSH non avvia OpenSSH"
grep -Fq 'systemctl stop ssh.service' "$tmp_dir/wasalight-ssh-control" || \
    fail "il controllo SSH non ferma OpenSSH"
grep -Fq 'mktemp "$flag_root/.${service}-autostart.XXXXXX"' \
    "$tmp_dir/wasalight-remote-persistence" || \
    fail "i flag remoti persistenti non sono scritti atomicamente"
grep -Fq '[[ -s /data/system/vnc/passwd ]]' \
    "$tmp_dir/wasalight-remote-persistence" || \
    fail "l'autostart VNC può essere abilitato senza una password"
grep -Fq 'wasalight-ssh-control start' "$tmp_dir/wasalight-remote-autostart" || \
    fail "l'autostart remoto non riattiva SSH"
grep -Fq 'wasalight-vnc-start --lan' "$tmp_dir/wasalight-remote-autostart" || \
    fail "l'autostart remoto non riattiva VNC"
grep -Fq '/usr/local/bin/wasalight-remote-autostart &' "$INSTALLER" || \
    fail "l'autostart remoto non è collegato alla sessione Openbox"
grep -Fq 'git_retry -C "$candidate_checkout" fetch' "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento Wasalight non usa download Git con retry"
grep -Fq 'merge-base --is-ancestor' "$tmp_dir/wasalight-update" || \
    fail "l'updater non blocca una riscrittura non fast-forward del ramo"
grep -Fq 'timeout --signal=TERM 120' "$tmp_dir/wasalight-update-lib.sh" || \
    fail "il download Git dell'updater può bloccarsi indefinitamente"
grep -Fq 'mv "$candidate_checkout" "$checkout"' "$tmp_dir/wasalight-update" || \
    fail "il checkout verificato non viene attivato transazionalmente"
grep -Fq 'status --porcelain' "$tmp_dir/wasalight-update" || \
    fail "l'updater non protegge i file Git non tracciati"
grep -Fq 'cmp -s -- "$source" "$destination"' "$tmp_dir/wasalight-update-lib.sh" || \
    fail "la copia persistente del pacchetto MagicQ non viene verificata"
grep -Fq 'findmnt -rn -o TARGET' "$tmp_dir/wasalight-update" || \
    fail "l'updater non controlla le USB attualmente montate"
grep -Fq 'find "$usb_mount" -maxdepth 1' "$tmp_dir/wasalight-update" || \
    fail "l'updater non cerca il pacchetto MagicQ nella root USB"
grep -Fq 'find "$usb_mount/packages" -maxdepth 1' "$tmp_dir/wasalight-update" || \
    fail "l'updater non cerca il pacchetto MagicQ nella cartella packages USB"
grep -Fq '[[ $(dpkg-deb -f "$source" Package 2>/dev/null) == "$magicq_package" ]]' \
    "$tmp_dir/wasalight-update-lib.sh" || \
    fail "l'updater non verifica che il pacchetto USB sia MagicQ"
grep -Fq 'dpkg --compare-versions' "$tmp_dir/wasalight-update" || \
    fail "l'updater non confronta le vere versioni Debian di MagicQ"
grep -Fq 'CONFLITTO: MagicQ $version' "$tmp_dir/wasalight-update-lib.sh" || \
    fail "l'updater non blocca pacchetti della stessa versione ma differenti"
if grep -Fq 'find "$package_store" -maxdepth 1 -type f -name '"'"'*.deb'"'"' -print | sort -V' \
    "$tmp_dir/wasalight-update-lib.sh"; then
    fail "l'updater sceglie ancora MagicQ ordinando i nomi dei file"
fi
grep -Fq 'tests/verify-project.sh' "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento Wasalight non verifica il progetto scaricato"
grep -Fq '/usr/local/sbin/wasalight-update --code-only' "$INSTALLER" || \
    fail "l'installer non inizializza il checkout persistente degli aggiornamenti"
if grep -Fq 'git reset --hard' "$tmp_dir/wasalight-update"; then
    fail "l'aggiornamento Wasalight non deve cancellare modifiche locali"
fi
grep -Fq '/usr/local/libexec/wasalight-update-session' "$tmp_dir/wasalight-update-terminal" || \
    fail "il menu Update non apre la sessione guidata"
grep -Fq 'WASALIGHT_UPDATE_PLUGIN' "$tmp_dir/wasalight-update-terminal" || \
    fail "l'interfaccia Update non inoltra l'installazione plugin"
grep -Fq 'update_args+=(--plugin "$WASALIGHT_UPDATE_PLUGIN")' \
    "$tmp_dir/wasalight-update-session" || \
    fail "la sessione Update non inoltra il plugin selezionato"
grep -Fq 'pkexec /usr/local/sbin/wasalight-update' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non usa l'autenticazione grafica Polkit"
if grep -Fq 'sudo /usr/local/sbin/wasalight-update' "$tmp_dir/wasalight-update-session"; then
    fail "la sessione guidata richiede ancora la password nel terminale"
fi
grep -Fq 'rc == 126' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non distingue l'annullamento dell'autenticazione"
grep -Fq 'wasalight-power-control reboot' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non offre il riavvio finale"
grep -Fq -- '--reboot' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone l'opzione di riavvio"
grep -Fq -- '--verbose' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone la diagnostica dettagliata"
grep -Fq -- '--plan' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone il piano senza installazione"
grep -Fq -- '--repair' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone la reinstallazione intenzionale"
grep -Fq 'same_release && !explicit_state_change && !magicq_change && !repair' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non evita una reinstallazione identica"
grep -Fq 'touch /run/wasalight-update-reboot-required' "$tmp_dir/wasalight-update" || \
    fail "l'updater non registra quando serve davvero un riavvio"
grep -Fq '[[ ! -e /run/wasalight-update-reboot-required ]]' \
    "$tmp_dir/wasalight-update-session" || \
    fail "la GUI updater propone un riavvio anche dopo un no-op"
grep -Fq 'Downgrade bloccato:' "$tmp_dir/wasalight-update" || \
    fail "l'updater non blocca downgrade Wasalight"
grep -Fq 'Release incoerente:' "$tmp_dir/wasalight-update" || \
    fail "l'updater accetta lo stesso VERSION da commit differenti"
grep -Fq 'downgrade evitato' "$tmp_dir/wasalight-update" || \
    fail "l'updater può installare un vecchio pacchetto MagicQ persistente"
grep -Fq '/data/log/wasalight/updates' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non crea un log separato per ogni esecuzione"
grep -Fq 'tail -n +21' "$tmp_dir/wasalight-update" || \
    fail "i log delle singole esecuzioni updater non hanno retention"
grep -Fq '/data/log/wasalight-update.log' \
    "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/wasalight-logrotate.conf" || \
    fail "il log cumulativo updater non viene ruotato"
grep -Fq 'Comando: %s' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non riporta il comando che ha causato l'errore"
grep -Fq -- '--with-companion' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone --with-companion"
grep -Fq -- '--plugin ID' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone la selezione plugin"
grep -Fq '/data/system/plugins-state/*' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non conserva i plugin abilitati"
grep -Fq 'plugins-state/companion' "$INSTALLER" || \
    fail "l'installer non conserva Companion disabilitato durante un update"
grep -Fq 'installer_args+=(--with-companion)' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non inoltra --with-companion all'installer"
grep -Fq -- '-h, -help, --help' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non accetta -help"
grep -Fq 'sudo wasalight-update --allow-missing-magicq' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non spiega come ignorare l'assenza di MagicQ"
grep -Fq 'systemctl reboot' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update --reboot non riavvia il sistema"
grep -Fq 'require_manifest_value /etc/wasalight/release-manifest.ini Wasalight VersionURL' \
    "$tmp_dir/wasalight-update-check" || \
    fail "il controllo aggiornamenti non usa la VersionURL centralizzata"
grep -Fq -- '--max-time 15' "$tmp_dir/wasalight-update-check" || \
    fail "il controllo aggiornamenti può bloccare indefinitamente l'avvio"
grep -Fq '( sleep 15; /usr/local/bin/wasalight-update-check ) &' "$INSTALLER" || \
    fail "il controllo aggiornamenti non parte con la sessione grafica"
if grep -Fq 'read -r _' "$tmp_dir/wasalight-update-terminal" || \
   grep -Fq 'read -r _' "$tmp_dir/wasalight-update-session"; then
    fail "l'interfaccia Update richiede ancora la tastiera per chiudersi"
fi
grep -Fq 'install -d -o chamsys -g chamsys -m 0750 /data/log' \
    "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento non preserva i permessi chamsys di /data/log"
if grep -Fq 'install -d -o root -g root -m 0755 /data/system /data/log' \
    "$tmp_dir/wasalight-update"; then
    fail "l'aggiornamento assegna ancora /data/log a root"
fi
if grep -Fq 'write_file "$TARGET_HOME/Desktop/Network.desktop"' "$INSTALLER" || \
   grep -Fq 'write_file "$TARGET_HOME/Desktop/Terminal.desktop"' "$INSTALLER"; then
    fail "le vecchie icone Network/Terminal sono ancora create sul desktop"
fi
if grep -Fq 'write_file "$TARGET_HOME/Desktop/Files.desktop"' "$INSTALLER" || \
   grep -Fq 'write_file "$TARGET_HOME/Desktop/Wasalight-Control.desktop"' "$INSTALLER"; then
    fail "File Manager o Wasalight Control sono ancora duplicati sul desktop"
fi
grep -Fq 'write_file "$TARGET_HOME/Desktop/MagicQ.desktop"' "$INSTALLER" || \
    fail "l'avvio rapido MagicQ non è disponibile sul desktop"
if grep -Fq 'write_file "$TARGET_HOME/Desktop/VNC.desktop"' "$INSTALLER" || \
   grep -Fq 'write_file "$TARGET_HOME/Desktop/SSH.desktop"' "$INSTALLER"; then
    fail "SSH o VNC sono ancora duplicati sul desktop"
fi
if grep -Fq 'write_file /etc/wasalight/apps.d/vnc.desktop' "$INSTALLER" || \
   grep -Fq 'write_file /etc/wasalight/apps.d/ssh.desktop' "$INSTALLER" || \
   grep -Fq '<item label="VNC">' "$INSTALLER" || \
   grep -Fq '<item label="SSH">' "$INSTALLER"; then
    fail "SSH o VNC sono ancora duplicati fuori dalla scheda Servizi"
fi
if grep -Fq 'write_file "$TARGET_HOME/Desktop/MagicQ-Start.desktop"' "$INSTALLER" || \
   grep -Fq 'write_file "$TARGET_HOME/Desktop/MagicQ-Stop.desktop"' "$INSTALLER"; then
    fail "i controlli MagicQ sono ancora duplicati sul desktop"
fi

plugin_command="$PROJECT_DIR/libexec/wasalight-plugin"
plugin_admin="$PROJECT_DIR/libexec/wasalight-plugin-admin"
control_center="$PROJECT_DIR/ui/wasalight-control-center.py"
for python_tool in "$plugin_command" "$plugin_admin" "$control_center"; do
    [[ -s $python_tool ]] || fail "componente plugin mancante: $python_tool"
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$python_tool"
done
grep -Fq '["systemctl", "disable", "--now", unit]' "$plugin_admin" || \
    fail "disabilitare un plugin non ferma il servizio systemd"
grep -Fq '["pkill", "-u", user, "-x", process]' "$plugin_admin" || \
    fail "disabilitare un plugin di sessione non ferma il processo"
grep -Fq 'os.replace(temporary, os.path.join(STATE_ROOT, plugin_id))' "$plugin_admin" || \
    fail "lo stato plugin persistente non viene scritto atomicamente"
grep -Fq 'except subprocess.TimeoutExpired:' "$plugin_command" || \
    fail "lo stato plugin non gestisce servizi lenti senza bloccare Control"
grep -Fq 'PLUGIN_COMMAND = "/usr/local/bin/wasalight-plugin"' "$control_center" || \
    fail "Wasalight Control non usa il registro plugin"
grep -Fq 'self.add_dashboard()' "$control_center" || \
    fail "Wasalight Control non espone la dashboard unificata"
grep -Fq "foreground='#76bd22'" "$control_center" || \
    fail "il titolo di Wasalight Control non usa il verde Wasabi"
grep -Fq 'notebook > header tab:checked {' "$control_center" || \
    fail "la scheda attiva di Control non ha una palette dedicata"
grep -Fq 'background: #223016; color: #9bd95a;' "$control_center" || \
    fail "la scheda attiva di Control non usa il verde Wasabi bilanciato"
grep -Fq 'min-height: 44px; font-size: 15px;' "$control_center" || \
    fail "i font dei pulsanti Control non usano la misura compatta touch"
grep -Fq "size='20000' weight='bold'>Wasalight Control" "$control_center" || \
    fail "il titolo Control non usa la misura compatta"
grep -Fq 'desktop_font=Sans 12' "$INSTALLER" || \
    fail "il desktop non usa il font compatto"
grep -Fq 'gtk-font-name=Sans 10' "$INSTALLER" || \
    fail "GTK non usa un font prevedibile tra monitor diversi"
grep -Fq '<size>16</size>' "$INSTALLER" || \
    fail "i titoli Openbox non usano la misura compatta"
grep -Fq 'task_font = Sans 11' "$INSTALLER" || \
    fail "la barra applicazioni non usa il font compatto"
grep -Fq 'notebook, notebook > stack, scrolledwindow, viewport, flowbox {' \
    "$control_center" || fail "le pagine Control non impongono il fondo scuro"
grep -Fq 'gi.require_version("Gdk", "3.0")' "$control_center" || \
    fail "Control non fissa la versione Gdk e genera warning PyGI"
if grep -Fq 'add_with_viewport' "$control_center"; then
    fail "Control usa ancora l'API GTK deprecata add_with_viewport"
fi
grep -Fq 'fill="#76bd22"' "$INSTALLER" || \
    fail "l'icona Wasalight Control non usa il verde Wasabi"
if grep -Fq '#8957e5' "$INSTALLER"; then
    fail "l'icona Wasalight Control usa ancora l'accento viola"
fi
grep -Fq 'mode_label = "Passa a MAINTENANCE" if mode == "SHOW" else "Passa a SHOW"' \
    "$control_center" || fail "la home Control non mostra il cambio modalità contestuale"
if grep -Fq '("File", ["pcmanfm", "/data"])' "$control_center"; then
    fail "la home Control contiene ancora il pulsante File"
fi
grep -Fq 'self.add_magicq_page(launchers)' "$control_center" || \
    fail "Wasalight Control non espone il pannello MagicQ dedicato"
grep -Fq '"/usr/share/pixmaps/magicq.png",' "$control_center" || \
    fail "Wasalight Control non usa l'icona originale MagicQ"
grep -Fq 'CARD_WIDTH = 290' "$control_center" || \
    fail "le schede software e servizi di Control non hanno una misura comune"
grep -Fq 'self.card_flow()' "$control_center" || \
    fail "MagicQ e Servizi non condividono la griglia Control"
if grep -Fq '"Ferma MagicQ"' "$control_center"; then
    fail "Wasalight Control espone ancora il pulsante Ferma MagicQ"
fi
if grep -Fq '<item label="Avvia MagicQ">' "$INSTALLER" || \
   grep -Fq '<item label="Ferma MagicQ">' "$INSTALLER"; then
    fail "il menu contestuale Openbox espone ancora Avvia/Ferma MagicQ"
fi
grep -Fq 'self.magicq_auto_switch = Gtk.Switch()' "$control_center" || \
    fail "Wasalight Control non espone il toggle automatico MagicQ"
grep -Fq 'magicq-autostart' "$INSTALLER" || \
    fail "l'avvio automatico MagicQ non ha un flag persistente"
grep -Fq 'wasalight-remote-persistence magicq enable' "$INSTALLER" || \
    fail "il toggle MagicQ non dispone del comando sudo ristretto"
grep -Fq 'magicq_auto=enabled' "$INSTALLER" || \
    fail "l'autostart SHOW di MagicQ non legge il flag persistente"
grep -Fq 'def plugin_control_changed' "$control_center" || \
    fail "Wasalight Control non gestisce i toggle servizio dichiarativi"
grep -Fq 'switch:checked { background: #76bd22;' "$control_center" || \
    fail "i toggle Control non usano il verde Wasabi"
grep -Fq 'if action["management"] or action.get("control")' "$control_center" || \
    fail "le azioni collegate ai toggle sono ancora duplicate come pulsanti"
grep -Fq 'self.add_service_page()' "$control_center" || \
    fail "Wasalight Control non espone la gestione servizi"
grep -Fq 'self.add_credits_page()' "$control_center" || \
    fail "Wasalight Control non espone la pagina Crediti"
grep -Fq 'Creato da Michele Moser /' "$control_center" || \
    fail "la pagina Crediti non attribuisce Wasalight"
grep -Fq 'https://github.com/wasabifilm/wasalight' "$control_center" || \
    fail "la pagina Crediti non collega il repository ufficiale"
grep -Fq 'https://www.instagram.com/wasabi_lightbulbfarm/' "$control_center" || \
    fail "la pagina Crediti non collega Instagram"
for launcher in files ip-scanner artnet-monitor; do
    launcher_body=$(cat "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/$launcher.desktop")
    grep -Fq 'X-Wasalight-Section=Applications' <<<"$launcher_body" || \
        fail "$launcher non è classificato in Applicazioni"
done
grep -Fq 'installed the verified official Bitfocus Companion icon' "$INSTALLER" || \
    fail "l'installer non registra l'uso dell'icona ufficiale Companion"
grep -Fq 'PLUGIN_COMMAND, "install"' "$control_center" || \
    fail "Wasalight Control non permette di installare plugin disponibili"
grep -Fq 'mode != "MAINTENANCE"' "$control_center" || \
    fail "Wasalight Control consente modifiche plugin persistenti in SHOW"
grep -Fq 'flock -n 9' "$tmp_dir/wasalight-control" || \
    fail "Wasalight Control non impedisce istanze multiple"
grep -Fq 'wmctrl -a "Wasalight Control Center"' "$tmp_dir/wasalight-control" || \
    fail "un secondo avvio di Control non porta in primo piano la finestra esistente"
grep -Fq 'wasalight-control.log' "$tmp_dir/wasalight-control" || \
    fail "Wasalight Control non conserva gli errori di avvio"
grep -Fq 'threading.Thread(target=self.refresh_worker, daemon=True).start()' \
    "$control_center" || \
    fail "Wasalight Control aggiorna ancora lo stato nel thread GTK"
grep -Fq 'ThreadPoolExecutor(max_workers=3)' "$control_center" || \
    fail "Control esegue ancora in serie stato, plugin e MagicQ"
grep -Fq 'timeout=20' "$control_center" || \
    fail "Control usa ancora un timeout troppo breve per i sistemi lenti"
grep -Fq 'timeout --signal=TERM 6 /usr/local/bin/wasalight-touch-status' \
    "$INSTALLER" || fail "lo stato touchscreen può bloccare il refresh Control"
grep -Fq 'dialog.set_keep_above(True)' "$control_center" || \
    fail "i dialoghi GTK di Control non restano in primo piano"
grep -Fq 'if item["optional"]:' "$control_center" || \
    fail "la scheda Plugin mostra ancora i servizi fondamentali"
grep -Fq 'if action["management"] or action.get("control"):' "$control_center" || \
    fail "Control non separa le azioni operative da quelle di gestione"
grep -Fq 'if not optional:' "$plugin_admin" || \
    fail "il gestore permette di disabilitare servizi fondamentali"

plugin_fixture="$tmp_dir/plugin-root"
plugin_state_fixture="$tmp_dir/plugin-state"
service_flag_fixture="$tmp_dir/service-flags"
mkdir -p "$plugin_fixture" "$plugin_state_fixture" "$service_flag_fixture"
cp -R "$PROJECT_DIR/plugins/." "$plugin_fixture/"
printf 'disabled\n' >"$plugin_state_fixture/ssh"
printf 'enabled\n' >"$service_flag_fixture/ssh-autostart"
printf 'disabled\n' >"$service_flag_fixture/vnc-autostart"
plugin_json=$(WASALIGHT_PLUGIN_ROOT="$plugin_fixture" \
    WASALIGHT_PLUGIN_STATE_ROOT="$plugin_state_fixture" \
    WASALIGHT_SERVICE_FLAG_ROOT="$service_flag_fixture" \
    WASALIGHT_PLUGIN_TEST_MODE=maintenance \
    WASALIGHT_VERSION_OVERRIDE="$project_version" \
    python3 "$plugin_command" list --json)
python3 - "$plugin_json" <<'PY' || fail "registro plugin Wasalight non valido"
import json
import sys
plugins = {item["id"]: item for item in json.loads(sys.argv[1])}
assert set(plugins) == {"companion", "ssh", "vnc"}
assert plugins["ssh"]["enabled"] is True
assert plugins["vnc"]["enabled"] is True
assert plugins["ssh"]["optional"] is False
assert plugins["vnc"]["optional"] is False
assert plugins["companion"]["optional"] is True
assert plugins["companion"]["category"] == "Services"
assert plugins["companion"]["compatible"] is True
assert plugins["ssh"]["persistent"] is True
assert plugins["vnc"]["persistent"] is False
assert plugins["ssh"]["state_label"].endswith("AUTO")
assert plugins["vnc"]["state_label"].endswith("MANUALE")
for plugin_id in ("ssh", "vnc"):
    controls = {control["id"]: control for control in plugins[plugin_id]["controls"]}
    assert set(controls) == {"runtime", "automatic"}
    assert controls["runtime"]["label"] == "Servizio attivo"
    assert controls["automatic"]["label"] == "Avvio automatico"
    assert controls["runtime"]["checked"] is plugins[plugin_id]["active"]
    assert controls["automatic"]["checked"] is plugins[plugin_id]["persistent"]
    controlled = {action["id"] for action in plugins[plugin_id]["actions"]
                  if action["control"]}
    assert controlled == {"start", "stop", "auto-enable", "auto-disable"}
assert any(action["id"] == "open" for action in plugins["companion"]["actions"])
assert any(action["id"] == "update" and action["management"]
           for action in plugins["companion"]["actions"])
PY
if WASALIGHT_PLUGIN_ROOT="$plugin_fixture" \
   WASALIGHT_PLUGIN_STATE_ROOT="$plugin_state_fixture" \
   python3 "$plugin_command" action ssh not-an-action >/dev/null 2>&1; then
    fail "il manager plugin accetta azioni non dichiarate"
fi
for plugin in ssh vnc companion; do
    manifest="$PROJECT_DIR/plugins/$plugin/manifest.ini"
    [[ -s $manifest ]] || fail "manifest plugin mancante: $plugin"
    grep -Fq "Id=$plugin" "$manifest" || fail "ID manifest plugin errato: $plugin"
done
grep -Fq 'Optional=false' "$PROJECT_DIR/plugins/ssh/manifest.ini" || \
    fail "SSH non è dichiarato come servizio fondamentale"
grep -Fq 'Optional=false' "$PROJECT_DIR/plugins/vnc/manifest.ini" || \
    fail "VNC non è dichiarato come servizio fondamentale"
grep -Fq 'Key=ssh-autostart' "$PROJECT_DIR/plugins/ssh/manifest.ini" || \
    fail "il manifest SSH non dichiara il flag persistente"
grep -Fq 'Key=vnc-autostart' "$PROJECT_DIR/plugins/vnc/manifest.ini" || \
    fail "il manifest VNC non dichiara il flag persistente"
for manifest in "$PROJECT_DIR/plugins/ssh/manifest.ini" \
                "$PROJECT_DIR/plugins/vnc/manifest.ini"; do
    grep -Fq '[Control runtime]' "$manifest" || fail "toggle runtime mancante: $manifest"
    grep -Fq '[Control automatic]' "$manifest" || fail "toggle automatico mancante: $manifest"
done
grep -Fq 'Command=/usr/local/bin/wasalight-companion-update-terminal' \
    "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "Companion non espone l'aggiornamento dal Control Center"

for embedded in \
    'wasalight-ip-scanner.py:/usr/local/libexec/wasalight-ip-scanner.py' \
    'wasalight-artnet-capture:/usr/local/sbin/wasalight-artnet-capture' \
    'wasalight-artnet-monitor.py:/usr/local/libexec/wasalight-artnet-monitor.py'; do
    output=${embedded%%:*}
    marker=${embedded#*:}
    cp "$INSTALLER_TEMPLATE_ROOT$marker" "$tmp_dir/$output"
    [[ -s $tmp_dir/$output ]] || fail "strumento Python non estraibile: $output"
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$tmp_dir/$output"
done

for embedded in \
    'companion-control:/usr/local/sbin/wasalight-companion-control' \
    'companion-backup:/usr/local/sbin/wasalight-companion-backup' \
    'companion-update:/usr/local/sbin/wasalight-companion-update' \
    'companion-update-session:/usr/local/libexec/wasalight-companion-update-session' \
    'companion-panel:/usr/local/bin/wasalight-companion-panel' \
    'companion-browser:/usr/local/bin/wasalight-companion-browser' \
    'falkon-profile:/usr/local/bin/wasalight-falkon-profile'; do
    output=${embedded%%:*}
    marker=${embedded#*:}
    cp "$INSTALLER_TEMPLATE_ROOT$marker" "$tmp_dir/$output"
    [[ -s $tmp_dir/$output ]] || fail "strumento Companion non estraibile: $output"
    bash -n "$tmp_dir/$output"
done
grep -Fq 'pkexec /usr/local/sbin/wasalight-companion-update' \
    "$tmp_dir/companion-update-session" || \
    fail "l'aggiornamento Companion non usa l'autenticazione grafica Polkit"
if grep -Fq 'sudo /usr/local/sbin/wasalight-companion-update' \
    "$tmp_dir/companion-update-session"; then
    fail "l'aggiornamento Companion richiede ancora la password nel terminale"
fi
grep -Fq '!= overlay' "$tmp_dir/companion-backup" || \
    fail "il backup Companion non è limitato alla modalità MAINTENANCE"
grep -Fq '!= overlay' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non è limitato alla modalità MAINTENANCE"
grep -Fq '/usr/local/sbin/wasalight-companion-backup' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non crea prima un backup"
grep -Fq '/opt/companion/BUILD' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non verifica la versione realmente installata"
grep -Fq 'actual=${actual%%+*}' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non ignora correttamente i metadata SemVer"

update_policy="$INSTALLER_TEMPLATE_ROOT/usr/share/polkit-1/actions/com.wasalight.updates.policy"
[[ -s $update_policy ]] || fail "policy Polkit degli aggiornamenti mancante"
python3 - "$update_policy" <<'PY' || fail "policy Polkit degli aggiornamenti non valida"
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
expected = {
    "com.wasalight.update": "/usr/local/sbin/wasalight-update",
    "com.wasalight.companion.update": "/usr/local/sbin/wasalight-companion-update",
}
actions = {action.attrib.get("id"): action for action in root.findall("action")}
for action_id, executable in expected.items():
    action = actions.get(action_id)
    if action is None:
        raise SystemExit(f"azione mancante: {action_id}")
    defaults = action.find("defaults")
    if defaults is None or defaults.findtext("allow_active") != "auth_admin":
        raise SystemExit(f"autenticazione amministratore mancante: {action_id}")
    if defaults.findtext("allow_any") != "no" or defaults.findtext("allow_inactive") != "no":
        raise SystemExit(f"policy troppo permissiva: {action_id}")
    paths = [node.text for node in action.findall("annotate")
             if node.attrib.get("key") == "org.freedesktop.policykit.exec.path"]
    if paths != [executable]:
        raise SystemExit(f"eseguibile non vincolato: {action_id}")
PY
companion_build='5.0.3+9703-stable-2daa0d7670'
companion_core=${companion_build#[vV]}
companion_core=${companion_core%%+*}
[[ $companion_core == 5.0.3 ]] || \
    fail "normalizzazione SemVer Companion non valida"
grep -Fq 'http://127.0.0.1:8000' "$tmp_dir/companion-browser" || \
    fail "il browser Companion non usa l'interfaccia locale"
grep -Fq '/data/companion/browser/config' "$tmp_dir/companion-browser" || \
    fail "il profilo Falkon Companion non è persistente"
if grep -Fq '/data/companion/browser/cache' "$tmp_dir/companion-browser"; then
    fail "la cache Falkon non deve essere persistente in /data"
fi

falkon_profile_fixture="$tmp_dir/falkon-profile-fixture"
mkdir -p "$falkon_profile_fixture"
cat >"$falkon_profile_fixture/settings.ini" <<'EOF'
[General]
keep=true

[Plugin-Settings]
AllowedPlugins=internal:adblock, lib:KDEFrameworksIntegration.so

[Other]
keep=this-too
EOF
WASALIGHT_FALKON_PROFILE_ROOT="$falkon_profile_fixture" \
    bash "$tmp_dir/falkon-profile"
grep -Fq 'AllowedPlugins=lib:KDEFrameworksIntegration.so' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non conserva gli altri plugin"
if grep -Fq 'internal:adblock' "$falkon_profile_fixture/settings.ini"; then
    fail "il profilo Falkon non disattiva AdBlock"
fi
grep -Fq 'keep=this-too' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon altera sezioni non correlate"
grep -Fq 'homepage=http://127.0.0.1:8000' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non imposta Companion come pagina iniziale"
grep -Fq 'afterLaunch=1' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon ripristina ancora la sessione precedente"
grep -Fq 'DefaultZoomLevel=8' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non usa lo zoom touch al 120 percento"
grep -Fq 'hideTabsWithOneTab=true' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non nasconde la barra con una singola scheda"
grep -Fq 'Layout=button-backforward, button-reloadstop, button-home, locationbar, button-tools' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "la barra Falkon non usa il layout touch Wasalight"
grep -Fq 'min-height: 46px' "$falkon_profile_fixture/userChrome.css" || \
    fail "il tema Falkon non crea controlli touch sufficientemente grandi"
[[ -e $falkon_profile_fixture/.wasalight-profile-1 ]] || \
    fail "il profilo Falkon non registra l'inizializzazione dei default"

# After the first seed, updates preserve operator preferences while continuing
# to enforce the deliberate AdBlock exclusion.
sed -i.bak 's/showStatusBar=false/showStatusBar=true/' \
    "$falkon_profile_fixture/settings.ini"
rm -f "$falkon_profile_fixture/settings.ini.bak"
sed -i.bak 's/AllowedPlugins=lib:KDEFrameworksIntegration.so/AllowedPlugins=internal:adblock, lib:KDEFrameworksIntegration.so/' \
    "$falkon_profile_fixture/settings.ini"
rm -f "$falkon_profile_fixture/settings.ini.bak"
WASALIGHT_FALKON_PROFILE_ROOT="$falkon_profile_fixture" \
    bash "$tmp_dir/falkon-profile"
grep -Fq 'showStatusBar=true' "$falkon_profile_fixture/settings.ini" || \
    fail "un update Wasalight sovrascrive le preferenze Falkon dell'operatore"
if grep -Fq 'internal:adblock' "$falkon_profile_fixture/settings.ini"; then
    fail "un update Wasalight riattiva AdBlock"
fi

empty_falkon_profile="$tmp_dir/falkon-profile-empty"
WASALIGHT_FALKON_PROFILE_ROOT="$empty_falkon_profile" \
    bash "$tmp_dir/falkon-profile"
grep -Fq 'AllowedPlugins=@Invalid()' "$empty_falkon_profile/settings.ini" || \
    fail "un nuovo profilo Falkon abilita ancora AdBlock per default"
grep -Fq 'showStatusBar=false' "$empty_falkon_profile/settings.ini" || \
    fail "un nuovo profilo Falkon non applica i default Wasalight"
[[ -s $empty_falkon_profile/userChrome.css ]] || \
    fail "un nuovo profilo Falkon non installa il tema Wasalight"

[[ -s "$PROJECT_DIR/docs/touchscreen.md" ]] || fail "guida touchscreen mancante"
grep -Fq 'wasalight-touch-config set' "$PROJECT_DIR/docs/touchscreen.md" || \
    fail "configurazione touchscreen non documentata"
grep -Fq '/stick/<dispositivo>' "$PROJECT_DIR/packages/README.md" || \
    fail "aggiornamento MagicQ da USB non documentato in packages/README.md"
[[ -s "$PROJECT_DIR/docs/vnc.md" ]] || fail "guida VNC mancante"
[[ -s "$PROJECT_DIR/docs/ssh.md" ]] || fail "guida SSH mancante"
[[ -s "$PROJECT_DIR/docs/update.md" ]] || fail "guida aggiornamenti mancante"
[[ -s "$PROJECT_DIR/docs/system-cleanup.md" ]] || fail "guida pulizia sistema mancante"
[[ -s "$PROJECT_DIR/docs/boot-branding.md" ]] || fail "guida branding di avvio mancante"
[[ -s "$PROJECT_DIR/docs/licensing.md" ]] || fail "guida licenza mancante"
[[ -s "$PROJECT_DIR/docs/versioning.md" ]] || fail "guida versionamento mancante"
[[ -s "$PROJECT_DIR/docs/companion.md" ]] || fail "guida Bitfocus Companion mancante"
grep -Fq '/data/companion/home' "$PROJECT_DIR/docs/companion.md" || \
    fail "persistenza Companion non documentata"
grep -Fq '127.0.0.1' "$PROJECT_DIR/docs/companion.md" || \
    fail "collegamento locale MagicQ/Companion non documentato"
grep -Fq 'wasalight-update --with-companion' "$PROJECT_DIR/docs/companion.md" || \
    fail "installazione Companion tramite updater non documentata"
grep -Fq '/data/companion/browser' "$PROJECT_DIR/docs/companion.md" || \
    fail "profilo persistente Falkon non documentato"
grep -Fq 'internal:adblock' "$PROJECT_DIR/docs/companion.md" || \
    fail "disattivazione AdBlock Falkon non documentata"
grep -Fq '## Bitfocus Companion opzionale' "$PROJECT_DIR/docs/hardware-test-checklist.md" || \
    fail "collaudo hardware Companion non documentato"
[[ -s "$PROJECT_DIR/LICENSE" ]] || fail "Apache License 2.0 mancante"
grep -Fq 'Apache License' "$PROJECT_DIR/LICENSE" || fail "testo licenza Apache non valido"
grep -Fq 'Version 2.0, January 2004' "$PROJECT_DIR/LICENSE" || \
    fail "versione della licenza Apache non valida"
[[ -s "$PROJECT_DIR/NOTICE" ]] || fail "NOTICE di attribuzione mancante"
grep -Fq 'Wasalight — created by Michele Moser / Wasabi Lightbulbfarm.' \
    "$PROJECT_DIR/NOTICE" || fail "citazione Wasalight mancante dal NOTICE"
grep -Fq '@wasabi_lightbulbfarm' "$PROJECT_DIR/NOTICE" || \
    fail "account Instagram mancante dal NOTICE"
[[ -s "$PROJECT_DIR/CITATION.cff" ]] || fail "metadati di citazione mancanti"
grep -Fq 'license: Apache-2.0' "$PROJECT_DIR/CITATION.cff" || \
    fail "licenza mancante dai metadati di citazione"
[[ -s "$PROJECT_DIR/assets/branding/LICENSE" ]] || fail "licenza separata del logo mancante"
grep -Fq 'excluded from the Apache' "$PROJECT_DIR/assets/branding/LICENSE" || \
    fail "esclusione del logo dalla licenza Apache non documentata"
[[ -s "$PROJECT_DIR/assets/branding/boot-logo.png" ]] || fail "logo Plymouth predefinito mancante"
if grep -Fq 'plymouth-set-default-theme' "$INSTALLER"; then
    fail "il comando Plymouth rimosso da Ubuntu 24.04 è ancora utilizzato"
fi
grep -Fq 'readlink -f /usr/share/plymouth/themes/default.plymouth' "$INSTALLER" || \
    fail "il tema Plymouth attivo non viene verificato tramite alternatives"
if grep -Eq -- '--chamsys-admin|--purge-cloud-init|previous_default_sha256' "$INSTALLER" || \
   grep -Fq '/home/*/wasalight/packages/*.deb' "$INSTALLER"; then
    fail "l'installer contiene ancora compatibilità con versioni Wasalight precedenti"
fi
if grep -Fq 'wasalight-hub' "$INSTALLER" || \
   [[ -e "$PROJECT_DIR/docs/migration-24.04.md" ]]; then
    fail "la prima base contiene ancora componenti o guide delle versioni precedenti"
fi
for old_command in \
    magicq-status magicq-maintenance magicq-protect magicq-touch \
    magicq-vnc magicq-audio-test magicq-set-mode magicq-usb magicq-logrotate; do
    if grep -Eq "(^|[/[:space:]\"'])${old_command}([[:space:]\"']|$)" "$INSTALLER"; then
        fail "nome comando non uniforme ancora presente: $old_command"
    fi
done
for label in '"Dashboard": "Stato"' '"Services": "Servizi"' \
    '"Applications": "Applicazioni"' '"Support": "Supporto"' \
    '"Credits": "Crediti"' \
    'Gtk.Button(label="Aggiorna")' 'Gtk.Button(label="Chiudi")'; do
    grep -Fq "$label" "$control_center" || \
        fail "etichetta Control non uniformata: $label"
done
python3 - "$PROJECT_DIR/assets/branding/boot-logo.png" <<'PY' || fail "logo Plymouth predefinito non valido"
import struct
import sys
with open(sys.argv[1], "rb") as source:
    assert source.read(8) == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">I", source.read(4))[0] == 13
    assert source.read(4) == b"IHDR"
    width, height = struct.unpack(">II", source.read(8))
assert (width, height) == (1200, 627)
PY
grep -Fq 'Ubuntu Server 24.04 LTS' "$PROJECT_DIR/README.md" || \
    fail "target Ubuntu 24.04 non documentato"
grep -Fq 'packages/*.deb' "$PROJECT_DIR/.gitignore" || \
    fail "i pacchetti MagicQ proprietari non sono esclusi da Git"
if grep -Fq 'VERSION_ID:-} == 22.04' "$INSTALLER"; then
    fail "il vecchio target Ubuntu 22.04 è ancora accettato"
fi
if grep -Fq '/media/usb' "$INSTALLER"; then
    fail "il vecchio percorso USB /media/usb è ancora configurato"
fi
if grep -Eq 'usermod .*netdev|groupadd .*netdev' "$INSTALLER"; then
    fail "l'installer dipende ancora dal gruppo opzionale netdev"
fi
if grep -Eq 'chpasswd|usermod .* -p |/etc/shadow' "$INSTALLER"; then
    fail "la password chamsys non deve essere copiata o gestita in forma non interattiva"
fi
if grep -Fq 'ENABLE_CHAMSYS_ADMIN' "$INSTALLER"; then
    fail "l'accesso amministrativo chamsys non deve più essere opzionale"
fi
grep -Fq -- '--reset-chamsys-password' "$PROJECT_DIR/README.md" || \
    fail "l'accesso amministrativo chamsys non è documentato"
grep -Fq 'chown -R "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/magicq"' "$INSTALLER" || \
    fail "la riparazione dei proprietari MagicQ persistenti è assente"
grep -Fq 'repair_magicq_persistent_permissions' "$INSTALLER" || \
    fail "la riparazione post-installazione dei permessi MagicQ è assente"
if grep -Eq 'gio[[:space:]]+set.*metadata::trusted' "$INSTALLER"; then
    fail "l'installer dipende ancora dal metadato GIO non supportato da PCManFM"
fi

install_magicq_line=$(grep -n '^[[:space:]]*install_magicq$' "$INSTALLER" | tail -n1 | cut -d: -f1)
repair_magicq_line=$(grep -n '^[[:space:]]*repair_magicq_persistent_permissions$' "$INSTALLER" | tail -n1 | cut -d: -f1)
[[ -n $install_magicq_line && -n $repair_magicq_line && $repair_magicq_line -gt $install_magicq_line ]] || \
    fail "i permessi MagicQ devono essere riparati dopo l'installazione del pacchetto"

group_helper="$tmp_dir/existing-groups.sh"
{
    printf '%s\n' '#!/usr/bin/env bash' 'warn() { :; }'
    awk '
        /^existing_groups_csv\(\)/ { capture=1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$INSTALLER"
} >"$group_helper"
bash -n "$group_helper"

group_mock_bin="$tmp_dir/group-mock-bin"
mkdir -p "$group_mock_bin"
cat >"$group_mock_bin/getent" <<'EOF'
#!/bin/sh
[ "${GROUP_TEST_NONE:-0}" = 1 ] && exit 2
case "${2:-}" in audio|video) exit 0 ;; *) exit 2 ;; esac
EOF
chmod +x "$group_mock_bin/getent"

available_groups=$(PATH="$group_mock_bin:$PATH" bash -c \
    'source "$1"; existing_groups_csv audio video plugdev netdev' \
    _ "$group_helper")
[[ $available_groups == audio,video ]] || \
    fail "il filtro dei gruppi opzionali non esclude quelli mancanti"

no_groups=$(GROUP_TEST_NONE=1 PATH="$group_mock_bin:$PATH" bash -c \
    'source "$1"; existing_groups_csv audio video plugdev' \
    _ "$group_helper")
[[ -z $no_groups ]] || fail "il filtro non gestisce un sistema privo di gruppi opzionali"

mock_bin="$tmp_dir/mock-bin"
mkdir -p "$mock_bin"
touch_log="$tmp_dir/touch.log"
touch_config="$tmp_dir/touch.conf"

cat >"$mock_bin/xset" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$mock_bin/xrandr" <<'EOF'
#!/bin/sh
printf '%s\n' 'HDMI-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis)'
EOF

cat >"$mock_bin/udevadm" <<'EOF'
#!/bin/sh
printf '%s\n' 'ID_INPUT=1' 'ID_INPUT_TOUCHSCREEN=1'
EOF

cat >"$mock_bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$mock_bin/xinput" <<'EOF'
#!/bin/sh
case "$1 $2" in
    '--list --short')
        printf '%s\n' '⎡ Virtual core pointer                     id=2    [master pointer  (3)]' \
            '⎜   ↳ Test Touch                         id=10   [slave  pointer  (2)]'
        ;;
    'list-props 10')
        printf '%s\n' 'Device Node (280): "/dev/null"' \
            'libinput Calibration Matrix (300): 1, 0, 0, 0, 1, 0, 0, 0, 1' \
            'libinput Calibration Matrix Default (301): 1, 0, 0, 0, 1, 0, 0, 0, 1'
        ;;
    'list --name-only')
        printf '%s\n' 'Test Touch'
        ;;
    'map-to-output '*|'set-prop '*)
        printf '%s\n' "$*" >>"$TOUCH_TEST_LOG"
        ;;
    *) exit 1 ;;
esac
EOF

chmod +x "$mock_bin"/*
ln -s "$tmp_dir/wasalight-touch" "$tmp_dir/wasalight-touch-status"
ln -s "$tmp_dir/wasalight-touch" "$tmp_dir/wasalight-touch-config"

PATH="$mock_bin:$PATH" MAGICQ_TOUCH_CONFIG="$touch_config" \
    TOUCH_TEST_LOG="$touch_log" bash "$tmp_dir/wasalight-touch-status" --summary | \
    grep -Fq '1 detected; mode: auto; target: ready' || \
    fail "diagnostica touchscreen simulata non riuscita"

PATH="$mock_bin:$PATH" MAGICQ_TOUCH_CONFIG="$touch_config" \
    TOUCH_TEST_LOG="$touch_log" bash "$tmp_dir/wasalight-touch-config" \
    set 'Test Touch' HDMI-1 right

grep -Fq 'MODE=manual' "$touch_config" || fail "modalita touch non salvata"
grep -Fq 'ROTATION=right' "$touch_config" || fail "rotazione touch non salvata"
grep -Fq 'map-to-output 10 HDMI-1' "$touch_log" || fail "associazione touch non applicata"
grep -Fq 'set-prop 10 libinput Calibration Matrix' "$touch_log" || \
    fail "matrice touch non applicata"

vnc_mock_bin="$tmp_dir/vnc-mock-bin"
vnc_config_dir="$tmp_dir/vnc-config"
vnc_runtime_dir="$tmp_dir/vnc-runtime"
mkdir -p "$vnc_mock_bin" "$vnc_config_dir" "$vnc_runtime_dir"
printf '%s\n' test-password >"$vnc_config_dir/passwd"
chmod 0600 "$vnc_config_dir/passwd"

cat >"$vnc_mock_bin/id" <<'EOF'
#!/bin/sh
case "${1:-}" in -un) printf '%s\n' chamsys ;; -u) printf '%s\n' 1000 ;; *) exit 2 ;; esac
EOF

cat >"$vnc_mock_bin/xset" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$vnc_mock_bin/hostname" <<'EOF'
#!/bin/sh
printf '%s\n' '192.0.2.10 '
EOF

cat >"$vnc_mock_bin/ps" <<'EOF'
#!/bin/sh
printf '%s\n' x11vnc
EOF

cat >"$vnc_mock_bin/x11vnc" <<'EOF'
#!/bin/sh
trap 'exit 0' TERM INT
while :; do sleep 1; done
EOF

chmod +x "$vnc_mock_bin"/*
vnc_env=(
    PATH="$vnc_mock_bin:$PATH"
    WASALIGHT_VNC_CONFIG_DIR="$vnc_config_dir"
    MAGICQ_VNC_RUNTIME_DIR="$vnc_runtime_dir"
    DISPLAY=:0
    XAUTHORITY="$tmp_dir/test.Xauthority"
)

vnc_start_output=$(env "${vnc_env[@]}" bash "$tmp_dir/wasalight-vnc-start" --lan) || \
    fail "avvio VNC simulato non riuscito: $vnc_start_output"
grep -Fq 'vnc://192.0.2.10:5900' <<<"$vnc_start_output" || \
    fail "indirizzo VNC inatteso: $vnc_start_output"
[[ -s "$vnc_runtime_dir/wasalight-x11vnc.pid" ]] || fail "PID VNC non registrato"
vnc_test_pid=$(<"$vnc_runtime_dir/wasalight-x11vnc.pid")
kill -0 "$vnc_test_pid" 2>/dev/null || fail "processo VNC simulato non attivo"

vnc_stop_output=$(env "${vnc_env[@]}" bash "$tmp_dir/wasalight-vnc-stop") || \
    fail "arresto VNC simulato non riuscito: $vnc_stop_output"
grep -Fq 'VNC stopped.' <<<"$vnc_stop_output" || \
    fail "risposta arresto VNC inattesa: $vnc_stop_output"
kill -0 "$vnc_test_pid" 2>/dev/null && fail "processo VNC simulato ancora attivo"
vnc_test_pid=
[[ ! -e "$vnc_runtime_dir/wasalight-x11vnc.pid" ]] || fail "PID VNC non rimosso"

printf 'Progetto verificato: sintassi e componenti essenziali presenti.\n'
