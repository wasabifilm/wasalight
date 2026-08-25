#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Build the small Wasalight network installer from Canonical's Ubuntu Mini ISO.

set -Eeuo pipefail

die() { printf '\nERRORE: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
RELEASE_MANIFEST="$PROJECT_DIR/release-manifest.ini"
MANIFEST_LIBRARY="$PROJECT_DIR/lib/wasalight-release-manifest.sh"
[[ -r "$RELEASE_MANIFEST" ]] || die "release-manifest.ini non trovato: $RELEASE_MANIFEST"
[[ -r "$MANIFEST_LIBRARY" ]] || die "loader manifest non trovato: $MANIFEST_LIBRARY"
# shellcheck source=../lib/wasalight-release-manifest.sh
. "$MANIFEST_LIBRARY"

VERSION_FILE_NAME="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder VersionFile \
  '^Minimal-ISO-Builder/[A-Za-z0-9][A-Za-z0-9._-]*$' 'a path below Minimal-ISO-Builder')" || exit 1
UBUNTU_VERSION="$(require_manifest_value_matching "$RELEASE_MANIFEST" Platform UbuntuVersion \
  '^[0-9]+\.[0-9]+$' 'a major.minor version')" || exit 1
UBUNTU_POINT_RELEASE="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder UbuntuPointRelease \
  '^[0-9]+\.[0-9]+\.[0-9]+$' 'a major.minor.patch version')" || exit 1
TARGET_ARCHITECTURE="$(require_manifest_value_matching "$RELEASE_MANIFEST" Platform Architecture \
  '^[A-Za-z0-9][A-Za-z0-9._-]*$' 'an architecture name')" || exit 1
MINI_ISO_FILE="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder MiniISOFile \
  '^[A-Za-z0-9][A-Za-z0-9._+-]*\.iso$' 'an ISO file name')" || exit 1
MINI_SHA256="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder MiniISOSHA256 \
  '^[0-9a-fA-F]{64}$' 'a SHA-256 digest')" || exit 1
SERVER_SHA256="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOSHA256 \
  '^[0-9a-fA-F]{64}$' 'a SHA-256 digest')" || exit 1
SERVER_SIZE="$(require_manifest_positive_integer "$RELEASE_MANIFEST" ISOBuilder LiveISOSize)" || exit 1
SERVER_URL="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOURL \
  '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL')" || exit 1
WASALIGHT_REPOSITORY="$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Repository \
  '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL')" || exit 1
WASALIGHT_BRANCH="$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Branch \
  '^[A-Za-z0-9][A-Za-z0-9._/-]*$' 'a Git branch name')" || exit 1
WASALIGHT_INSTALL_REF=${WASALIGHT_INSTALL_REF:-$WASALIGHT_BRANCH}
[[ $WASALIGHT_INSTALL_REF =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || \
  die "Riferimento Wasalight non valido: $WASALIGHT_INSTALL_REF"
VERSION_FILE="$PROJECT_DIR/$VERSION_FILE_NAME"
[[ -r "$VERSION_FILE" ]] || die "VERSION non trovato: $VERSION_FILE"
INSTALLER_VERSION="$(tr -d '[:space:]' <"$VERSION_FILE")"
[[ $INSTALLER_VERSION =~ ^[0-9]+$ ]] || die "VERSION non valido: $INSTALLER_VERSION"
readonly PROJECT_DIR RELEASE_MANIFEST MANIFEST_LIBRARY VERSION_FILE_NAME VERSION_FILE
readonly UBUNTU_VERSION UBUNTU_POINT_RELEASE TARGET_ARCHITECTURE MINI_ISO_FILE
readonly MINI_SHA256 SERVER_SHA256 SERVER_SIZE SERVER_URL
readonly WASALIGHT_REPOSITORY WASALIGHT_BRANCH WASALIGHT_INSTALL_REF INSTALLER_VERSION

MINI_ISO="${1:-$SCRIPT_DIR/$MINI_ISO_FILE}"
AUTOINSTALL="${2:-$SCRIPT_DIR/autoinstall.yaml}"
OUTPUT_ISO="${3:-$SCRIPT_DIR/WASALIGHT-Installer-${UBUNTU_VERSION}-Minimal-Netboot-v${INSTALLER_VERSION}.iso}"
LOADER="$SCRIPT_DIR/netboot-iso-loader.sh"
COPY_SEED="$SCRIPT_DIR/netboot-copy-seed.sh"

DISK_SELECTOR="$SCRIPT_DIR/select-disk.sh"
KEYBOARD_SELECTOR="$SCRIPT_DIR/select-keyboard.sh"
INSTALL_WIZARD="$SCRIPT_DIR/install-wizard.py"
THEME_SCRIPT="$SCRIPT_DIR/apply-theme.sh"
UI_TEMPLATE="$SCRIPT_DIR/install-ui.sh"
POWEROFF_PROMPT="$SCRIPT_DIR/wait-for-poweroff.sh"
LOG_SAVER="$SCRIPT_DIR/save-installer-logs.sh"
PREFLIGHT_SCRIPT="$SCRIPT_DIR/preflight.sh"
FIRST_BOOT_SCRIPT="$SCRIPT_DIR/wasalight-first-boot.sh"
FIRST_BOOT_SERVICE="$SCRIPT_DIR/wasalight-first-boot.service"

output_parent="$(dirname -- "$OUTPUT_ISO")"
[[ -d "$output_parent" ]] || die "La cartella di destinazione non esiste: $output_parent"
mini_real="$(CDPATH= cd -- "$(dirname -- "$MINI_ISO")" && pwd)/$(basename -- "$MINI_ISO")"
output_real="$(CDPATH= cd -- "$output_parent" && pwd)/$(basename -- "$OUTPUT_ISO")"
[[ "$mini_real" != "$output_real" ]] || die "La ISO di output non puo' sovrascrivere la Mini ISO sorgente."

sha256sum_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

file_size() {
  case $(uname -s) in
    Darwin) stat -f '%z' "$1" ;;
    *) stat -c '%s' "$1" ;;
  esac
}

for dependency in xorriso cpio; do
  command -v "$dependency" >/dev/null 2>&1 || die "Manca $dependency."
done
for source in "$MINI_ISO" "$AUTOINSTALL" "$LOADER" "$COPY_SEED" \
  "$DISK_SELECTOR" "$KEYBOARD_SELECTOR" "$INSTALL_WIZARD" "$THEME_SCRIPT" "$UI_TEMPLATE" \
  "$POWEROFF_PROMPT" "$FIRST_BOOT_SCRIPT" "$FIRST_BOOT_SERVICE" \
  "$LOG_SAVER" \
  "$PREFLIGHT_SCRIPT" \
  "$RELEASE_MANIFEST" "$MANIFEST_LIBRARY"; do
  [[ -f $source ]] || die "File richiesto non trovato: $source"
done

for placeholder in \
  __WASALIGHT_TARGET_DISK__ \
  __WASALIGHT_DISK_GRUB_DEVICE__ \
  __WASALIGHT_EFI_GRUB_DEVICE__ \
  __WASALIGHT_KEYBOARD_LAYOUT__ \
  __WASALIGHT_KEYBOARD_VARIANT__ \
  __WASALIGHT_TIMEZONE__ \
  __WASALIGHT_PASSWORD_HASH__ \
  __WASALIGHT_INSTALL_VARIANT__ \
  __WASALIGHT_NETWORK_PRELOAD__ \
  __WASALIGHT_INSTALLER_VERSION__
do
  count=$(grep -Foc "$placeholder" "$AUTOINSTALL" || true)
  [[ "$count" == "1" ]] || \
    die "Il placeholder $placeholder deve comparire una sola volta in $AUTOINSTALL."
done

if grep -Eq 'password:[[:space:]]+["'\'']?\$[156y]\$' "$AUTOINSTALL"; then
  die "autoinstall.yaml contiene un hash password fisso."
fi

[[ $(sha256sum_file "$MINI_ISO") == "$MINI_SHA256" ]] || \
  die "Checksum Mini ISO non valido."
bash -n "$0"
sh -n "$LOADER"
sh -n "$COPY_SEED"
bash -n "$FIRST_BOOT_SCRIPT"
sh -n "$DISK_SELECTOR"
sh -n "$KEYBOARD_SELECTOR"
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' "$INSTALL_WIZARD"
sh -n "$THEME_SCRIPT"
sh -n "$POWEROFF_PROMPT"
sh -n "$LOG_SAVER"
sh -n "$PREFLIGHT_SCRIPT"
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' "$UI_TEMPLATE"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wasalight-netboot.XXXXXX")"
PARTIAL_OUTPUT=""
cleanup() {
  [[ -z "$PARTIAL_OUTPUT" ]] || rm -f -- "$PARTIAL_OUTPUT"
  chmod -R u+w "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

ISO_RELEASE_MANIFEST="$TMP/release-manifest.ini"
awk -v install_ref="$WASALIGHT_INSTALL_REF" '
  /^\[/ { section=$0 }
  section == "[Wasalight]" && /^Branch=/ {
    print "Branch=" install_ref
    replaced++
    next
  }
  { print }
  END { if (replaced != 1) exit 1 }
' "$RELEASE_MANIFEST" >"$ISO_RELEASE_MANIFEST" || \
  die "Impossibile fissare il riferimento Wasalight nel manifest ISO."
grep -Fxq "Branch=$WASALIGHT_INSTALL_REF" "$ISO_RELEASE_MANIFEST" || \
  die "Il riferimento Wasalight non è presente nel manifest ISO."

UI_SCRIPT="$TMP/install-ui.sh"
sed "s|__WASALIGHT_UBUNTU_VERSION__|$UBUNTU_VERSION|g" "$UI_TEMPLATE" >"$UI_SCRIPT"
grep -Fq '__WASALIGHT_UBUNTU_VERSION__' "$UI_SCRIPT" && \
  die "Versione Ubuntu non risolta nella UI."
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' "$UI_SCRIPT"

info "============================================================"
info " WASALIGHT Mini ISO Builder v${INSTALLER_VERSION} · NETBOOT"
info "============================================================"
info "Mini ISO : $MINI_ISO"
info "Output   : $OUTPUT_ISO"
info "Wasalight: $WASALIGHT_INSTALL_REF"
info

info "[1/5] Estraggo bootloader e initrd Canonical..."
xorriso -indev "$MINI_ISO" -ls /casper/vmlinuz >/dev/null 2>&1 || \
  die "La Mini ISO non contiene /casper/vmlinuz."
xorriso -indev "$MINI_ISO" -ls /casper/initrd >/dev/null 2>&1 || \
  die "La Mini ISO non contiene /casper/initrd."
xorriso -indev "$MINI_ISO" -ls /boot/grub/grub.cfg >/dev/null 2>&1 || \
  die "La Mini ISO non contiene GRUB."
xorriso -osirrox on -indev "$MINI_ISO" \
  -extract /boot/grub/grub.cfg "$TMP/grub-original.cfg" \
  -extract /casper/initrd "$TMP/initrd-original" >/dev/null 2>&1

info "[2/5] Creo autoinstall e overlay per il secondo avvio..."
sed \
  -e 's|__WASALIGHT_INSTALL_VARIANT__|NETBOOT|g' \
  -e 's|__WASALIGHT_NETWORK_PRELOAD__|curtin in-target --target=/target -- /usr/local/sbin/wasalight-first-boot --download-only|g' \
  -e "s|__WASALIGHT_INSTALLER_VERSION__|$INSTALLER_VERSION|g" \
  -e 's|/cdrom/wasalight|/wasalight|g' \
  "$AUTOINSTALL" >"$TMP/autoinstall.yaml"
grep -Fq 'packages: [git]' "$TMP/autoinstall.yaml" || \
  die "Git non presente nell'autoinstall NETBOOT."
grep -Fq -- '--download-only' "$TMP/autoinstall.yaml" || die "Preload Git Wasalight non configurato."
if grep -Eq '__WASALIGHT_(INSTALL_VARIANT|NETWORK_PRELOAD|INSTALLER_VERSION)__|/cdrom/wasalight' "$TMP/autoinstall.yaml"; then
  die "Autoinstall NETBOOT contiene placeholder o percorsi non risolti."
fi

FINAL_ROOT="$TMP/final-root"
install -d "$FINAL_ROOT/wasalight" "$FINAL_ROOT/scripts/casper-bottom"
install -m 0600 "$TMP/autoinstall.yaml" "$FINAL_ROOT/autoinstall.yaml"
install -m 0755 "$DISK_SELECTOR" "$FINAL_ROOT/wasalight/select-disk.sh"
install -m 0755 "$KEYBOARD_SELECTOR" "$FINAL_ROOT/wasalight/select-keyboard.sh"
install -m 0755 "$INSTALL_WIZARD" "$FINAL_ROOT/wasalight/install-wizard.py"
install -m 0755 "$THEME_SCRIPT" "$FINAL_ROOT/wasalight/apply-theme.sh"
install -m 0755 "$UI_SCRIPT" "$FINAL_ROOT/wasalight/install-ui.sh"
install -m 0755 "$POWEROFF_PROMPT" "$FINAL_ROOT/wasalight/wait-for-poweroff.sh"
install -m 0755 "$LOG_SAVER" "$FINAL_ROOT/wasalight/save-installer-logs.sh"
install -m 0755 "$PREFLIGHT_SCRIPT" "$FINAL_ROOT/wasalight/preflight.sh"
install -m 0644 "$VERSION_FILE" "$FINAL_ROOT/wasalight/VERSION"
install -m 0644 "$ISO_RELEASE_MANIFEST" "$FINAL_ROOT/wasalight/release-manifest.ini"
install -m 0644 "$MANIFEST_LIBRARY" "$FINAL_ROOT/wasalight/wasalight-release-manifest.sh"
install -m 0755 "$FIRST_BOOT_SCRIPT" "$FINAL_ROOT/wasalight/wasalight-first-boot.sh"
install -m 0644 "$FIRST_BOOT_SERVICE" "$FINAL_ROOT/wasalight/wasalight-first-boot.service"
install -m 0755 "$COPY_SEED" "$FINAL_ROOT/scripts/casper-bottom/62wasalight-seed"
(cd "$FINAL_ROOT" && find . -print | LC_ALL=C sort | cpio -o -H newc >"$TMP/final-overlay.cpio" 2>/dev/null)

info "[3/5] Personalizzo il caricatore di rete verificato..."
sed \
  -e "s|__WASALIGHT_SERVER_ISO_URL__|$SERVER_URL|g" \
  -e "s|__WASALIGHT_SERVER_ISO_SIZE__|$SERVER_SIZE|g" \
  -e "s|__WASALIGHT_SERVER_ISO_SHA256__|$SERVER_SHA256|g" \
  -e "s|__WASALIGHT_UBUNTU_POINT_RELEASE__|$UBUNTU_POINT_RELEASE|g" \
  "$LOADER" >"$TMP/30mini-iso-menu"
chmod 0755 "$TMP/30mini-iso-menu"

MINI_ROOT="$TMP/mini-root"
install -d "$MINI_ROOT/scripts/casper-premount" "$MINI_ROOT/wasalight"
install -m 0755 "$TMP/30mini-iso-menu" "$MINI_ROOT/scripts/casper-premount/30mini-iso-menu"
install -m 0644 "$TMP/final-overlay.cpio" "$MINI_ROOT/wasalight/final-overlay.cpio"
(cd "$MINI_ROOT" && find . -print | LC_ALL=C sort | cpio -o -H newc >"$TMP/mini-overlay.cpio" 2>/dev/null)
cp "$TMP/initrd-original" "$TMP/initrd"
chmod u+w "$TMP/initrd"
cat "$TMP/mini-overlay.cpio" >>"$TMP/initrd"

cat >"$TMP/grub.cfg" <<EOF
# WASALIGHT INSTALLER v${INSTALLER_VERSION} · TRUE NETBOOT
set default=0
set timeout_style=menu
set timeout=-1
set menu_color_normal=white/black
set menu_color_highlight=black/green

menuentry 'INSTALL WASALIGHT NETBOOT v${INSTALLER_VERSION}' {
    set gfxpayload=keep
    echo 'WASALIGHT NETBOOT v${INSTALLER_VERSION}'
    echo 'Verified download of Ubuntu Server ${UBUNTU_POINT_RELEASE}'
    linux /casper/vmlinuz wasalight-netboot ip=dhcp ---
    initrd /casper/initrd
}
EOF

info "[4/5] Creo la ISO ibrida BIOS/UEFI..."
PARTIAL_OUTPUT="$(mktemp "$output_parent/.$(basename -- "$OUTPUT_ISO").partial.XXXXXX")"
xorriso -abort_on SORRY -indev "$MINI_ISO" -outdev "$PARTIAL_OUTPUT" \
  -map "$TMP/initrd" /casper/initrd \
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay -compliance no_emul_toc -padding included

info "[5/5] Verifico contenuto e boot..."
xorriso -indev "$PARTIAL_OUTPUT" -ls /casper/initrd >/dev/null 2>&1
xorriso -indev "$PARTIAL_OUTPUT" -ls /boot/grub/grub.cfg >/dev/null 2>&1
boot_report=$(xorriso -indev "$PARTIAL_OUTPUT" -report_el_torito plain 2>&1)
grep -q 'BIOS' <<<"$boot_report" || die "Boot BIOS non preservato."
grep -q 'UEFI' <<<"$boot_report" || die "Boot UEFI non preservato."
[[ $(file_size "$PARTIAL_OUTPUT") -lt 209715200 ]] || \
  die "La ISO NETBOOT supera 200 MiB: build non realmente minimale."
xorriso -osirrox on -indev "$PARTIAL_OUTPUT" \
  -extract /casper/initrd "$TMP/verify-initrd" \
  -extract /boot/grub/grub.cfg "$TMP/verify-grub.cfg" >/dev/null 2>&1
cmp -s "$TMP/initrd" "$TMP/verify-initrd" || \
  die "initrd NETBOOT incorporato non corrisponde al file generato."
cmp -s "$TMP/grub.cfg" "$TMP/verify-grub.cfg" || \
  die "grub.cfg NETBOOT incorporato non corrisponde al file generato."

chmod 0644 "$PARTIAL_OUTPUT"
mv -f -- "$PARTIAL_OUTPUT" "$OUTPUT_ISO"
PARTIAL_OUTPUT=""

info
info "ISO NETBOOT v${INSTALLER_VERSION} creata: $OUTPUT_ISO"
info "Dimensione: $(du -h "$OUTPUT_ISO" | awk '{print $1}')"
info "SHA-256: $(sha256sum_file "$OUTPUT_ISO")"
