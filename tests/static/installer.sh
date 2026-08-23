# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Controlli statici per installer, updater e sessione grafica.
system_audit="$PROJECT_DIR/libexec/wasalight-system-audit"
[[ -x $system_audit ]] || fail "audit di sistema mancante o non eseguibile"
bash -n "$system_audit"
session_language="$INSTALLER_TEMPLATE_ROOT/usr/local/libexec/wasalight-session-language"
[[ -s $session_language ]] || fail "helper lingua della sessione mancante"
sh -n "$session_language"
i18n_helper="$INSTALLER_TEMPLATE_ROOT/usr/local/libexec/wasalight-i18n"
[[ -s $i18n_helper ]] || fail "helper gettext di sistema mancante"
bash -n "$i18n_helper"
grep -Fq '. /usr/local/libexec/wasalight-i18n' \
    "$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-power" || \
    fail "i dialoghi di alimentazione non usano il dominio gettext di sistema"
openbox_menu="$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-openbox-menu"
[[ -s $openbox_menu ]] || fail "generatore menu Openbox mancante"
bash -n "$openbox_menu"
grep -Fq '/usr/local/bin/wasalight-openbox-menu "$HOME/.config/openbox/menu.xml"' \
    "$INSTALLER" || fail "il menu Openbox non viene rigenerato a ogni login"
grep -Fq '. /usr/local/libexec/wasalight-session-language' "$INSTALLER" || \
    fail "la sessione grafica non applica la preferenza lingua persistente"
grep -Fq 'locale-gen en_US.UTF-8 it_IT.UTF-8' "$INSTALLER" || \
    fail "l'installer non genera entrambe le locale supportate"
for localized_desktop_field in \
    'Name=Power off' 'Name[it]=Spegni' \
    'Comment=Shut down the workstation after confirmation' \
    'Comment[it]=Spegne la postazione dopo una conferma' \
    'Name=Restart' 'Name[it]=Riavvia' \
    'Comment=Restart the workstation after confirmation' \
    'Comment[it]=Riavvia la postazione dopo una conferma'; do
    grep -Fq "$localized_desktop_field" "$INSTALLER" || \
        fail "campo desktop localizzato mancante: $localized_desktop_field"
done
grep -Fq 'wasalight-system-audit' "$PROJECT_DIR/installer/modules/70-management.sh" || \
    fail "l'installer non installa l'audit di sistema"
grep -Fq 'audit) command_to_run=/usr/local/bin/wasalight-system-audit' \
    "$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-terminal-tool" || \
    fail "l'audit non è apribile dal terminale grafico"
grep -Fq 'Exec=/usr/local/bin/wasalight-terminal-tool audit' \
    "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/system-audit.desktop" || \
    fail "l'audit non compare negli strumenti di supporto"
for forbidden_audit_action in 'apt-get ' 'systemctl enable' 'systemctl disable' \
    'systemctl start' 'systemctl stop' 'systemctl restart' 'mount ' 'umount ' \
    'tee ' 'rm -' 'mv ' 'cp '; do
    if grep -Fq "$forbidden_audit_action" "$system_audit"; then
        fail "l'audit contiene un'azione mutante: $forbidden_audit_action"
    fi
done

lock_library="$PROJECT_DIR/lib/wasalight-operation-lock.sh"
[[ -s $lock_library ]] || fail "libreria lock globale mancante"
grep -Fq 'wasalight_acquire_operation_lock "Wasalight installation"' "$ENTRYPOINT" || \
    fail "install.sh non acquisisce il lock globale"
for locked_tool in \
    "$INSTALLER_TEMPLATE_ROOT/usr/local/sbin/wasalight-update" \
    "$PROJECT_DIR/libexec/wasalight-update-snapshot" \
    "$PROJECT_DIR/libexec/wasalight-data-transfer"; do
    grep -Fq 'wasalight_acquire_operation_lock' "$locked_tool" || \
        fail "operazione mutante priva di lock globale: $locked_tool"
done
magicq_installer="$INSTALLER_TEMPLATE_ROOT/usr/local/sbin/wasalight-magicq-install"
magicq_installer_ui="$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-magicq-install-ui"
[[ -x $magicq_installer ]] || fail "installer MagicQ offline mancante o non eseguibile"
bash -n "$magicq_installer" "$magicq_installer_ui"
grep -Fq 'wasalight_acquire_operation_lock "MagicQ installation"' "$magicq_installer" || \
    fail "l'installer MagicQ offline non usa il lock globale"
grep -Fq 'apt-get --simulate --no-download install' "$magicq_installer" || \
    fail "l'installer MagicQ non verifica offline le dipendenze prima di modificare il sistema"
grep -Fq 'dpkg --install "$selected_package"' "$magicq_installer" || \
    fail "l'installer MagicQ non installa direttamente il pacchetto locale verificato"
grep -Fq 'find "$usb_mount/packages" -maxdepth 1' "$magicq_installer" || \
    fail "l'installer MagicQ non cerca nella cartella packages della USB"
grep -Fq 'pkexec /usr/local/sbin/wasalight-magicq-install' "$magicq_installer_ui" || \
    fail "l'interfaccia MagicQ non usa l'autenticazione grafica"
for forbidden_magicq_action in 'apt-get update' 'git clone' 'git fetch' 'curl ' 'wget '; do
    if grep -Fq "$forbidden_magicq_action" "$magicq_installer"; then
        fail "l'installer MagicQ offline usa rete o aggiorna indici: $forbidden_magicq_action"
    fi
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
grep -Fq '_ "Delete permanently"' "$rollback_ui" || \
    fail "l’interfaccia rollback elimina snapshot senza seconda conferma"
delete_branch_line=$(grep -n '^if \[\[ \$action == "$( _ "Delete snapshot" )" \]\]; then$' \
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
grep -Fq 'Name=Companion' "$companion_web_launcher" || \
    fail "il launcher operativo Companion non usa il nome compatto"
grep -Fq '[[ -d /opt/companion && -x /usr/local/bin/wasalight-companion-browser ]]' \
    "$INSTALLER" || fail "il launcher Companion nel dock non dipende dall'installazione reale"
grep -Fq 'companion_icon=/usr/local/share/icons/wasalight/companion-official.png' \
    "$INSTALLER" || fail "il launcher Companion nel dock non usa l'icona ufficiale"
grep -Fq 'StartupWMClass=WasalightCompanion' "$INSTALLER" || \
    fail "il launcher Companion nel dock non è associato alla finestra Falkon dedicata"
[[ ! -e $INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/companion.desktop ]] || \
    fail "il vecchio launcher tecnico Companion duplica ancora il Control Center"

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
    "status_line \"\$green\" 'MAGICQ' \"RUNNING · \$magicq_version · \$magicq_mode\""
    "status_line \"\$yellow\" 'MAGICQ' \"READY · \$magicq_version · \$magicq_mode\""
    "status_line \"\$red\" 'MAGICQ' 'NOT INSTALLED'"
    "dpkg-query -W -f='\${db:Status-Abbrev}\\t\${Version}' magicq"
    'WASALIGHT:  $version'
    'magicq="READY · $magicq_version · ${magicq_mode^^}"'
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
    '/etc/netplan/99-wasalight-networkmanager.yaml'
    'renderer: NetworkManager'
    'netplan apply'
    'systemd-networkd-wait-online.service systemd-networkd.service'
    'systemctl reset-failed systemd-networkd-wait-online.service'
    'fsapfsmount -X ro,allow_other,nosuid,nodev,noexec'
    'Mounted $dev (APFS) read-only'
    'ID_FS_TYPE}=="vfat|exfat|ntfs|apfs"'
    "grep -F 'libGLU.so.1'"
    'MagicQ has unresolved runtime libraries'
    'MagicQ Qt xcb platform plugin has unresolved runtime libraries'
    'MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable'
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
    '/usr/local/share/wasalight/desktop/MagicQ.desktop'
    '/usr/local/share/wasalight/desktop/Install-MagicQ.desktop'
    'wasalight-magicq-desktop-refresh'
    '$TARGET_HOME/Desktop/Power-Off.desktop'
    '$TARGET_HOME/Desktop/Reboot.desktop'
    'Icon=/usr/local/share/icons/wasalight/hub.svg'
    'Icon=/usr/local/share/icons/wasalight/files.svg'
    'Icon=/usr/local/share/icons/wasalight/power.svg'
    'Icon=/usr/local/share/icons/wasalight/reboot.svg'
    'conky --config="$HOME/.config/conky/wasalight.conf"'
    'wasalight-desktop-status'
    'wasalight-keyboard-toggle'
    'wasalight-power-control poweroff'
    'wasalight-vnc-toggle'
    'wasalight-ssh-toggle'
    'wasalight-update'
    '${execpi 2 /usr/local/bin/wasalight-desktop-status}'
    '/data/system/wasalight'
    '/data/system/packages'
    'candidate_checkout="${checkout}.candidate"'
    '/etc/wasalight/apps.d/network.desktop'
    '/data/system/apps.d'
    'wasalight-app-register'
    'taskbar_name = 0'
    'autohide = 0'
    'strut_policy = follow_size'
    'launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Wasalight-Control.desktop'
    'launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Files.desktop'
    '$TARGET_HOME/.config/wasalight/dock/Companion.desktop'
    '$companion_dock_item'
    'panel_items = LTSPC'
    'button_lclick_command = /usr/local/bin/wasalight-keyboard-toggle'
    'button_icon = /usr/local/share/icons/wasalight/keyboard.svg'
    'task_text = 0'
    'task_maximum_size = 64 52'
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
    '/etc/wasalight/apps.d/osc-monitor.desktop'
    '/etc/wasalight/apps.d/system-monitor.desktop'
    '/usr/local/share/icons/wasalight/system-monitor.svg'
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
    'unattended-upgrades pollinate os-prober'
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
    'rm -f /etc/wasalight/apps.d/companion.desktop'
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
    '/usr/local/bin/wasalight-x11-window-icon'
    'plugin == "internal:adblock"'
    'profile_marker="$profile_root/.wasalight-profile-$profile_schema"'
    'profile_schema=3'
    'set_ini_value Web-URL-Settings afterLaunch 1'
    'set_ini_value Web-Browser-Settings DefaultZoomLevel 8'
    "set_ini_value NavigationBar Layout 'button-backforward, button-reloadstop, button-home, button-tools'"
    '#navigationbar QToolButton'
    '#locationbar,'
    '#locationbar-bookmarkicon,'
    '#locationbar-down-icon {'
    'falkon --wmclass=WasalightCompanion --profile wasalight-companion "$url"'
    '/usr/local/bin/wasalight-x11-window-icon'
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
    'run_with_progress_capture "$snapshot_output" "Creating snapshot"'
    'bash "$snapshot_tool" restore "$snapshot"'
    'SSH:        $ssh'
    'MAINTENANCE mode: automatic MagicQ start skipped'
)

for pattern in "${required_patterns[@]}"; do
    grep -Fq -- "$pattern" "$INSTALLER" || fail "funzione richiesta non trovata: $pattern"
done

runtime_packages_file="$PROJECT_DIR/packages/wasalight-runtime.txt"
[[ -s $runtime_packages_file ]] || fail "elenco pacchetti runtime condiviso mancante"
for runtime_package in \
    xinput libinput-tools libglu1-mesa libgl1-mesa-dri libxcb-cursor0 \
    alsa-utils openbox picom x11vnc galculator i3lock mousepad onboard \
    gir1.2-atspi-2.0 falkon conky-all \
    python3-gi gir1.2-gtk-3.0 arp-scan network-manager wpasupplicant \
    plymouth libfsapfs-utils openssh-server git curl; do
    grep -Fxq "$runtime_package" "$runtime_packages_file" || \
        fail "pacchetto runtime richiesto mancante: $runtime_package"
done

if grep -Fq -- '--with-onscreen-keyboard' "$INSTALLER" || \
   grep -Fq 'ENABLE_ONSCREEN_KEYBOARD' "$INSTALLER"; then
    fail "l'installer espone ancora il vecchio flag della tastiera virtuale"
fi

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
grep -Fq -- "-name 'fsapfs[0-9]*'" "$ENTRYPOINT" || \
    fail "install.sh non cerca MagicQ nei volumi APFS esposti da libfsapfs"

install_packages_body=$(awk '/^install_packages\(\) \{/,/^}/' "$INSTALLER")
metadata_line=$(grep -n '^        apt-get update$' <<<"$install_packages_body" | head -n1 | cut -d: -f1)
required_install_line=$(grep -n '^        apt_install "${missing_packages\[@\]}"$' <<<"$install_packages_body" | cut -d: -f1)
[[ $metadata_line =~ ^[0-9]+$ && $required_install_line =~ ^[0-9]+$ ]] || \
    fail "ordine dell'installazione APT non verificabile"
((metadata_line < required_install_line)) || \
    fail "i metadati APT non vengono aggiornati prima dei pacchetti mancanti"
grep -Fq 'wasalight_runtime_packages "$RUNTIME_PACKAGES_FILE"' \
    <<<"$install_packages_body" || \
    fail "l'installer non usa l'elenco pacchetti runtime condiviso"
grep -Fq 'all required packages are installed; skipping apt metadata refresh' \
    <<<"$install_packages_body" || \
    fail "l'installer aggiorna APT anche quando tutti i pacchetti sono presenti"
grep -Fq "makestep 1.0 -1" "$INSTALLER" || \
    fail "Chrony non corregge gli scarti elevati dopo l'avvio iniziale"
grep -Fq 'configure_time_synchronization' <<<"$install_packages_body" || \
    fail "l'installer non applica la configurazione persistente dell'orologio"
[[ $(grep -Fc 'apt-get autoremove --purge -y' "$INSTALLER") == 1 ]] || \
    fail "autoremove deve essere eseguito una sola volta alla fine"

optimize_body=$(awk '/^optimize_system\(\) \{/,/^}/' "$INSTALLER")
grep -Fq 'snapd modemmanager cups cups-daemon bluez avahi-daemon whoopsie apport' \
    <<<"$optimize_body" || fail "la pulizia finale non include i pacchetti appliance inutili"
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
    /usr/local/bin/wasalight-keyboard-toggle
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
    /usr/local/sbin/wasalight-time-control
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

keyboard_toggle="$tmp_dir/wasalight-keyboard-toggle"
grep -Fq 'WASALIGHT_I18N_HELPER:-/usr/local/libexec/wasalight-i18n' \
    "$keyboard_toggle" || \
    fail "il toggle tastiera non permette un helper i18n isolato nei test"
grep -Fq 'pgrep -u "$(id -u)" -x onboard' "$keyboard_toggle" || \
    fail "il pulsante Tastiera non rileva un'istanza Onboard esistente"
grep -Fq 'pkill -TERM -u "$(id -u)" -x onboard' "$keyboard_toggle" || \
    fail "il pulsante Tastiera non permette di chiudere Onboard"
grep -Fq 'pkill -KILL -u "$(id -u)" -x onboard' "$keyboard_toggle" || \
    fail "il pulsante Tastiera non elimina un processo Onboard nascosto"
grep -Fq "grep -Fq 'Map State: IsViewable'" "$keyboard_toggle" || \
    fail "il pulsante Tastiera confonde ancora processo e finestra visibile"
grep -Fq 'stop_onboard || exit 1' "$keyboard_toggle" || \
    fail "la tastiera nascosta non viene ripulita e riaperta nello stesso tocco"
grep -Fq 'gsettings set org.onboard show-status-icon false' "$keyboard_toggle" || \
    fail "Onboard mostra ancora un'icona duplicata che interferisce col toggle"
grep -Fq 'gsettings set org.onboard.auto-show enabled false' "$keyboard_toggle" || \
    fail "Onboard non è configurato per il solo controllo manuale"
grep -Fq 'gsettings set org.onboard.keyboard input-event-source GTK' \
    "$keyboard_toggle" || \
    fail "Onboard usa ancora il backend XInput instabile con tablet e mouse"
grep -Fq 'GTK_A11Y=none onboard' "$keyboard_toggle" || \
    fail "Onboard non disabilita il bridge accessibilità assente"
grep -Fq 'gsettings set org.onboard.window force-to-top true' "$keyboard_toggle" || \
    fail "Onboard non resta sopra le applicazioni della console"
grep -Fq 'onboard_args+=(--size="${width}x${height}" -x "$x" -y "$y")' \
    "$keyboard_toggle" || \
    fail "la geometria GTK di Onboard non viene impostata prima dell'avvio"
grep -Fq 'wmctrl -i -r "$window_id" -b add,above,sticky' "$keyboard_toggle" || \
    fail "la tastiera virtuale non viene mantenuta visibile sul desktop touch"
if grep -Fq 'wasalight-keyboard-toggle &' "$INSTALLER"; then
    fail "la tastiera virtuale viene avviata automaticamente"
fi
if grep -Fq 'install_template /etc/wasalight/apps.d/keyboard.desktop' "$INSTALLER"; then
    fail "la tastiera è ancora duplicata nella pagina Applicazioni"
fi
grep -Fq '/data/system/apps.d/keyboard.desktop' "$INSTALLER" || \
    fail "l'installer non rimuove la registrazione persistente duplicata della tastiera"

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
grep -Fq 'icon=/usr/local/share/icons/wasalight/power.svg' "$tmp_dir/wasalight-power" || \
    fail "la conferma di spegnimento non usa l'icona corretta"
grep -Fq 'icon=/usr/local/share/icons/wasalight/reboot.svg' "$tmp_dir/wasalight-power" || \
    fail "la conferma di riavvio non usa l'icona corretta"
grep -Fq -- '--icon=/usr/local/share/icons/wasalight/ssh.svg' \
    "$tmp_dir/wasalight-ssh-toggle" || \
    fail "le conferme SSH non usano l'icona SSH"
grep -Fq -- '--icon=/usr/local/share/icons/wasalight/vnc.svg' \
    "$tmp_dir/wasalight-vnc-toggle" || \
    fail "le conferme VNC non usano l'icona VNC"
grep -Fq -- '--icon=system-lock-screen' "$tmp_dir/wasalight-screen-lock" || \
    fail "la conferma di blocco non usa l'icona lucchetto"
grep -Fq -- '--icon=edit-delete' "$rollback_ui" || \
    fail "la conferma di eliminazione snapshot non usa l'icona cestino"
grep -Fq -- '--icon=document-revert' "$rollback_ui" || \
    fail "la conferma di rollback non usa l'icona ripristino"
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
grep -Fq 'progress_indicator()' "$tmp_dir/wasalight-update" || \
    fail "l'updater non offre un avanzamento compatto per le operazioni lente"
grep -Fq "local -a frames=('●··' '·●·' '··●' '·●·')" "$tmp_dir/wasalight-update" || \
    fail "l'updater non rende visibile che un'operazione lunga sta proseguendo"
grep -Fq 'kill "$indicator_pid"' "$tmp_dir/wasalight-update" || \
    fail "l'indicatore dell'updater non viene arrestato alla fine del comando"
if grep -Fq 'while kill -0 "$pid"' "$tmp_dir/wasalight-update"; then
    fail "l'avanzamento updater può restare bloccato su un processo zombie"
fi
grep -Fq 'tee -a "$current_log" "$log_file" >"$raw_output"' \
    "$tmp_dir/wasalight-update" || \
    fail "la vista compatta dell'updater non conserva l'output completo in tempo reale"
grep -Fq 'tail -n 24 "$raw_output"' "$tmp_dir/wasalight-update" || \
    fail "l'updater non mostra il contesto grezzo quando un comando fallisce"
grep -Fq 'WASALIGHT_PROGRESS_FILE="$progress_file"' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non evita il riepilogo needrestart prima del riavvio richiesto"
grep -Fq 'merge-base --is-ancestor' "$tmp_dir/wasalight-update" || \
    fail "l'updater non blocca una riscrittura non fast-forward del ramo"
grep -Fq 'timeout --signal=TERM 120' "$tmp_dir/wasalight-update-lib.sh" || \
    fail "il download Git dell'updater può bloccarsi indefinitamente"
grep -Fq 'mv "$candidate_checkout" "$checkout"' "$tmp_dir/wasalight-update" || \
    fail "il checkout verificato non viene attivato transazionalmente"
grep -Fq 'status --porcelain' "$tmp_dir/wasalight-update" || \
    fail "l'updater non protegge i file Git non tracciati"
grep -Fq 'cmp -s -- "$source" "$temporary"' "$tmp_dir/wasalight-update-lib.sh" || \
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
grep -Fq 'CONFLICT: MagicQ $version' "$tmp_dir/wasalight-update-lib.sh" || \
    fail "l'updater non blocca pacchetti della stessa versione ma differenti"
if grep -Fq 'find "$package_store" -maxdepth 1 -type f -name '"'"'*.deb'"'"' -print | sort -V' \
    "$tmp_dir/wasalight-update-lib.sh"; then
    fail "l'updater sceglie ancora MagicQ ordinando i nomi dei file"
fi
grep -Fq 'tests/verify-project.sh' "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento Wasalight non verifica il progetto scaricato"
grep -Fq 'git clone --quiet --no-hardlinks "$PROJECT_DIR" "$UPDATE_CHECKOUT"' "$INSTALLER" || \
    fail "l'installer non inizializza il checkout persistente dalla sorgente verificata"
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
grep -Fq 'update_args+=(--channel "$WASALIGHT_UPDATE_CHANNEL")' \
    "$tmp_dir/wasalight-update-session" || \
    fail "la sessione Update non inoltra il canale selezionato"
grep -Fq 'update_args+=(--resume)' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione Update non propone la ripresa di una transazione interrotta"
grep -Fq 'pkexec /usr/local/sbin/wasalight-update' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non usa l'autenticazione grafica Polkit"
grep -Fq '_ "Waiting for authorization…"' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non spiega l'attesa della finestra Polkit"
grep -Fq '_ "The full log remains available with the compact view."' \
    "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non chiarisce che l'output completo viene conservato"
for localized_update_ui in \
    "$tmp_dir/wasalight-update-terminal" "$tmp_dir/wasalight-update-session"; do
    grep -Fq 'WASALIGHT_I18N_HELPER:-/usr/local/libexec/wasalight-i18n' \
        "$localized_update_ui" || \
        fail "componente updater privo del dominio gettext: $localized_update_ui"
done
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
grep -Fq 'candidate_checkout=$(mktemp -d /tmp/wasalight-plan.XXXXXX)' \
    "$tmp_dir/wasalight-update" || \
    fail "--plan non usa un checkout temporaneo esterno a /data"
grep -Fq 'Simulation: USB drives are inspected only during a real update.' \
    "$tmp_dir/wasalight-update" || \
    fail "--plan può ancora importare pacchetti dalle USB"
grep -Fq -- '--resume' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone la ripresa transazionale"
grep -Fq 'update_state_write "$state_file" running installing' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non registra atomicamente la fase di installazione"
grep -Fq 'WASALIGHT_UPDATE_STATE_OWNER:-root:chamsys' \
    "$tmp_dir/wasalight-update-lib.sh" || \
    fail "lo stato transazionale non è leggibile dal pannello chamsys"
grep -Fq 'export GIT_OPTIONAL_LOCKS=0' "$tmp_dir/wasalight-update" || \
    fail "--plan può ancora aggiornare l'indice Git persistente"
grep -Fq 'WASALIGHT_UPDATE_TRANSACTION=1' "$tmp_dir/wasalight-update" || \
    fail "l'installer può inizializzare il checkout attivo durante una transazione"
grep -Fq 'verify_stable_tag "$candidate_checkout" "$stable_tag" "$signer_file"' \
    "$tmp_dir/wasalight-update" || \
    fail "il canale stable non verifica la firma del tag"
grep -Fq 'refs/heads/main' "$RELEASE_MANIFEST" || \
    fail "il canale debug non è dichiarato nel manifest"
grep -Fq -- '--repair' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone la reinstallazione intenzionale"
grep -Fq 'same_release && !explicit_state_change && !magicq_change && !repair' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non evita una reinstallazione identica"
grep -Fq 'Synchronizing the system clock before package operations' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non sincronizza l'orologio prima di APT"
grep -Fq 'System clock is still more than five minutes from NTP time.' \
    "$tmp_dir/wasalight-update" || \
    fail "l'updater non blocca uno scarto NTP ancora pericoloso"
grep -Fq 'touch /run/wasalight-update-reboot-required' "$tmp_dir/wasalight-update" || \
    fail "l'updater non registra quando serve davvero un riavvio"
grep -Fq '[[ ! -e /run/wasalight-update-reboot-required ]]' \
    "$tmp_dir/wasalight-update-session" || \
    fail "la GUI updater propone un riavvio anche dopo un no-op"
grep -Fq 'Downgrade blocked:' "$tmp_dir/wasalight-update" || \
    fail "l'updater non blocca downgrade Wasalight"
grep -Fq 'Inconsistent release:' "$tmp_dir/wasalight-update" || \
    fail "l'updater accetta lo stesso VERSION da commit differenti"
grep -Fq 'downgrade avoided' "$tmp_dir/wasalight-update" || \
    fail "l'updater può installare un vecchio pacchetto MagicQ persistente"
grep -Fq '/data/log/wasalight/updates' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non crea un log separato per ogni esecuzione"
grep -Fq 'tail -n +21' "$tmp_dir/wasalight-update" || \
    fail "i log delle singole esecuzioni updater non hanno retention"
grep -Fq '/data/log/wasalight-update.log' \
    "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/wasalight-logrotate.conf" || \
    fail "il log cumulativo updater non viene ruotato"
grep -Fq 'Command: %s' "$tmp_dir/wasalight-update" || \
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
grep -Fq 'update-grub 9>&-' "$INSTALLER" || \
    fail "GRUB eredita ancora il descrittore del lock globale"
grep -Fq 'update-initramfs -u 9>&-' "$INSTALLER" || \
    fail "initramfs eredita ancora il descrittore del lock globale"
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
grep -Fq 'install_template /usr/local/share/wasalight/desktop/MagicQ.desktop' "$INSTALLER" || \
    fail "l'avvio rapido MagicQ non è disponibile sul desktop"
grep -Fq '/usr/local/sbin/wasalight-magicq-desktop-refresh' "$INSTALLER" || \
    fail "il desktop non commuta tra Installa MagicQ e MagicQ"
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
