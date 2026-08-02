#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$PROJECT_DIR/bin/chamsys_install_ubuntu.sh"
ENTRYPOINT="$PROJECT_DIR/install.sh"
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

[[ -x "$INSTALLER" ]] || fail "installer mancante o non eseguibile"
[[ -x "$ENTRYPOINT" ]] || fail "install.sh mancante o non eseguibile"
grep -Fq '/data/system/packages/*.deb' "$ENTRYPOINT" || \
    fail "install.sh non riutilizza il pacchetto MagicQ persistente"

bash -n "$INSTALLER"
bash -n "$ENTRYPOINT"

required_patterns=(
    'VERSION_ID:-} == 24.04'
    'add-apt-repository -y universe'
    'overlayroot="tmpfs:swap=0,recurse=0"'
    '$TARGET_HOME/Documents/MagicQ'
    '$TARGET_HOME/.local/share'
    '/etc/NetworkManager/system-connections'
    'magicq-usb@%k.service'
    'readonly USB_MOUNT="/stick"'
    'mountpoint="$base/$dev_name"'
    'state="$state_dir/$dev_name.mount"'
    'ID_FS_TYPE}=="vfat|exfat|ntfs"'
    'magicq-maintenance'
    'magicq-protect'
    'magicq-status'
    'OS:         $os'
    'xinput libinput-tools'
    'libglu1-mesa libgl1-mesa-dri'
    'libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0'
    'libxcb-keysyms1 libxcb-randr0 libxcb-render0 libxcb-render-util0'
    'libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0'
    'libxcb-xinerama0 libxcb-xkb1 libxkbcommon-x11-0 libxcb-cursor0'
    'libasound2-data alsa-utils'
    'openbox tint2 pcmanfm lxterminal lxrandr lxtask x11vnc procps wmctrl x11-utils'
    'conky-all zenity libglib2.0-bin desktop-file-utils librsvg2-common'
    'python3 python3-gi gir1.2-gtk-3.0'
    'arp-scan iproute2'
    'plymouth plymouth-themes file'
    '/etc/netplan/99-wasalight-networkmanager.yaml'
    'renderer: NetworkManager'
    'netplan apply'
    'network-manager network-manager-gnome wpasupplicant'
    'util-linux udev logrotate'
    "grep -F 'libGLU.so.1'"
    'MagicQ has unresolved runtime libraries'
    'MagicQ Qt xcb platform plugin has unresolved runtime libraries'
    'MagicQ audio runtime check failed: /usr/share/alsa/alsa.conf is unavailable'
    '--with-onscreen-keyboard'
    '--reset-chamsys-password'
    'audio video plugdev sudo adm systemd-journal'
    'passwd "$TARGET_USER"'
    '/data/system/touchscreen/config'
    'magicq-touch-status'
    'magicq-touch-config'
    'magicq-touch-watch'
    'magicq-vnc-start'
    'magicq-vnc-stop'
    'magicq-fullscreen-watch'
    'magicq-audio-test'
    'wmctrl -n 1'
    'pcmanfm --desktop --profile=default'
    '$TARGET_HOME/Desktop/Start-MagicQ.desktop'
    '$TARGET_HOME/Desktop/Stop-MagicQ.desktop'
    '$TARGET_HOME/Desktop/Wasalight-Hub.desktop'
    '$TARGET_HOME/Desktop/Files.desktop'
    '$TARGET_HOME/Desktop/VNC.desktop'
    '$TARGET_HOME/Desktop/SSH.desktop'
    '$TARGET_HOME/Desktop/Power-Off.desktop'
    '$TARGET_HOME/Desktop/Reboot.desktop'
    'Icon=/usr/local/share/icons/wasalight/start.svg'
    'Icon=/usr/local/share/icons/wasalight/stop.svg'
    'Icon=/usr/local/share/icons/wasalight/hub.svg'
    'Icon=/usr/local/share/icons/wasalight/files.svg'
    'Icon=/usr/local/share/icons/wasalight/vnc.svg'
    'Icon=/usr/local/share/icons/wasalight/ssh.svg'
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
    'git clone --branch main'
    '/etc/wasalight/apps.d/network.desktop'
    '/data/system/apps.d'
    'wasalight-app-register'
    'taskbar_name = 0'
    'autohide = 0'
    'strut_policy = follow_size'
    'launcher_item_app = $TARGET_HOME/Desktop/Wasalight-Hub.desktop'
    'launcher_item_app = $TARGET_HOME/Desktop/Files.desktop'
    'quick_exec=1'
    'chown -R root:root "$TARGET_HOME/Desktop"'
    '-exec chmod 0444 {} +'
    'desktop SVG icon loader is unavailable'
    'background_color = #080b10 98'
    '/usr/share/themes/Wasalight/openbox-3/themerc'
    '<titleLayout>NLC</titleLayout>'
    '#define close_width 16'
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
    'magicq-vnc-password'
    'cleanup_candidates=(pollinate os-prober)'
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
    'magicq-logrotate.timer'
    'LOGS:       $logs'
    'unmanaged: $unmanaged_devices'
    'magicq-start'
    'magicq-stop'
    'magicq-root-stop'
    'SUPERVISOR: $supervisor'
    'SSH:        $ssh'
    'MAINTENANCE mode: automatic MagicQ start skipped'
)

for pattern in "${required_patterns[@]}"; do
    grep -Fq -- "$pattern" "$INSTALLER" || fail "funzione richiesta non trovata: $pattern"
done

helpers=(
    /usr/local/libexec/magicq-usb-mount
    /usr/local/libexec/magicq-usb-unmount
    /usr/local/libexec/magicq-set-mode
    /usr/local/sbin/magicq-maintenance
    /usr/local/sbin/magicq-protect
    /usr/local/bin/magicq-status
    /usr/local/bin/magicq-session
    /usr/local/sbin/magicq-root-launcher
    /usr/local/sbin/magicq-root-stop
    /usr/local/bin/magicq-start
    /usr/local/bin/magicq-stop
    /usr/local/bin/magicq-touch
    /usr/local/bin/magicq-vnc-password
    /usr/local/bin/magicq-vnc-start
    /usr/local/bin/magicq-vnc-stop
    /usr/local/bin/magicq-fullscreen-watch
    /usr/local/bin/magicq-audio-test
    /usr/local/bin/wasalight-power
    /usr/local/sbin/wasalight-power-control
    /usr/local/bin/wasalight-desktop-status
    /usr/local/bin/wasalight-vnc-toggle
    /usr/local/bin/wasalight-ssh-toggle
    /usr/local/sbin/wasalight-ssh-control
    /usr/local/sbin/wasalight-update
    /usr/local/libexec/wasalight-update-session
    /usr/local/bin/wasalight-update-terminal
    /usr/local/bin/wasalight-hub
    /usr/local/bin/wasalight-terminal-tool
    /usr/local/sbin/wasalight-app-register
)

for helper in "${helpers[@]}"; do
    output="$tmp_dir/${helper##*/}"
    awk -v needle="write_file $helper" '
        index($0, needle) { capture=1; next }
        capture && /^EOF$/ { exit }
        capture { print }
    ' "$INSTALLER" >"$output"
    [[ -s "$output" ]] || fail "impossibile estrarre $helper"
    bash -n "$output"
done

grep -Fq 'sudo -n /usr/local/sbin/magicq-root-launcher' "$tmp_dir/magicq-session" || \
    fail "MagicQ non viene avviato tramite il launcher root controllato"
grep -Fq '>>"$console_log" 2>&1' "$tmp_dir/magicq-session" || \
    fail "stdout e stderr di MagicQ non sono salvati nel log persistente"
grep -Fq 'flock -n 9' "$tmp_dir/magicq-session" || \
    fail "il supervisore MagicQ consente ancora istanze duplicate"
grep -Fq 'wasalight-magicq-console.log' "$tmp_dir/magicq-session" || \
    fail "il log di console non è distinto dai log nativi MagicQ"
grep -Fq 'wasalight-magicq-session.pid' "$tmp_dir/magicq-session" || \
    fail "il supervisore MagicQ non registra il proprio PID"
grep -Fq 'sudo -n /usr/local/sbin/magicq-root-stop' "$tmp_dir/magicq-stop" || \
    fail "magicq-stop non arresta il processo root tramite il comando ristretto"
grep -Fq 'flock -n 9' "$tmp_dir/magicq-start" || \
    fail "magicq-start non impedisce supervisori duplicati"
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
if grep -Fq '/run/magicq-usb.device' "$INSTALLER"; then
    fail "la vecchia gestione USB a dispositivo singolo è ancora presente"
fi
grep -Fq 'LD_LIBRARY_PATH=/opt/magicq/lib' "$INSTALLER" || \
    fail "il controllo binario XCB non usa le librerie incluse da MagicQ"
grep -Fq 'wmctrl -ir "$window_id" -b add,fullscreen' \
    "$tmp_dir/magicq-fullscreen-watch" || \
    fail "MagicQ non viene portato automaticamente in fullscreen"
grep -Fq 'speaker-test -D default -c 2 -t wav -l 1' \
    "$tmp_dir/magicq-audio-test" || \
    fail "il test audio ALSA non verifica il dispositivo predefinito"
grep -Fq 'desktop_icon_size=64' "$INSTALLER" || \
    fail "i pulsanti desktop non sono dimensionati per l'uso touch"
grep -Fq 'zenity --question' "$tmp_dir/wasalight-power" || \
    fail "spegnimento e riavvio non richiedono una conferma touch"
grep -Fq 'systemctl poweroff' "$tmp_dir/wasalight-power-control" || \
    fail "il controllo di alimentazione non gestisce lo spegnimento"
grep -Fq 'systemctl reboot' "$tmp_dir/wasalight-power-control" || \
    fail "il controllo di alimentazione non gestisce il riavvio"
grep -Fq 'magicq-vnc-start' "$tmp_dir/wasalight-vnc-toggle" || \
    fail "il pulsante VNC non avvia la sessione condivisa"
grep -Fq 'magicq-vnc-stop' "$tmp_dir/wasalight-vnc-toggle" || \
    fail "il pulsante VNC non ferma la sessione condivisa"
grep -Fq 'wasalight-ssh-control start' "$tmp_dir/wasalight-ssh-toggle" || \
    fail "il pulsante SSH non avvia il servizio controllato"
grep -Fq 'wasalight-ssh-control stop' "$tmp_dir/wasalight-ssh-toggle" || \
    fail "il pulsante SSH non ferma il servizio controllato"
grep -Fq 'systemctl start ssh.service' "$tmp_dir/wasalight-ssh-control" || \
    fail "il controllo SSH non avvia OpenSSH"
grep -Fq 'systemctl stop ssh.service' "$tmp_dir/wasalight-ssh-control" || \
    fail "il controllo SSH non ferma OpenSSH"
grep -Fq 'merge --ff-only FETCH_HEAD' "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento Wasalight non impone un avanzamento Git sicuro"
grep -Fq 'cmp -s -- "$source" "$destination"' "$tmp_dir/wasalight-update" || \
    fail "la migrazione del pacchetto MagicQ non verifica la copia"
grep -Fq 'tests/verify-project.sh' "$tmp_dir/wasalight-update" || \
    fail "l'aggiornamento Wasalight non verifica il progetto scaricato"
grep -Fq '/usr/local/sbin/wasalight-update --code-only' "$INSTALLER" || \
    fail "l'installer non inizializza il checkout persistente degli aggiornamenti"
if grep -Fq 'git reset --hard' "$tmp_dir/wasalight-update"; then
    fail "l'aggiornamento Wasalight non deve cancellare modifiche locali"
fi
grep -Fq '/usr/local/libexec/wasalight-update-session' "$tmp_dir/wasalight-update-terminal" || \
    fail "il menu Update non apre la sessione guidata"
grep -Fq 'sudo /usr/local/sbin/wasalight-update' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non esegue l'aggiornamento"
grep -Fq 'wasalight-power-control reboot' "$tmp_dir/wasalight-update-session" || \
    fail "la sessione guidata non offre il riavvio finale"
grep -Fq -- '--reboot' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update non espone l'opzione di riavvio"
grep -Fq 'systemctl reboot' "$tmp_dir/wasalight-update" || \
    fail "wasalight-update --reboot non riavvia il sistema"
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
grep -Fq 'write_file "$TARGET_HOME/Desktop/Files.desktop"' "$INSTALLER" || \
    fail "il File Manager non è disponibile sul desktop"

hub_script="$tmp_dir/wasalight-hub.py"
awk '/write_file \/usr\/local\/libexec\/wasalight-hub.py / { capture=1; next }
     capture && /^PYEOF$/ { exit }
     capture { print }' "$INSTALLER" >"$hub_script"
[[ -s $hub_script ]] || fail "Wasalight Hub non è estraibile dall'installer"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$hub_script"
grep -Fq '/data/system/apps.d/*.desktop' "$hub_script" || \
    fail "Wasalight Hub non legge il registro applicazioni persistente"
grep -Fq 'magicvis|magichd' "$hub_script" || \
    fail "Wasalight Hub non rileva i companion ChamSys conosciuti"
grep -Fq '"path": item.get("Path", "").strip() or None' "$hub_script" || \
    fail "Wasalight Hub ignora la directory Path dei launcher"
grep -Fq 'cwd=item["path"]' "$hub_script" || \
    fail "Wasalight Hub non avvia i companion dalla directory richiesta"
grep -Fq '/usr/local/sbin/wasalight-companion-launcher' "$hub_script" || \
    fail "Wasalight Hub non usa il launcher root dedicato per MagicHD/MagicVis"
grep -Fq 'except ValueError' "$hub_script" || \
    fail "Wasalight Hub non gestisce i booleani desktop non validi"
grep -Fq 'wasalight-hub.log' "$tmp_dir/wasalight-hub" || \
    fail "Wasalight Hub non conserva gli errori di avvio"

for embedded in \
    'wasalight-ip-scanner.py:/usr/local/libexec/wasalight-ip-scanner.py' \
    'wasalight-artnet-capture:/usr/local/sbin/wasalight-artnet-capture' \
    'wasalight-artnet-monitor.py:/usr/local/libexec/wasalight-artnet-monitor.py'; do
    output=${embedded%%:*}
    marker=${embedded#*:}
    awk -v marker="$marker" '
        index($0, "write_file " marker " ") { capture=1; next }
        capture && /^PYEOF$/ { exit }
        capture { print }
    ' "$INSTALLER" >"$tmp_dir/$output"
    [[ -s $tmp_dir/$output ]] || fail "strumento Python non estraibile: $output"
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$tmp_dir/$output"
done

[[ -s "$PROJECT_DIR/docs/touchscreen.md" ]] || fail "guida touchscreen mancante"
grep -Fq 'magicq-touch-config set' "$PROJECT_DIR/docs/touchscreen.md" || \
    fail "configurazione touchscreen non documentata"
[[ -s "$PROJECT_DIR/docs/migration-24.04.md" ]] || fail "guida migrazione 24.04 mancante"
[[ -s "$PROJECT_DIR/docs/vnc.md" ]] || fail "guida VNC mancante"
[[ -s "$PROJECT_DIR/docs/ssh.md" ]] || fail "guida SSH mancante"
[[ -s "$PROJECT_DIR/docs/update.md" ]] || fail "guida aggiornamenti mancante"
[[ -s "$PROJECT_DIR/docs/system-cleanup.md" ]] || fail "guida pulizia sistema mancante"
[[ -s "$PROJECT_DIR/docs/boot-branding.md" ]] || fail "guida branding di avvio mancante"
[[ -s "$PROJECT_DIR/assets/branding/boot-logo.png" ]] || fail "logo Plymouth predefinito mancante"
if grep -Fq 'plymouth-set-default-theme' "$INSTALLER"; then
    fail "il comando Plymouth rimosso da Ubuntu 24.04 è ancora utilizzato"
fi
grep -Fq 'readlink -f /usr/share/plymouth/themes/default.plymouth' "$INSTALLER" || \
    fail "il tema Plymouth attivo non viene verificato tramite alternatives"
grep -Fq 'previous_default_sha256=1a063958609eb258b14679213e0739cdca87cf4a4f0669d5ddc41e19a208a5d1' "$INSTALLER" || \
    fail "migrazione del precedente logo Plymouth mancante"
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
ln -s "$tmp_dir/magicq-touch" "$tmp_dir/magicq-touch-status"
ln -s "$tmp_dir/magicq-touch" "$tmp_dir/magicq-touch-config"

PATH="$mock_bin:$PATH" MAGICQ_TOUCH_CONFIG="$touch_config" \
    TOUCH_TEST_LOG="$touch_log" bash "$tmp_dir/magicq-touch-status" --summary | \
    grep -Fq '1 detected; mode: auto; target: ready' || \
    fail "diagnostica touchscreen simulata non riuscita"

PATH="$mock_bin:$PATH" MAGICQ_TOUCH_CONFIG="$touch_config" \
    TOUCH_TEST_LOG="$touch_log" bash "$tmp_dir/magicq-touch-config" \
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
    MAGICQ_VNC_CONFIG_DIR="$vnc_config_dir"
    MAGICQ_VNC_RUNTIME_DIR="$vnc_runtime_dir"
    DISPLAY=:0
    XAUTHORITY="$tmp_dir/test.Xauthority"
)

vnc_start_output=$(env "${vnc_env[@]}" bash "$tmp_dir/magicq-vnc-start" --lan) || \
    fail "avvio VNC simulato non riuscito: $vnc_start_output"
grep -Fq 'vnc://192.0.2.10:5900' <<<"$vnc_start_output" || \
    fail "indirizzo VNC inatteso: $vnc_start_output"
[[ -s "$vnc_runtime_dir/wasalight-x11vnc.pid" ]] || fail "PID VNC non registrato"
vnc_test_pid=$(<"$vnc_runtime_dir/wasalight-x11vnc.pid")
kill -0 "$vnc_test_pid" 2>/dev/null || fail "processo VNC simulato non attivo"

vnc_stop_output=$(env "${vnc_env[@]}" bash "$tmp_dir/magicq-vnc-stop") || \
    fail "arresto VNC simulato non riuscito: $vnc_stop_output"
grep -Fq 'VNC stopped.' <<<"$vnc_stop_output" || \
    fail "risposta arresto VNC inattesa: $vnc_stop_output"
kill -0 "$vnc_test_pid" 2>/dev/null && fail "processo VNC simulato ancora attivo"
vnc_test_pid=
[[ ! -e "$vnc_runtime_dir/wasalight-x11vnc.pid" ]] || fail "PID VNC non rimosso"

printf 'Progetto verificato: sintassi e componenti essenziali presenti.\n'
