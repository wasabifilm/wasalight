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
    'mountpoint=/stick'
    'ID_FS_TYPE}=="vfat|exfat|ntfs"'
    'magicq-maintenance'
    'magicq-protect'
    'magicq-status'
    'OS:         $os'
    'xinput libinput-tools'
    'libglu1-mesa libgl1-mesa-dri'
    'openbox tint2 pcmanfm lxterminal lxrandr x11vnc procps'
    "grep -F 'libGLU.so.1'"
    'MagicQ has unresolved runtime libraries'
    '--with-onscreen-keyboard'
    '--chamsys-admin'
    'audio video plugdev sudo adm systemd-journal'
    'passwd "$TARGET_USER"'
    '/data/system/touchscreen/config'
    'magicq-touch-status'
    'magicq-touch-config'
    'magicq-touch-watch'
    'magicq-vnc-start'
    'magicq-vnc-stop'
    'magicq-vnc-password'
    'existing_groups_csv audio video plugdev'
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
    /usr/local/bin/magicq-touch
    /usr/local/bin/magicq-vnc-password
    /usr/local/bin/magicq-vnc-start
    /usr/local/bin/magicq-vnc-stop
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

[[ -s "$PROJECT_DIR/docs/touchscreen.md" ]] || fail "guida touchscreen mancante"
grep -Fq 'magicq-touch-config set' "$PROJECT_DIR/docs/touchscreen.md" || \
    fail "configurazione touchscreen non documentata"
[[ -s "$PROJECT_DIR/docs/migration-24.04.md" ]] || fail "guida migrazione 24.04 mancante"
[[ -s "$PROJECT_DIR/docs/vnc.md" ]] || fail "guida VNC mancante"
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
grep -Fq -- '--chamsys-admin' "$PROJECT_DIR/README.md" || \
    fail "l'accesso amministrativo chamsys non è documentato"

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
