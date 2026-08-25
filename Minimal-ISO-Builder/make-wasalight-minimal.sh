#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

# WASALIGHT Ubuntu Minimal ISO Builder
# Ubuntu Server LTS - Linux + macOS
#
# Uso: crea entrambe le varianti.
#   ./make-wasalight-minimal.sh [--wasalight-ref REF] \
#     [SOURCE-LIVE.iso [AUTOINSTALL.yaml]]
#
# Variante singola:
#   ./make-wasalight-minimal.sh --variant full|netboot [--wasalight-ref REF] \
#     [SOURCE.iso [AUTOINSTALL.yaml [OUTPUT.iso]]]
#
# Dipendenza unica:
#   Ubuntu/Debian: sudo apt update && sudo apt install -y xorriso
#   macOS:         brew install xorriso

die() { printf '\nERRORE: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
Uso:
  ./make-wasalight-minimal.sh [--wasalight-ref REF] \
    [SOURCE.iso [AUTOINSTALL.yaml]]
  ./make-wasalight-minimal.sh --variant full|netboot [--wasalight-ref REF] \
    [SOURCE.iso [AUTOINSTALL.yaml [OUTPUT.iso]]]

Senza SOURCE.iso il builder usa le basi ufficiali Live Server e Mini ISO
configurate nel release-manifest.ini centrale
presenti nella propria cartella.

Senza --variant vengono create entrambe le immagini:
  full     Live Server completa, sistema Ubuntu disponibile localmente
  netboot  Mini ISO di circa 100 MB, scarica e verifica la Live Server in RAM

FULL richiede Internet per installare Git e poi Wasalight; non scarica la base
Ubuntu. NETBOOT richiede DHCP, DNS, Internet e almeno 8 GiB di RAM durante
l'installazione. `offline` resta un alias compatibile di `full`. Nessuna
variante include il pacchetto proprietario MagicQ.

Senza --wasalight-ref viene installato il branch dichiarato nel manifest. Le
ISO di release devono indicare il tag esatto, per esempio:
  --wasalight-ref v2026.08.25.1-rc.2
EOF
}

iso_has_path() {
  local iso="$1"
  local path="$2"
  xorriso -indev "$iso" -ls "$path" >/dev/null 2>&1
}

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
LIVE_ISO_FILE="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOFile \
  '^[A-Za-z0-9][A-Za-z0-9._+-]*\.iso$' 'an ISO file name')" || exit 1
LIVE_ISO_SHA256="$(require_manifest_value_matching "$RELEASE_MANIFEST" ISOBuilder LiveISOSHA256 \
  '^[0-9a-fA-F]{64}$' 'a SHA-256 digest')" || exit 1
WASALIGHT_REPOSITORY="$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Repository \
  '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL')" || exit 1
WASALIGHT_BRANCH="$(require_manifest_value_matching "$RELEASE_MANIFEST" Wasalight Branch \
  '^[A-Za-z0-9][A-Za-z0-9._/-]*$' 'a Git branch name')" || exit 1
VERSION_FILE="$PROJECT_DIR/$VERSION_FILE_NAME"
[[ -r "$VERSION_FILE" ]] || die "VERSION non trovato: $VERSION_FILE"
INSTALLER_VERSION="$(tr -d '[:space:]' <"$VERSION_FILE")"
[[ $INSTALLER_VERSION =~ ^[0-9]+$ ]] || die "VERSION non valido: $INSTALLER_VERSION"
readonly PROJECT_DIR RELEASE_MANIFEST MANIFEST_LIBRARY VERSION_FILE_NAME VERSION_FILE
readonly UBUNTU_VERSION UBUNTU_POINT_RELEASE TARGET_ARCHITECTURE LIVE_ISO_FILE
readonly LIVE_ISO_SHA256 WASALIGHT_REPOSITORY WASALIGHT_BRANCH INSTALLER_VERSION

BUILD_VARIANT=all
WASALIGHT_INSTALL_REF=$WASALIGHT_BRANCH
while (($#)); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --variant)
      (($# >= 2)) || die "--variant richiede full oppure netboot."
      BUILD_VARIANT=$2
      shift 2
      ;;
    --wasalight-ref)
      (($# >= 2)) || die "--wasalight-ref richiede un branch o tag Git."
      WASALIGHT_INSTALL_REF=$2
      shift 2
      ;;
    --*) die "Opzione sconosciuta: $1" ;;
    *) break ;;
  esac
done
[[ $WASALIGHT_INSTALL_REF =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || \
  die "Riferimento Wasalight non valido: $WASALIGHT_INSTALL_REF"
export WASALIGHT_INSTALL_REF
readonly WASALIGHT_INSTALL_REF

case "$BUILD_VARIANT" in
  all)
    (($# <= 2)) || die "Con entrambe le varianti non specificare OUTPUT.iso."
    info "Creo le varianti FULL e NETBOOT."
    bash "$0" --variant full --wasalight-ref "$WASALIGHT_INSTALL_REF" "$@"
    if (($# == 0)); then
      bash "$0" --variant netboot --wasalight-ref "$WASALIGHT_INSTALL_REF"
    else
      bash "$0" --variant netboot --wasalight-ref "$WASALIGHT_INSTALL_REF" \
        "" "${2:-$SCRIPT_DIR/autoinstall.yaml}"
    fi
    exit 0
    ;;
  full|offline)
    BUILD_VARIANT=full
    VARIANT_LABEL=FULL
    NETWORK_PRELOAD_VALUE="sh -c 'true'"
    DEFAULT_OUTPUT="$SCRIPT_DIR/WASALIGHT-Installer-${UBUNTU_VERSION}-Minimal-Full-v${INSTALLER_VERSION}.iso"
    ;;
  netboot)
    exec bash "$SCRIPT_DIR/make-wasalight-netboot.sh" "$@"
    ;;
  *) die "Variante sconosciuta: $BUILD_VARIANT (usa full oppure netboot)." ;;
esac

SOURCE_ISO="${1:-}"
AUTOINSTALL="${2:-$SCRIPT_DIR/autoinstall.yaml}"
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
OUTPUT_ISO="${3:-$DEFAULT_OUTPUT}"

# Se non viene specificata una ISO, cercala automaticamente nella cartella.
# Il checksum approvato nel manifest limita comunque il build alla release scelta.
if [[ -z "$SOURCE_ISO" ]]; then
  ISO_CANDIDATES=()

  while IFS= read -r iso; do
    ISO_CANDIDATES+=("$iso")
  done < <(
    find "$SCRIPT_DIR" -maxdepth 1 -type f \
      \( -name "ubuntu-${UBUNTU_VERSION}*-live-server-${TARGET_ARCHITECTURE}.iso" \
         -o -name "ubuntu-${UBUNTU_VERSION}*-server-${TARGET_ARCHITECTURE}.iso" \) \
      -print | sort
  )

  case "${#ISO_CANDIDATES[@]}" in
    0)
      die "Nessuna ISO Ubuntu Server ${UBUNTU_VERSION} ${TARGET_ARCHITECTURE} trovata nella cartella: $SCRIPT_DIR"
      ;;
    1)
      SOURCE_ISO="${ISO_CANDIDATES[0]}"
      info "ISO trovata automaticamente: $(basename "$SOURCE_ISO")"
      ;;
    *)
      echo
      echo "Trovate più ISO compatibili nella cartella:"
      for iso in "${ISO_CANDIDATES[@]}"; do
        echo "  - $(basename "$iso")"
      done
      die "Lasciane una sola nella cartella oppure passa il nome ISO come primo argomento."
      ;;
  esac
fi

md5sum_file() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    die "Non trovo md5sum o md5."
  fi
}

sha256sum_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "Non trovo sha256sum o shasum."
  fi
}

[[ -f "$SOURCE_ISO" ]] || die "ISO sorgente non trovata: $SOURCE_ISO"
[[ -f "$AUTOINSTALL" ]] || die "autoinstall.yaml non trovato: $AUTOINSTALL"
[[ -f "$DISK_SELECTOR" ]] || die "select-disk.sh non trovato: $DISK_SELECTOR"
[[ -f "$KEYBOARD_SELECTOR" ]] || die "select-keyboard.sh non trovato: $KEYBOARD_SELECTOR"
[[ -f "$INSTALL_WIZARD" ]] || die "install-wizard.py non trovato: $INSTALL_WIZARD"
[[ -f "$THEME_SCRIPT" ]] || die "apply-theme.sh non trovato: $THEME_SCRIPT"
[[ -f "$UI_TEMPLATE" ]] || die "install-ui.sh non trovato: $UI_TEMPLATE"
[[ -f "$POWEROFF_PROMPT" ]] || die "wait-for-poweroff.sh non trovato: $POWEROFF_PROMPT"
[[ -f "$LOG_SAVER" ]] || die "save-installer-logs.sh non trovato: $LOG_SAVER"
[[ -f "$PREFLIGHT_SCRIPT" ]] || die "preflight.sh non trovato: $PREFLIGHT_SCRIPT"
[[ -f "$FIRST_BOOT_SCRIPT" ]] || die "wasalight-first-boot.sh non trovato: $FIRST_BOOT_SCRIPT"
[[ -f "$FIRST_BOOT_SERVICE" ]] || die "wasalight-first-boot.service non trovato: $FIRST_BOOT_SERVICE"
[[ -f "$RELEASE_MANIFEST" ]] || die "release-manifest.ini non trovato: $RELEASE_MANIFEST"
[[ -f "$MANIFEST_LIBRARY" ]] || die "loader manifest non trovato: $MANIFEST_LIBRARY"

source_real="$(CDPATH= cd -- "$(dirname -- "$SOURCE_ISO")" && pwd)/$(basename -- "$SOURCE_ISO")"
output_parent="$(dirname -- "$OUTPUT_ISO")"
[[ -d "$output_parent" ]] || die "La cartella di destinazione non esiste: $output_parent"
output_real="$(CDPATH= cd -- "$output_parent" && pwd)/$(basename -- "$OUTPUT_ISO")"
[[ "$source_real" != "$output_real" ]] || die "La ISO di output non puo' sovrascrivere la ISO sorgente."

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

bash -n "$0" || die "Errore di sintassi nel builder."
for script in "$DISK_SELECTOR" "$KEYBOARD_SELECTOR" "$THEME_SCRIPT" "$POWEROFF_PROMPT" "$LOG_SAVER" "$PREFLIGHT_SCRIPT"; do
  sh -n "$script" || die "Errore di sintassi in: $script"
done
command -v python3 >/dev/null 2>&1 || die "Manca python3 per validare la UI."
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' "$INSTALL_WIZARD"
bash -n "$FIRST_BOOT_SCRIPT" || die "Errore di sintassi in: $FIRST_BOOT_SCRIPT"
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' \
  "$UI_TEMPLATE" || die "Errore di sintassi Python in: $UI_TEMPLATE"

if ! command -v xorriso >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin) die "Manca xorriso. Su macOS: brew install xorriso" ;;
    Linux)  die "Manca xorriso. Su Ubuntu/Debian: sudo apt update && sudo apt install -y xorriso" ;;
    *)      die "Manca xorriso. Installalo con il package manager del sistema." ;;
  esac
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wasalight.XXXXXX")"
PARTIAL_OUTPUT=""
cleanup() {
  [[ -z "$PARTIAL_OUTPUT" ]] || rm -f -- "$PARTIAL_OUTPUT"
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
if grep -Fq '__WASALIGHT_UBUNTU_VERSION__' "$UI_SCRIPT"; then
  die "Versione Ubuntu non risolta nella UI."
fi
python3 -c 'compile(open(__import__("sys").argv[1], encoding="utf-8").read(), __import__("sys").argv[1], "exec")' \
  "$UI_SCRIPT" || die "Errore di sintassi Python nella UI generata."

info "============================================================"
info " WASALIGHT Minimal ISO Builder v${INSTALLER_VERSION} · ${VARIANT_LABEL}"
info "============================================================"
info "Sistema      : $(uname -s)"
info "ISO sorgente : $SOURCE_ISO"
info "Autoinstall  : $AUTOINSTALL"
info "ISO finale   : $OUTPUT_ISO"
info "Variante     : $VARIANT_LABEL"
info "Wasalight ref: $WASALIGHT_INSTALL_REF"
info

info "[1/7] Controllo la ISO Ubuntu..."

source_sha256=$(sha256sum_file "$SOURCE_ISO")
if [[ "$source_sha256" != "$LIVE_ISO_SHA256" ]]; then
  die "$(printf 'Checksum ISO non riconosciuto. Atteso Ubuntu Server %s %s ufficiale (%s).\n  atteso: %s\n  trovato: %s' \
    "$UBUNTU_POINT_RELEASE" "$TARGET_ARCHITECTURE" "$LIVE_ISO_FILE" "$LIVE_ISO_SHA256" "$source_sha256")"
fi
info "    SHA-256 Canonical verificato: $source_sha256"

info "    verifico /casper/vmlinuz"
iso_has_path "$SOURCE_ISO" /casper/vmlinuz || \
  die "La ISO non contiene /casper/vmlinuz."

info "    verifico /casper/initrd"
iso_has_path "$SOURCE_ISO" /casper/initrd || \
  die "La ISO non contiene /casper/initrd."

info "    verifico /casper/install-sources.yaml"
iso_has_path "$SOURCE_ISO" /casper/install-sources.yaml || \
  die "Manca /casper/install-sources.yaml. Usa la ISO Ubuntu Server ${UBUNTU_POINT_RELEASE} ufficiale."

info "    ISO valida."

info "[2/7] Leggo install-sources.yaml e GRUB..."

xorriso -osirrox on -indev "$SOURCE_ISO" \
  -extract /casper/install-sources.yaml "$TMP/install-sources.yaml" >/dev/null 2>&1

xorriso -osirrox on -indev "$SOURCE_ISO" \
  -extract /boot/grub/grub.cfg "$TMP/grub-original.cfg" >/dev/null 2>&1

# Estrae id e path delle sorgenti top-level senza dipendenze YAML esterne.
awk '
function flush() {
  if (id != "" || path != "") print id "\t" path
  id=""; path=""
}
/^- / { flush() }
{
  if ($0 ~ /^[[:space:]]+id:[[:space:]]*/) {
    line=$0
    sub(/^[[:space:]]+id:[[:space:]]*/, "", line)
    gsub(/^["'\'']|["'\'']$/, "", line)
    id=line
  }
  if ($0 ~ /^[[:space:]]+path:[[:space:]]*/) {
    line=$0
    sub(/^[[:space:]]+path:[[:space:]]*/, "", line)
    gsub(/^["'\'']|["'\'']$/, "", line)
    path=line
  }
}
END { flush() }
' "$TMP/install-sources.yaml" > "$TMP/sources.tsv"

MINIMAL_PATH="$(awk -F '\t' '$1=="ubuntu-server-minimal"{print $2; exit}' "$TMP/sources.tsv")"
[[ -n "$MINIMAL_PATH" ]] || die "La ISO non dichiara la sorgente ubuntu-server-minimal."
iso_has_path "$SOURCE_ISO" "/casper/$MINIMAL_PATH" || \
  die "La sorgente minimal dichiarata ($MINIMAL_PATH) non esiste nella ISO."

info "    Sorgente minimal: /casper/$MINIMAL_PATH"

info "[3/7] Lascio Ubuntu Server Minimal come unica sorgente..."

awk '
function emit() {
  if (!have) return
  if (minimal) {
    n=split(block, lines, "\n")
    for (i=1; i<=n; i++) {
      if (lines[i] !~ /^[[:space:]]+default:[[:space:]]*/)
        print lines[i]
    }
    print "  default: true"
  }
  block=""; have=0; minimal=0
}
/^- / {
  emit()
  block=$0
  have=1
  next
}
{
  if (have) {
    block=block "\n" $0
    if ($0 ~ /^[[:space:]]+id:[[:space:]]*ubuntu-server-minimal[[:space:]]*$/)
      minimal=1
  }
}
END { emit() }
' "$TMP/install-sources.yaml" > "$TMP/install-sources-minimal.yaml"

grep -q 'id:[[:space:]]*ubuntu-server-minimal' "$TMP/install-sources-minimal.yaml" || \
  die "Errore creando install-sources.yaml minimal-only."

info "[4/7] Mantengo intatti i layer Casper necessari al boot..."
info "    Nessun file squashfs viene rimosso."
info "    Ubuntu Server Minimal resta comunque l'unica sorgente installabile"
info "    tramite /casper/install-sources.yaml."
: > "$TMP/remove.txt"

info "[5/7] Creo il menu WASALIGHT..."

sed -E \
  -e '/^[[:space:]]*set[[:space:]]+default=/d' \
  -e '/^[[:space:]]*set[[:space:]]+timeout=/d' \
  -e '/^[[:space:]]*set[[:space:]]+timeout_style=/d' \
  "$TMP/grub-original.cfg" > "$TMP/grub-original-clean.cfg"

cat > "$TMP/grub.cfg" <<GRUB
# ============================================================
# WASALIGHT INSTALLER v${INSTALLER_VERSION} ${VARIANT_LABEL}
# ============================================================

set default=0
set timeout_style=menu
set timeout=-1
set menu_color_normal=white/black
set menu_color_highlight=black/green

menuentry 'INSTALL WASALIGHT ${VARIANT_LABEL} v${INSTALLER_VERSION}' {
    set gfxpayload=keep
    echo
    echo 'WASALIGHT INSTALLER v${INSTALLER_VERSION} - ${VARIANT_LABEL}'
    echo 'Ubuntu is included locally - Internet is required for Wasalight'
    echo
    linux /casper/vmlinuz autoinstall ---
    initrd /casper/initrd
}

menuentry '--- UBUNTU / RECOVERY ---' {
    echo 'Use the Ubuntu entries below for a manual installation.'
    sleep 2
}

GRUB

cat "$TMP/grub-original-clean.cfg" >> "$TMP/grub.cfg"
sed \
  -e "s|__WASALIGHT_INSTALL_VARIANT__|$VARIANT_LABEL|g" \
  -e "s|__WASALIGHT_NETWORK_PRELOAD__|$NETWORK_PRELOAD_VALUE|g" \
  -e "s|__WASALIGHT_INSTALLER_VERSION__|$INSTALLER_VERSION|g" \
  "$AUTOINSTALL" > "$TMP/autoinstall.yaml"
grep -Fq 'packages: [git]' "$TMP/autoinstall.yaml" || \
  die "Git non presente nell'autoinstall FULL."

info "[6/7] Aggiorno i checksum..."

HAVE_MD5=0
if iso_has_path "$SOURCE_ISO" /md5sum.txt; then
  HAVE_MD5=1

  xorriso -osirrox on -indev "$SOURCE_ISO" \
    -extract /md5sum.txt "$TMP/md5sum-original.txt" >/dev/null 2>&1

  cp "$TMP/md5sum-original.txt" "$TMP/md5sum.filtered"
  chmod u+w "$TMP/md5sum.filtered"

  # Filtra checksum dei file rimossi.
  if [[ -s "$TMP/remove.txt" ]]; then
    while IFS= read -r removed; do
      rel=".${removed}"
      awk -v rel="$rel" '
        {
          f=$0
          sub(/^[0-9a-fA-F]+[[:space:]]+[*]?/, "", f)
          if (f != rel) print
        }
      ' "$TMP/md5sum.filtered" > "$TMP/md5sum.next"
      mv -f "$TMP/md5sum.next" "$TMP/md5sum.filtered"
    done < "$TMP/remove.txt"
  fi

  # Filtra checksum dei file che sostituiamo.
  for rel in \
    "./boot/grub/grub.cfg" \
    "./casper/install-sources.yaml" \
    "./autoinstall.yaml" \
    "./wasalight/select-disk.sh" \
    "./wasalight/select-keyboard.sh" \
    "./wasalight/install-wizard.py" \
    "./wasalight/apply-theme.sh" \
    "./wasalight/install-ui.sh" \
    "./wasalight/wait-for-poweroff.sh" \
    "./wasalight/save-installer-logs.sh" \
    "./wasalight/preflight.sh" \
    "./wasalight/VERSION" \
    "./wasalight/release-manifest.ini" \
    "./wasalight/wasalight-release-manifest.sh" \
    "./wasalight/wasalight-first-boot.sh" \
    "./wasalight/wasalight-first-boot.service"
  do
    awk -v rel="$rel" '
      {
        f=$0
        sub(/^[0-9a-fA-F]+[[:space:]]+[*]?/, "", f)
        if (f != rel) print
      }
    ' "$TMP/md5sum.filtered" > "$TMP/md5sum.next"
    mv -f "$TMP/md5sum.next" "$TMP/md5sum.filtered"
  done

  {
    cat "$TMP/md5sum.filtered"
    printf '%s  ./boot/grub/grub.cfg\n' "$(md5sum_file "$TMP/grub.cfg")"
    printf '%s  ./casper/install-sources.yaml\n' "$(md5sum_file "$TMP/install-sources-minimal.yaml")"
    printf '%s  ./autoinstall.yaml\n' "$(md5sum_file "$TMP/autoinstall.yaml")"
    printf '%s  ./wasalight/select-disk.sh\n' "$(md5sum_file "$DISK_SELECTOR")"
    printf '%s  ./wasalight/select-keyboard.sh\n' "$(md5sum_file "$KEYBOARD_SELECTOR")"
    printf '%s  ./wasalight/install-wizard.py\n' "$(md5sum_file "$INSTALL_WIZARD")"
    printf '%s  ./wasalight/apply-theme.sh\n' "$(md5sum_file "$THEME_SCRIPT")"
    printf '%s  ./wasalight/install-ui.sh\n' "$(md5sum_file "$UI_SCRIPT")"
    printf '%s  ./wasalight/wait-for-poweroff.sh\n' "$(md5sum_file "$POWEROFF_PROMPT")"
    printf '%s  ./wasalight/save-installer-logs.sh\n' "$(md5sum_file "$LOG_SAVER")"
    printf '%s  ./wasalight/preflight.sh\n' "$(md5sum_file "$PREFLIGHT_SCRIPT")"
    printf '%s  ./wasalight/VERSION\n' "$(md5sum_file "$VERSION_FILE")"
    printf '%s  ./wasalight/release-manifest.ini\n' "$(md5sum_file "$ISO_RELEASE_MANIFEST")"
    printf '%s  ./wasalight/wasalight-release-manifest.sh\n' "$(md5sum_file "$MANIFEST_LIBRARY")"
    printf '%s  ./wasalight/wasalight-first-boot.sh\n' "$(md5sum_file "$FIRST_BOOT_SCRIPT")"
    printf '%s  ./wasalight/wasalight-first-boot.service\n' "$(md5sum_file "$FIRST_BOOT_SERVICE")"
  } > "$TMP/md5sum.txt"
fi

info "[7/7] Creo la ISO ibrida BIOS/UEFI..."

PARTIAL_OUTPUT="$(mktemp "$output_parent/.$(basename -- "$OUTPUT_ISO").partial.XXXXXX")"

ARGS=(
  -abort_on SORRY
  -indev "$SOURCE_ISO"
  -outdev "$PARTIAL_OUTPUT"
)

ARGS+=(
  -map "$TMP/autoinstall.yaml" /autoinstall.yaml
  -map "$DISK_SELECTOR" /wasalight/select-disk.sh
  -map "$KEYBOARD_SELECTOR" /wasalight/select-keyboard.sh
  -map "$INSTALL_WIZARD" /wasalight/install-wizard.py
  -map "$THEME_SCRIPT" /wasalight/apply-theme.sh
  -map "$UI_SCRIPT" /wasalight/install-ui.sh
  -map "$POWEROFF_PROMPT" /wasalight/wait-for-poweroff.sh
  -map "$LOG_SAVER" /wasalight/save-installer-logs.sh
  -map "$PREFLIGHT_SCRIPT" /wasalight/preflight.sh
  -map "$VERSION_FILE" /wasalight/VERSION
  -map "$ISO_RELEASE_MANIFEST" /wasalight/release-manifest.ini
  -map "$MANIFEST_LIBRARY" /wasalight/wasalight-release-manifest.sh
  -map "$FIRST_BOOT_SCRIPT" /wasalight/wasalight-first-boot.sh
  -map "$FIRST_BOOT_SERVICE" /wasalight/wasalight-first-boot.service
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg
  -map "$TMP/install-sources-minimal.yaml" /casper/install-sources.yaml
)

if [[ "$HAVE_MD5" == "1" ]]; then
  ARGS+=(-map "$TMP/md5sum.txt" /md5sum.txt)
fi

# Ripristina le informazioni di boot El Torito/GPT/MBR della ISO Canonical.
ARGS+=(
  -boot_image any replay
  -compliance no_emul_toc
  -padding included
)

if ! xorriso "${ARGS[@]}"; then
  die "xorriso ha segnalato un errore. La ISO parziale è stata eliminata."
fi

info
info "Verifica finale..."

iso_has_path "$PARTIAL_OUTPUT" /autoinstall.yaml || \
  die "autoinstall.yaml manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/select-disk.sh || \
  die "select-disk.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/select-keyboard.sh || \
  die "select-keyboard.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/install-wizard.py || \
  die "install-wizard.py manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/apply-theme.sh || \
  die "apply-theme.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/install-ui.sh || \
  die "install-ui.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/wait-for-poweroff.sh || \
  die "wait-for-poweroff.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/save-installer-logs.sh || \
  die "save-installer-logs.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/preflight.sh || \
  die "preflight.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/VERSION || \
  die "VERSION manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/release-manifest.ini || \
  die "release-manifest.ini manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/wasalight-release-manifest.sh || \
  die "loader manifest manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/wasalight-first-boot.sh || \
  die "wasalight-first-boot.sh manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /wasalight/wasalight-first-boot.service || \
  die "wasalight-first-boot.service manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" /casper/install-sources.yaml || \
  die "install-sources.yaml manca nella ISO finale."
iso_has_path "$PARTIAL_OUTPUT" "/casper/$MINIMAL_PATH" || \
  die "La sorgente minimal manca nella ISO finale."

install -d "$TMP/verify"
xorriso -osirrox on -indev "$PARTIAL_OUTPUT" \
  -extract /autoinstall.yaml "$TMP/verify/autoinstall.yaml" \
  -extract /wasalight/select-disk.sh "$TMP/verify/select-disk.sh" \
  -extract /wasalight/select-keyboard.sh "$TMP/verify/select-keyboard.sh" \
  -extract /wasalight/install-wizard.py "$TMP/verify/install-wizard.py" \
  -extract /wasalight/apply-theme.sh "$TMP/verify/apply-theme.sh" \
  -extract /wasalight/install-ui.sh "$TMP/verify/install-ui.sh" \
  -extract /wasalight/wait-for-poweroff.sh "$TMP/verify/wait-for-poweroff.sh" \
  -extract /wasalight/save-installer-logs.sh "$TMP/verify/save-installer-logs.sh" \
  -extract /wasalight/preflight.sh "$TMP/verify/preflight.sh" \
  -extract /wasalight/VERSION "$TMP/verify/VERSION" \
  -extract /wasalight/release-manifest.ini "$TMP/verify/release-manifest.ini" \
  -extract /wasalight/wasalight-release-manifest.sh "$TMP/verify/wasalight-release-manifest.sh" \
  -extract /wasalight/wasalight-first-boot.sh "$TMP/verify/wasalight-first-boot.sh" \
  -extract /wasalight/wasalight-first-boot.service "$TMP/verify/wasalight-first-boot.service" \
  >/dev/null 2>&1
cmp -s "$TMP/autoinstall.yaml" "$TMP/verify/autoinstall.yaml" || \
  die "autoinstall.yaml incorporato non corrisponde al file generato."
cmp -s "$DISK_SELECTOR" "$TMP/verify/select-disk.sh" || \
  die "select-disk.sh incorporato non corrisponde al sorgente."
cmp -s "$KEYBOARD_SELECTOR" "$TMP/verify/select-keyboard.sh" || \
  die "select-keyboard.sh incorporato non corrisponde al sorgente."
cmp -s "$INSTALL_WIZARD" "$TMP/verify/install-wizard.py" || \
  die "install-wizard.py incorporato non corrisponde al sorgente."
cmp -s "$THEME_SCRIPT" "$TMP/verify/apply-theme.sh" || \
  die "apply-theme.sh incorporato non corrisponde al sorgente."
cmp -s "$UI_SCRIPT" "$TMP/verify/install-ui.sh" || \
  die "install-ui.sh incorporato non corrisponde al sorgente."
cmp -s "$POWEROFF_PROMPT" "$TMP/verify/wait-for-poweroff.sh" || \
  die "wait-for-poweroff.sh incorporato non corrisponde al sorgente."
cmp -s "$LOG_SAVER" "$TMP/verify/save-installer-logs.sh" || \
  die "save-installer-logs.sh incorporato non corrisponde al sorgente."
cmp -s "$PREFLIGHT_SCRIPT" "$TMP/verify/preflight.sh" || \
  die "preflight.sh incorporato non corrisponde al sorgente."
cmp -s "$VERSION_FILE" "$TMP/verify/VERSION" || \
  die "VERSION incorporato non corrisponde al sorgente."
cmp -s "$ISO_RELEASE_MANIFEST" "$TMP/verify/release-manifest.ini" || \
  die "release-manifest.ini incorporato non contiene il riferimento richiesto."
cmp -s "$MANIFEST_LIBRARY" "$TMP/verify/wasalight-release-manifest.sh" || \
  die "loader manifest incorporato non corrisponde al sorgente."
cmp -s "$FIRST_BOOT_SCRIPT" "$TMP/verify/wasalight-first-boot.sh" || \
  die "wasalight-first-boot.sh incorporato non corrisponde al sorgente."
cmp -s "$FIRST_BOOT_SERVICE" "$TMP/verify/wasalight-first-boot.service" || \
  die "wasalight-first-boot.service incorporato non corrisponde al sorgente."
boot_report=$(xorriso -indev "$PARTIAL_OUTPUT" -report_el_torito plain 2>&1)
grep -q 'BIOS' <<<"$boot_report" || die "Boot BIOS non preservato."
grep -q 'UEFI' <<<"$boot_report" || die "Boot UEFI non preservato."

chmod 0644 "$PARTIAL_OUTPUT"
mv -f -- "$PARTIAL_OUTPUT" "$OUTPUT_ISO"
PARTIAL_OUTPUT=""


info
info "============================================================"
info " ISO WASALIGHT ${VARIANT_LABEL} v${INSTALLER_VERSION} CREATA"
info "============================================================"
info "File: $OUTPUT_ISO"
info
info "Caratteristiche:"
info "  - Ubuntu Server ${UBUNTU_VERSION} LTS"
info "  - ubuntu-server-minimal come unica sorgente installabile"
info "  - layer Casper originali preservati"
if [[ $BUILD_VARIANT == full ]]; then
  info "  - sistema base installato dalla ISO"
  info "  - Internet richiesto per Git e Wasalight"
else
  info "  - rete richiesta durante l'installazione"
  info "  - checkout Wasalight verificato e preparato durante l'autoinstall"
fi
info "  - Git installato dai repository Ubuntu"
info "  - Wasalight ${WASALIGHT_INSTALL_REF} installato automaticamente al primo avvio con rete"
info "  - autoinstall.yaml incluso"
info "  - password chamsys scelta durante l'installazione"
info "  - SSH non installato e accesso password SSH disabilitato"
info "  - disco minimo 32 GiB"
info "  - boot installer e sistema installato compatibili BIOS/UEFI"
info "  - nessun avvio distruttivo a tempo: serve premere ENTER"
info "  - voci Ubuntu originali disponibili come recovery"
info
info "Prima dell'uso su hardware con dati, testare almeno una volta in VM."
info "Nota: MagicQ non e' incluso; il relativo pacchetto proprietario resta esterno."
