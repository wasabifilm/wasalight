#!/usr/bin/env bash
# Build the small Wasalight network installer from Canonical's Ubuntu Mini ISO.

set -Eeuo pipefail

die() { printf '\nERRORE: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
readonly INSTALLER_VERSION=24
readonly MINI_SHA256=57bfe99e776698ae08358145cf3a58bfb74beafe8c8cf965ca86552233d2f53f
readonly SERVER_SHA256=e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433
readonly SERVER_SIZE=3405469696
readonly SERVER_URL=https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso

MINI_ISO="${1:-$SCRIPT_DIR/ubuntu-mini-iso-24.04.4-mini-iso-amd64.iso}"
AUTOINSTALL="${2:-$SCRIPT_DIR/autoinstall.yaml}"
OUTPUT_ISO="${3:-$SCRIPT_DIR/WASALIGHT-Installer-24.04-Minimal-Netboot-v${INSTALLER_VERSION}.iso}"
LOADER="$SCRIPT_DIR/netboot-iso-loader.sh"
COPY_SEED="$SCRIPT_DIR/netboot-copy-seed.sh"

DISK_SELECTOR="$SCRIPT_DIR/select-disk.sh"
KEYBOARD_SELECTOR="$SCRIPT_DIR/select-keyboard.sh"
THEME_SCRIPT="$SCRIPT_DIR/apply-theme.sh"
UI_SCRIPT="$SCRIPT_DIR/install-ui.sh"
FIRST_BOOT_SCRIPT="$SCRIPT_DIR/wasalight-first-boot.sh"
FIRST_BOOT_SERVICE="$SCRIPT_DIR/wasalight-first-boot.service"

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
  "$DISK_SELECTOR" "$KEYBOARD_SELECTOR" "$THEME_SCRIPT" "$UI_SCRIPT" \
  "$FIRST_BOOT_SCRIPT" "$FIRST_BOOT_SERVICE"; do
  [[ -f $source ]] || die "File richiesto non trovato: $source"
done

[[ $(sha256sum_file "$MINI_ISO") == "$MINI_SHA256" ]] || \
  die "Checksum Mini ISO non valido."
bash -n "$0"
sh -n "$LOADER"
sh -n "$COPY_SEED"
bash -n "$FIRST_BOOT_SCRIPT"
sh -n "$DISK_SELECTOR"
sh -n "$KEYBOARD_SELECTOR"
sh -n "$THEME_SCRIPT"
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' "$UI_SCRIPT"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wasalight-netboot.XXXXXX")"
cleanup() { chmod -R u+w "$TMP" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

info "============================================================"
info " WASALIGHT Mini ISO Builder v${INSTALLER_VERSION} · NETBOOT"
info "============================================================"
info "Mini ISO : $MINI_ISO"
info "Output   : $OUTPUT_ISO"
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
  -e 's|__WASALIGHT_PACKAGES__|[git]|g' \
  -e 's|__WASALIGHT_NETWORK_PRELOAD__|curtin in-target --target=/target -- /usr/local/sbin/wasalight-first-boot --download-only|g' \
  -e 's|/cdrom/wasalight|/wasalight|g' \
  "$AUTOINSTALL" >"$TMP/autoinstall.yaml"
grep -Fq 'packages: [git]' "$TMP/autoinstall.yaml" || die "Git non presente nell'autoinstall NETBOOT."
grep -Fq -- '--download-only' "$TMP/autoinstall.yaml" || die "Preload Git Wasalight non configurato."
if grep -Eq '__WASALIGHT_(INSTALL_VARIANT|PACKAGES|NETWORK_PRELOAD)__|/cdrom/wasalight' "$TMP/autoinstall.yaml"; then
  die "Autoinstall NETBOOT contiene placeholder o percorsi non risolti."
fi

FINAL_ROOT="$TMP/final-root"
install -d "$FINAL_ROOT/wasalight" "$FINAL_ROOT/scripts/casper-bottom"
install -m 0600 "$TMP/autoinstall.yaml" "$FINAL_ROOT/autoinstall.yaml"
install -m 0755 "$DISK_SELECTOR" "$FINAL_ROOT/wasalight/select-disk.sh"
install -m 0755 "$KEYBOARD_SELECTOR" "$FINAL_ROOT/wasalight/select-keyboard.sh"
install -m 0755 "$THEME_SCRIPT" "$FINAL_ROOT/wasalight/apply-theme.sh"
install -m 0755 "$UI_SCRIPT" "$FINAL_ROOT/wasalight/install-ui.sh"
install -m 0755 "$FIRST_BOOT_SCRIPT" "$FINAL_ROOT/wasalight/wasalight-first-boot.sh"
install -m 0644 "$FIRST_BOOT_SERVICE" "$FINAL_ROOT/wasalight/wasalight-first-boot.service"
install -m 0755 "$COPY_SEED" "$FINAL_ROOT/scripts/casper-bottom/62wasalight-seed"
(cd "$FINAL_ROOT" && find . -print | LC_ALL=C sort | cpio -o -H newc >"$TMP/final-overlay.cpio" 2>/dev/null)

info "[3/5] Personalizzo il caricatore di rete verificato..."
sed \
  -e "s|__WASALIGHT_SERVER_ISO_URL__|$SERVER_URL|g" \
  -e "s|__WASALIGHT_SERVER_ISO_SIZE__|$SERVER_SIZE|g" \
  -e "s|__WASALIGHT_SERVER_ISO_SHA256__|$SERVER_SHA256|g" \
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

menuentry 'INSTALLA WASALIGHT NETBOOT v${INSTALLER_VERSION}' {
    set gfxpayload=keep
    echo 'WASALIGHT NETBOOT v${INSTALLER_VERSION}'
    echo 'Scaricamento verificato di Ubuntu Server 24.04.4'
    linux /casper/vmlinuz wasalight-netboot ip=dhcp ---
    initrd /casper/initrd
}
EOF

info "[4/5] Creo la ISO ibrida BIOS/UEFI..."
rm -f "$OUTPUT_ISO"
xorriso -abort_on SORRY -indev "$MINI_ISO" -outdev "$OUTPUT_ISO" \
  -map "$TMP/initrd" /casper/initrd \
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay -compliance no_emul_toc -padding included

info "[5/5] Verifico contenuto e boot..."
xorriso -indev "$OUTPUT_ISO" -ls /casper/initrd >/dev/null 2>&1
xorriso -indev "$OUTPUT_ISO" -ls /boot/grub/grub.cfg >/dev/null 2>&1
boot_report=$(xorriso -indev "$OUTPUT_ISO" -report_el_torito plain 2>&1)
grep -q 'BIOS' <<<"$boot_report" || die "Boot BIOS non preservato."
grep -q 'UEFI' <<<"$boot_report" || die "Boot UEFI non preservato."
[[ $(file_size "$OUTPUT_ISO") -lt 209715200 ]] || \
  die "La ISO NETBOOT supera 200 MiB: build non realmente minimale."

info
info "ISO NETBOOT v${INSTALLER_VERSION} creata: $OUTPUT_ISO"
info "Dimensione: $(du -h "$OUTPUT_ISO" | awk '{print $1}')"
info "SHA-256: $(sha256sum_file "$OUTPUT_ISO")"
