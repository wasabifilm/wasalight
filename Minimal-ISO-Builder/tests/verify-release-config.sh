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
grep -Fq 'To confirm, type exactly: ERASE' "$ISO_BUILDER_DIR/select-disk.sh" || \
    fail "conferma distruttiva inglese mancante"
if grep -Fq 'CANCELLA' "$ISO_BUILDER_DIR/select-disk.sh"; then
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
for builder in make-wasalight-minimal.sh make-wasalight-netboot.sh; do
    grep -Fq 'wait-for-poweroff.sh' "$ISO_BUILDER_DIR/$builder" || \
        fail "$builder non incorpora il prompt di spegnimento"
done
"$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone Europe/Rome || \
    fail "Europe/Rome non riconosciuto come fuso orario valido"
if "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone ../Etc/UTC; then
    fail "il selettore accetta un percorso zoneinfo con traversal"
fi
if "$ISO_BUILDER_DIR/select-keyboard.sh" --validate-timezone Invalid; then
    fail "il selettore accetta un fuso orario non valido"
fi

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
    "$ISO_BUILDER_DIR/make-wasalight-minimal.sh"
    "$ISO_BUILDER_DIR/make-wasalight-netboot.sh"
    "$ISO_BUILDER_DIR/netboot-copy-seed.sh"
    "$ISO_BUILDER_DIR/netboot-iso-loader.sh"
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
