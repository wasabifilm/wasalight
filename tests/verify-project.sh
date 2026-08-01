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
    'openbox tint2 pcmanfm lxterminal lxrandr x11vnc procps wmctrl x11-utils'
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
    'magicq-vnc-password'
    'cleanup_candidates=(pollinate)'
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

[[ -s "$PROJECT_DIR/docs/touchscreen.md" ]] || fail "guida touchscreen mancante"
grep -Fq 'magicq-touch-config set' "$PROJECT_DIR/docs/touchscreen.md" || \
    fail "configurazione touchscreen non documentata"
[[ -s "$PROJECT_DIR/docs/migration-24.04.md" ]] || fail "guida migrazione 24.04 mancante"
[[ -s "$PROJECT_DIR/docs/vnc.md" ]] || fail "guida VNC mancante"
[[ -s "$PROJECT_DIR/docs/system-cleanup.md" ]] || fail "guida pulizia sistema mancante"
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
