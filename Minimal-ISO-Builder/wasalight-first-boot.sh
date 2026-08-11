#!/usr/bin/env bash
# Complete the Wasalight appliance setup on the first real Ubuntu boot.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly repository="https://github.com/wasabifilm/wasalight.git"
readonly checkout="/data/system/wasalight"
readonly log_dir="/data/log"
readonly log_file="$log_dir/wasalight-first-boot.log"
readonly version_file="$log_dir/wasalight-first-boot.version"
readonly complete_file="/var/lib/wasalight/first-boot-complete"

die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }

download_only=0
case "${1:-}" in
    "") ;;
    --download-only) download_only=1 ;;
    *) die "opzione sconosciuta: $1" ;;
esac

[[ $EUID -eq 0 ]] || die "il bootstrap deve essere eseguito come root"
if [[ -e $complete_file ]]; then
    echo "Wasalight risulta gia' installato: nessuna operazione necessaria."
    exit 0
fi
mountpoint -q /data || die "/data non e' montata"
[[ $(findmnt -n -o FSTYPE -M /data) == ext4 ]] || die "/data non e' ext4"
command -v git >/dev/null 2>&1 || die "Git non e' installato"

install -d -o root -g root -m 0755 /data/system /var/lib/wasalight
install -d -o chamsys -g chamsys -m 0750 "$log_dir"
touch "$log_file"
chown root:adm "$log_file" 2>/dev/null || chown root:root "$log_file"
chmod 0640 "$log_file"
exec > >(tee -a "$log_file") 2>&1

printf '\n========================================\n'
printf '  WASALIGHT · INSTALLAZIONE AUTOMATICA\n'
printf '========================================\n'
echo "Avvio: $(date --iso-8601=seconds)"
echo "Repository: $repository"

if [[ -e $checkout && ! -d $checkout/.git ]]; then
    die "il percorso $checkout esiste ma non e' un repository Git"
fi

if [[ -d $checkout/.git ]]; then
    echo "Aggiorno il checkout persistente esistente..."
    git -C "$checkout" diff --quiet || die "il checkout contiene modifiche locali"
    git -C "$checkout" diff --cached --quiet || die "l'indice Git contiene modifiche locali"
    git -C "$checkout" remote set-url origin "$repository"
    git -C "$checkout" fetch origin main
    git -C "$checkout" merge --ff-only FETCH_HEAD
else
    temporary_checkout="${checkout}.new.$$"
    cleanup() { rm -rf -- "$temporary_checkout"; }
    trap cleanup EXIT
    echo "Scarico il branch main piu' recente..."
    git clone --branch main --single-branch "$repository" "$temporary_checkout"
    "$temporary_checkout/tests/verify-project.sh"
    mv "$temporary_checkout" "$checkout"
    trap - EXIT
fi

echo "Verifico il progetto scaricato..."
"$checkout/tests/verify-project.sh"
commit=$(git -C "$checkout" rev-parse --verify HEAD)
[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "commit Git non valido: $commit"
printf 'repository=%s\nbranch=main\ncommit=%s\ndownloaded_at=%s\n' \
    "$repository" "$commit" "$(date --iso-8601=seconds)" >"$version_file"
chown root:adm "$version_file" 2>/dev/null || chown root:root "$version_file"
chmod 0640 "$version_file"

if ((download_only)); then
    echo "Codice Wasalight verificato e preparato per il primo avvio."
    exit 0
fi

echo "Installo Wasalight dal commit $commit..."
"$checkout/install.sh" --allow-missing-magicq

touch "$complete_file"
chmod 0644 "$complete_file"
systemctl disable wasalight-first-boot.service

printf '\n========================================\n'
printf '  WASALIGHT INSTALLATO CORRETTAMENTE\n'
printf '========================================\n'
echo "Commit: $commit"
echo "Riavvio in modalita' protetta..."
sync
systemctl reboot --no-block
