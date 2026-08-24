#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

set -Eeuo pipefail

ISO_BUILDER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd -- "$ISO_BUILDER_DIR/.." && pwd)
RELEASE_MANIFEST="$PROJECT_DIR/release-manifest.ini"
MANIFEST_LIBRARY="$PROJECT_DIR/lib/wasalight-release-manifest.sh"
PACKAGE_LIST_LIBRARY="$PROJECT_DIR/lib/wasalight-package-list.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'ERRORE: %s\n' "$*" >&2
    exit 1
}

[[ -s $RELEASE_MANIFEST ]] || fail "release-manifest.ini centrale mancante"
[[ -s $MANIFEST_LIBRARY ]] || fail "loader release manifest centrale mancante"
[[ -s $PACKAGE_LIST_LIBRARY ]] || fail "loader pacchetti runtime mancante"
# shellcheck source=../../lib/wasalight-release-manifest.sh
. "$MANIFEST_LIBRARY"
# shellcheck source=../../lib/wasalight-package-list.sh
. "$PACKAGE_LIST_LIBRARY"

version_file=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder VersionFile \
    '^Minimal-ISO-Builder/[A-Za-z0-9][A-Za-z0-9._-]*$' \
    'a path below Minimal-ISO-Builder')
runtime_packages_file=$(require_manifest_value_matching \
    "$RELEASE_MANIFEST" Wasalight RuntimePackagesFile \
    '^packages/[A-Za-z0-9][A-Za-z0-9._/-]*$' 'a path below packages')
ubuntu_version=$(require_manifest_value_matching "$RELEASE_MANIFEST" Platform UbuntuVersion \
    '^[0-9]+\.[0-9]+$' 'a major.minor version')
architecture=$(require_manifest_value_matching "$RELEASE_MANIFEST" Platform Architecture \
    '^[A-Za-z0-9][A-Za-z0-9._-]*$' 'an architecture name')
point_release=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder UbuntuPointRelease \
    '^[0-9]+\.[0-9]+\.[0-9]+$' 'a major.minor.patch version')
live_file=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOFile \
    '^[A-Za-z0-9][A-Za-z0-9._+-]*\.iso$' 'an ISO file name')
live_url=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOURL \
    '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL')
live_size=$(require_manifest_positive_integer "$RELEASE_MANIFEST" ISOBuilder LiveISOSize)
live_sha=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOSHA256 \
    '^[0-9a-fA-F]{64}$' 'a SHA-256 digest')
mini_file=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder MiniISOFile \
    '^[A-Za-z0-9][A-Za-z0-9._+-]*\.iso$' 'an ISO file name')
mini_sha=$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder MiniISOSHA256 \
    '^[0-9a-fA-F]{64}$' 'a SHA-256 digest')
repository=$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Repository \
    '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL')
branch=$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Branch \
    '^[A-Za-z0-9][A-Za-z0-9._/-]*$' 'a Git branch name')

[[ -s $PROJECT_DIR/$version_file ]] || fail "VersionFile ISO Builder non trovato"
[[ -s $PROJECT_DIR/$runtime_packages_file ]] || fail "elenco pacchetti runtime non trovato"
runtime_packages_yaml=$(wasalight_runtime_packages_yaml "$PROJECT_DIR/$runtime_packages_file") || \
    fail "elenco pacchetti runtime non valido"
[[ $runtime_packages_yaml == *git* ]] || fail "Git manca dall'elenco pacchetti runtime"
[[ $point_release == "$ubuntu_version".* ]] || \
    fail "UbuntuPointRelease non appartiene a Platform.UbuntuVersion"
[[ $live_file == *"$point_release"* && $live_file == *"$architecture.iso" ]] || \
    fail "LiveISOFile non corrisponde a release e architettura"
[[ $mini_file == *"$point_release"* && $mini_file == *"$architecture.iso" ]] || \
    fail "MiniISOFile non corrisponde a release e architettura"
[[ $live_url == */"$live_file" ]] || fail "LiveISOURL non termina con LiveISOFile"

for script in make-wasalight-minimal.sh make-wasalight-netboot.sh; do
    grep -Fq 'lib/wasalight-release-manifest.sh' "$ISO_BUILDER_DIR/$script" || \
        fail "$script non usa il loader manifest centrale"
    grep -Fq 'wasalight_runtime_packages_yaml "$RUNTIME_PACKAGES_FILE"' \
        "$ISO_BUILDER_DIR/$script" || \
        fail "$script non usa l'elenco pacchetti runtime condiviso"
done
grep -Fq 'git clone --depth 1 --branch "$branch" --single-branch' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot non usa un clone shallow"
[[ $(grep -Foc '"$checkout/tests/verify-project.sh"' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh") == 1 ]] || \
    fail "first boot deve verificare il checkout una sola volta per esecuzione"
grep -Fq 'require_manifest_value_matching "$release_manifest" Wasalight Repository' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot non legge il repository dal manifest"
grep -Fq 'git -C "$checkout" fetch origin "$branch"' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot non usa il branch centralizzato"
grep -Fq 'Before=getty@tty1.service' "$ISO_BUILDER_DIR/wasalight-first-boot.service" || \
    fail "first boot non precede la console grafica su tty1"
grep -Fq 'RequiresMountsFor=/data' "$ISO_BUILDER_DIR/wasalight-first-boot.service" || \
    fail "first boot non attende il volume /data"
grep -Fq 'active_file="/run/wasalight-first-boot-active"' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot privo del marker grafico volatile"
grep -Fq '[ ! -e /run/wasalight-first-boot-active ]' \
    "$PROJECT_DIR/installer/modules/20-network-services.sh" || \
    fail "Openbox non rispetta il marker del primo avvio"
grep -Fq '"$checkout/install.sh" --no-protection --allow-missing-magicq' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot non prepara MAINTENANCE con MagicQ opzionale"
grep -Fq "overlayroot=\"disabled\"" "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "first boot non verifica la modalita' MAINTENANCE"
grep -Fq 'rebooting into MAINTENANCE' "$ISO_BUILDER_DIR/wasalight-first-boot.sh" || \
    fail "stato finale first boot non dichiara MAINTENANCE"
reboot_line=$(grep -nF 'systemctl reboot --no-block' \
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh" | cut -d: -f1)
hold_line=$(grep -nF 'while :; do' "$ISO_BUILDER_DIR/wasalight-first-boot.sh" | tail -n1 | cut -d: -f1)
[[ $reboot_line =~ ^[0-9]+$ && $hold_line =~ ^[0-9]+$ && $hold_line -gt $reboot_line ]] || \
    fail "first boot termina prima che systemd completi il riavvio"
grep -Fq '/target/etc/wasalight/release-manifest.ini' \
    "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "autoinstall non installa il manifest nel target"
grep -Fq '__WASALIGHT_UBUNTU_POINT_RELEASE__' \
    "$ISO_BUILDER_DIR/netboot-iso-loader.sh" || \
    fail "loader NETBOOT privo del placeholder release Ubuntu"
[[ $(grep -Foc '__WASALIGHT_UBUNTU_VERSION__' "$ISO_BUILDER_DIR/install-ui.sh") == 1 ]] || \
    fail "UI priva del placeholder versione Ubuntu univoco"
[[ $(grep -Foc '__WASALIGHT_TIMEZONE__' "$ISO_BUILDER_DIR/autoinstall.yaml") == 1 ]] || \
    fail "autoinstall privo del placeholder fuso orario univoco"
for builder in make-wasalight-minimal.sh make-wasalight-netboot.sh; do
    grep -Fq '__WASALIGHT_TIMEZONE__' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non verifica il placeholder fuso orario"
done
grep -Fq 'timezone: "__WASALIGHT_TIMEZONE__"' "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "campo autoinstall.timezone non configurato"
grep -Fq '/usr/share/zoneinfo/$candidate' "$ISO_BUILDER_DIR/select-keyboard.sh" || \
    fail "selettore fuso orario non valida il database zoneinfo"
grep -Fq 's/__WASALIGHT_TIMEZONE__/$escaped_timezone/g' \
    "$ISO_BUILDER_DIR/select-keyboard.sh" || \
    fail "selettore fuso orario non risolve il placeholder"
grep -Fq '/run/wasalight-timezone-label' "$ISO_BUILDER_DIR/install-ui.sh" || \
    fail "UI installer non mostra il fuso orario scelto"
grep -Fq 'Preparing the installation' "$ISO_BUILDER_DIR/install-ui.sh" || \
    fail "UI installer non tradotta in inglese"
wizard="$ISO_BUILDER_DIR/install-wizard.py"
[[ -s $wizard ]] || fail "wizard installazione unificato mancante"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$wizard"
grep -Fq 'Type exactly ERASE to start.' "$wizard" || \
    fail "conferma distruttiva inglese mancante"
grep -Fq 'Review and confirm' "$wizard" || \
    fail "riepilogo finale prima di ERASE mancante"
for summary_value in 'Interface language' 'Keyboard' 'Time zone' 'Password' 'Boot mode' 'Storage:'; do
    grep -Fq "$summary_value" "$wizard" || \
        fail "riepilogo installazione privo di $summary_value"
done
if grep -Fq 'CANCELLA' "$wizard"; then
    fail "il selettore disco usa ancora la conferma italiana"
fi
grep -Fq 'for index in (2, 4, 10):' "$ISO_BUILDER_DIR/apply-theme.sh" || \
    fail "palette installer non uniformata"
grep -Fq 'palette[i + 0] = 118' "$ISO_BUILDER_DIR/apply-theme.sh" || \
    fail "verde Wasalight dell'updater non applicato all'installer"
grep -Fq 'shutdown: poweroff' "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "autoinstall non spegne il sistema prima della rimozione USB"
grep -Fq 'sh /cdrom/wasalight/wait-for-poweroff.sh' \
    "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "prompt di spegnimento non eseguito come ultimo late-command"
grep -Fq 'PID_FILE = Path("/run/wasalight-ui.pid")' \
    "$ISO_BUILDER_DIR/install-ui.sh" || \
    fail "UI installer priva del PID per il passaggio sicuro della console"
sh -n "$ISO_BUILDER_DIR/wait-for-poweroff.sh"
sh -n "$ISO_BUILDER_DIR/save-installer-logs.sh"
for builder in make-wasalight-minimal.sh make-wasalight-netboot.sh; do
    grep -Fq 'wait-for-poweroff.sh' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non incorpora il prompt di spegnimento"
    grep -Fq 'save-installer-logs.sh' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non incorpora il salvataggio log installer"
    grep -Fq 'preflight.sh' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non incorpora il preflight"
    grep -Fq 'install-wizard.py' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non incorpora il wizard unificato"
done
sh -n "$ISO_BUILDER_DIR/preflight.sh"
"$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone Europe/Rome || \
    fail "Europe/Rome non riconosciuto come fuso orario valido"
if "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone ../Etc/UTC; then
    fail "il selettore accetta un percorso zoneinfo con traversal"
fi
if "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone Invalid; then
    fail "il selettore accetta un fuso orario non valido"
fi

mkdir -p "$tmp_dir/xkb/symbols"
printf 'default partial alphanumeric_keys\nxkb_symbols "basic" { };\nxkb_symbols "intl" { };\n' \
    >"$tmp_dir/xkb/symbols/us"
WASALIGHT_XKB_ROOT="$tmp_dir/xkb" \
    "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-layout us intl || \
    fail "layout e variante XKB disponibili non riconosciuti"
WASALIGHT_XKB_ROOT="$tmp_dir/xkb" \
    "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-layout us || \
    fail "layout XKB predefinito non riconosciuto"
if WASALIGHT_XKB_ROOT="$tmp_dir/xkb" \
        "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-layout ../us; then
    fail "il selettore accetta un layout XKB con traversal"
fi
if WASALIGHT_XKB_ROOT="$tmp_dir/xkb" \
        "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-layout us unavailable; then
    fail "il selettore accetta una variante XKB non disponibile"
fi
mkdir -p "$tmp_dir/runtime"
cp "$ISO_BUILDER_DIR/autoinstall.yaml" "$tmp_dir/autoinstall.yaml"
printf '%s\n' en English us '' 'English (US)' Europe/Rome \
    '$6$testsalt$testhash' >"$tmp_dir/wizard-config"
WASALIGHT_XKB_ROOT="$tmp_dir/xkb" \
WASALIGHT_RUNTIME_DIR="$tmp_dir/runtime" \
WASALIGHT_AUTOINSTALL_PATH="$tmp_dir/autoinstall.yaml" \
    "$ISO_BUILDER_DIR/select-keyboard.sh" --apply-config "$tmp_dir/wizard-config" || \
    fail "backend configurazione non applica una selezione valida"
grep -Fq 'layout: "us"' "$tmp_dir/autoinstall.yaml" || \
    fail "backend configurazione non applica il layout"
grep -Fq 'timezone: "Europe/Rome"' "$tmp_dir/autoinstall.yaml" || \
    fail "backend configurazione non applica il fuso orario"
grep -Fq 'password: "$6$testsalt$testhash"' "$tmp_dir/autoinstall.yaml" || \
    fail "backend configurazione non applica l'hash temporaneo"
[[ $(<"$tmp_dir/runtime/wasalight-interface-language") == en ]] || \
    fail "backend configurazione non persiste la lingua scelta"
"$ISO_BUILDER_DIR/select-keyboard.sh" --validate-language en || \
    fail "lingua interfaccia inglese non riconosciuta"
"$ISO_BUILDER_DIR/select-keyboard.sh" --validate-language it || \
    fail "lingua interfaccia italiana non riconosciuta"
if "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-language de; then
    fail "il selettore accetta una lingua interfaccia non supportata"
fi
grep -Fq 'This choice is independent from the keyboard layout.' "$wizard" || \
    fail "indipendenza tra lingua interfaccia e tastiera non esplicitata"
grep -Fq '/run/wasalight-interface-language /target/data/system/control/language' \
    "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "lingua interfaccia scelta non persistita nel sistema installato"
grep -Fq '/run/wasalight-interface-language-label' \
    "$ISO_BUILDER_DIR/install-ui.sh" || \
    fail "UI installer non mostra la lingua interfaccia scelta"
grep -Fq 'at least 6 characters' "$wizard" || \
    fail "minimo password di 6 caratteri non mostrato"
grep -Fq 'if len(password) < 6:' "$wizard" || \
    fail "minimo password di 6 caratteri non applicato"
grep -Fq 'ckbcomp -layout' "$ISO_BUILDER_DIR/select-keyboard.sh" || \
    fail "layout XKB non convertito per la console live"
grep -Fq 'loadkeys "$keymap_file"' "$ISO_BUILDER_DIR/select-keyboard.sh" || \
    fail "layout tastiera non applicato alla console live"
grep -Fq '"Test keyboard"' "$wizard" || \
    fail "schermata di prova tastiera mancante"

wizard_command_line=$(grep -nF 'python3 /cdrom/wasalight/install-wizard.py /dev/tty1' \
    "$ISO_BUILDER_DIR/autoinstall.yaml" | cut -d: -f1)
[[ -n $wizard_command_line ]] || fail "autoinstall non avvia il wizard unificato"
if grep -Fq 'sh /cdrom/wasalight/select-' "$ISO_BUILDER_DIR/autoinstall.yaml"; then
    fail "autoinstall avvia ancora i vecchi selettori interattivi"
fi
grep -Fq 'self.run_backend(self.disk_backend, "--apply-target", self.disk["device"])' \
    "$wizard" || fail "wizard non rivalida il disco dopo ERASE"
grep -Fq 'wasalight-wizard.log' "$ISO_BUILDER_DIR/save-installer-logs.sh" || \
    fail "log errori wizard non salvato insieme ai log installer"
grep -Fq 'build_disk_list' "$ISO_BUILDER_DIR/select-disk.sh" || \
    fail "backend disco non ricostruisce l'elenco prima dell'applicazione"
grep -Fq 'selected disk contains the installation media' \
    "$ISO_BUILDER_DIR/select-disk.sh" || \
    fail "backend disco non riblocca il supporto installazione"
grep -Fq 'save-installer-logs.sh success' "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "log installer non salvati in caso di successo"
grep -Fq 'save-installer-logs.sh failed' "$ISO_BUILDER_DIR/autoinstall.yaml" || \
    fail "log installer non salvati in caso di errore"
grep -Fq 'log_dir=/target/data/log/installer' \
    "$ISO_BUILDER_DIR/save-installer-logs.sh" || \
    fail "log installer non destinati a /data/log/installer"
grep -Fq '<redacted-password-hash>' "$ISO_BUILDER_DIR/save-installer-logs.sh" || \
    fail "hash password non oscurato nei log persistenti"

[[ $($ISO_BUILDER_DIR/preflight.sh --classify-memory 1900000) == insufficient ]] || \
    fail "preflight non blocca una RAM inferiore a 2 GiB nominali"
[[ $($ISO_BUILDER_DIR/preflight.sh --classify-memory 2097152) == warning ]] || \
    fail "preflight non avvisa tra 2 e 4 GiB"
[[ $($ISO_BUILDER_DIR/preflight.sh --classify-memory 4194304) == recommended ]] || \
    fail "preflight non accetta 4 GiB"
expected_repository_host=${repository#https://}
expected_repository_host=${expected_repository_host%%/*}
expected_repository_host=${expected_repository_host%%:*}
[[ $($ISO_BUILDER_DIR/preflight.sh --repository-host "$repository") == \
    "$expected_repository_host" ]] || \
    fail "preflight non ricava l'host dal repository centralizzato"
if "$ISO_BUILDER_DIR/preflight.sh" --repository-host http://github.com/example; then
    fail "preflight accetta un repository senza HTTPS"
fi
for network_check in \
    'ip -o link show up' \
    'ip -o addr show scope global' \
    'route show default' \
    'getent ahosts "$host"' \
    'curl --fail --silent --show-error --location --head'; do
    grep -Fq "$network_check" "$ISO_BUILDER_DIR/preflight.sh" || \
        fail "preflight privo del controllo rete: $network_check"
done
preflight_command_line=$(grep -nF 'sh /cdrom/wasalight/preflight.sh' \
    "$ISO_BUILDER_DIR/autoinstall.yaml" | cut -d: -f1)
[[ $preflight_command_line -lt $wizard_command_line ]] || \
    fail "preflight eseguito dopo la configurazione interattiva"
grep -Fq 'f"Preflight' "$wizard" || \
    fail "riepilogo finale privo dell'esito preflight"

sed \
    -e "s|__WASALIGHT_SERVER_ISO_URL__|$live_url|g" \
    -e "s|__WASALIGHT_SERVER_ISO_SIZE__|$live_size|g" \
    -e "s|__WASALIGHT_SERVER_ISO_SHA256__|$live_sha|g" \
    -e "s|__WASALIGHT_UBUNTU_POINT_RELEASE__|$point_release|g" \
    "$ISO_BUILDER_DIR/netboot-iso-loader.sh" >"$tmp_dir/netboot-loader.sh"
if grep -Eq '__WASALIGHT_(SERVER_ISO|UBUNTU_POINT_RELEASE)' "$tmp_dir/netboot-loader.sh"; then
    fail "loader NETBOOT generato contiene placeholder release"
fi
sh -n "$tmp_dir/netboot-loader.sh"

sed "s|__WASALIGHT_UBUNTU_VERSION__|$ubuntu_version|g" \
    "$ISO_BUILDER_DIR/install-ui.sh" >"$tmp_dir/install-ui.py"
grep -Fq '__WASALIGHT_UBUNTU_VERSION__' "$tmp_dir/install-ui.py" && \
    fail "UI generata contiene placeholder release"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$tmp_dir/install-ui.py"

release_sources=(
    "$ISO_BUILDER_DIR/apply-theme.sh"
    "$ISO_BUILDER_DIR/autoinstall.yaml"
    "$ISO_BUILDER_DIR/install-ui.sh"
    "$ISO_BUILDER_DIR/install-wizard.py"
    "$ISO_BUILDER_DIR/make-wasalight-minimal.sh"
    "$ISO_BUILDER_DIR/make-wasalight-netboot.sh"
    "$ISO_BUILDER_DIR/netboot-copy-seed.sh"
    "$ISO_BUILDER_DIR/netboot-iso-loader.sh"
    "$ISO_BUILDER_DIR/preflight.sh"
    "$ISO_BUILDER_DIR/save-installer-logs.sh"
    "$ISO_BUILDER_DIR/select-disk.sh"
    "$ISO_BUILDER_DIR/select-keyboard.sh"
    "$ISO_BUILDER_DIR/wait-for-poweroff.sh"
    "$ISO_BUILDER_DIR/wasalight-first-boot.sh"
    "$ISO_BUILDER_DIR/wasalight-first-boot.service"
)
for literal in "$repository" "$point_release" "$live_file" "$live_url" "$live_size" \
    "$live_sha" "$mini_file" "$mini_sha"; do
    if grep -Fq "$literal" "${release_sources[@]}"; then
        fail "valore release duplicato fuori dal manifest: $literal"
    fi
done
if grep -Eq 'fetch origin main|--branch main|branch=main' "${release_sources[@]}"; then
    fail "branch Wasalight hardcoded fuori dal manifest"
fi

invalid_manifest="$tmp_dir/invalid.ini"
printf '[Broken]\nEmpty=\nBadSize=nope\nBadURL=https://example.test/a|b\nBadSHA=1234\n' \
    >"$invalid_manifest"
if require_manifest_value "$invalid_manifest" Broken Missing >/dev/null 2>&1; then
    fail "una chiave mancante viene accettata"
fi
if require_manifest_value "$invalid_manifest" Broken Empty >/dev/null 2>&1; then
    fail "un valore vuoto viene accettato"
fi
if require_manifest_positive_integer "$invalid_manifest" Broken BadSize >/dev/null 2>&1; then
    fail "una dimensione non valida viene accettata"
fi
if require_manifest_value_matching "$invalid_manifest" Broken BadURL \
        '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL' \
        >/dev/null 2>&1; then
    fail "un URL non sicuro viene accettato"
fi
if require_manifest_value_matching "$invalid_manifest" Broken BadSHA \
        '^[0-9a-fA-F]{64}$' 'a SHA-256 digest' >/dev/null 2>&1; then
    fail "un checksum non valido viene accettato"
fi

printf 'git\ninvalid package\n' >"$tmp_dir/invalid-packages.txt"
if wasalight_runtime_packages "$tmp_dir/invalid-packages.txt" >/dev/null 2>&1; then
    fail "un nome pacchetto non valido viene accettato"
fi
printf 'git\ngit\n' >"$tmp_dir/duplicate-packages.txt"
if wasalight_runtime_packages "$tmp_dir/duplicate-packages.txt" >/dev/null 2>&1; then
    fail "un pacchetto duplicato viene accettato"
fi

printf 'Configurazione release ISO Builder verificata (%s, %s, %s, %s).\n' \
    "$point_release" "$architecture" "$live_size" "$branch"
