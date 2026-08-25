#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

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
grep -Fq 'exec "$PROJECT_DIR/bin/chamsys_install_ubuntu.sh" "$@"' "$ENTRYPOINT" || \
    fail "install.sh non delega direttamente al motore unico"
grep -Fq 'discover_magicq_from_usb' "$PROJECT_DIR/installer/modules/10-base.sh" || \
    fail "il motore unico non cerca MagicQ sulle USB iniziali"
grep -Fq 'dpkg --compare-versions' "$PROJECT_DIR/installer/modules/10-base.sh" || \
    fail "il motore unico sceglie MagicQ dal nome file invece che dalla versione Debian"

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
    'BootstrapPackagesFile=packages/wasalight-bootstrap.txt' \
    'RuntimePackagesFile=packages/wasalight-runtime.txt' \
    '[Updates]' 'DefaultChannel=stable' \
    'StableAPI=https://api.github.com/repos/wasabifilm/wasalight/releases/latest' \
    'DebugRef=refs/heads/main' 'TagPrefix=v' \
    'SignerFile=/etc/wasalight/update-signers' \
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
    'RuntimePackagesFile=packages/companion-runtime.txt' \
    'Commit=07024263dbb54512f3acdc705eca70cd74dbae43' \
    '[MagicQ]' 'RuntimePackagesFile=packages/magicq-runtime.txt'; do
    grep -Fqx "$declaration" "$RELEASE_MANIFEST" || \
        fail "valore release centralizzato mancante: $declaration"
done
[[ -s $ISO_BUILDER_RELEASE_TEST ]] || fail "test configurazione ISO Builder mancante"
bash "$ISO_BUILDER_RELEASE_TEST"

STATIC_TEST_DIR="$PROJECT_DIR/tests/static"
static_test_lines=0
for static_suite in installer control-plugins runtime; do
    static_test="$STATIC_TEST_DIR/$static_suite.sh"
    [[ -s $static_test ]] || fail "suite statica mancante: $static_test"
    static_test_lines=$((static_test_lines + $(wc -l <"$static_test")))
    # Le suite condividono intenzionalmente il contesto preparato qui sopra.
    # shellcheck source=/dev/null
    source "$static_test"
done
((static_test_lines >= 1600)) || \
    fail "la modularizzazione ha perso una parte sostanziale dei controlli statici"
