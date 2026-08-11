#!/usr/bin/env bash
# Complete the Wasalight appliance setup on the first real Ubuntu boot.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly repository="https://github.com/wasabifilm/wasalight.git"
readonly checkout="/data/system/wasalight"
readonly log_dir="/data/log"
readonly log_file="$log_dir/wasalight-first-boot.log"
readonly status_file="$log_dir/wasalight-first-boot.status"
readonly version_file="$log_dir/wasalight-first-boot.version"
readonly complete_file="/var/lib/wasalight/first-boot-complete"

status_ready=0
current_phase="Avvio"

write_status() {
    ((status_ready)) || return 0
    local state=$1 message=$2 temporary="${status_file}.tmp.$$"
    printf 'state=%s\nphase=%s\nmessage=%s\nupdated_at=%s\n' \
        "$state" "$current_phase" "$message" "$(date --iso-8601=seconds)" >"$temporary"
    chown root:adm "$temporary" 2>/dev/null || chown root:root "$temporary"
    chmod 0640 "$temporary"
    mv -f "$temporary" "$status_file"
}

die() {
    write_status failed "$*"
    printf 'ERRORE: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local rc=$?
    trap - ERR
    set +e
    write_status failed "Comando non riuscito (codice $rc)"
    printf 'ERRORE: installazione automatica interrotta nella fase: %s\n' \
        "$current_phase" >&2
    exit "$rc"
}
trap on_error ERR

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
status_ready=1
write_status running "Preparazione dell'installazione automatica"

printf '\n========================================\n'
printf '  WASALIGHT · INSTALLAZIONE AUTOMATICA\n'
printf '========================================\n'
echo "Avvio: $(date --iso-8601=seconds)"
echo "Repository: $repository"

current_phase="1/4 · Download sorgenti"
write_status running "Controllo e aggiornamento del repository Wasalight"
echo "[$current_phase]"
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

current_phase="2/4 · Verifica sorgenti"
write_status running "Verifica del progetto scaricato"
echo "[$current_phase]"
echo "Verifico il progetto scaricato..."
"$checkout/tests/verify-project.sh"
commit=$(git -C "$checkout" rev-parse --verify HEAD)
[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "commit Git non valido: $commit"
printf 'repository=%s\nbranch=main\ncommit=%s\ndownloaded_at=%s\n' \
    "$repository" "$commit" "$(date --iso-8601=seconds)" >"$version_file"
chown root:adm "$version_file" 2>/dev/null || chown root:root "$version_file"
chmod 0640 "$version_file"

if ((download_only)); then
    write_status prepared "Codice Wasalight verificato e pronto per il primo avvio"
    echo "Codice Wasalight verificato e preparato per il primo avvio."
    exit 0
fi

current_phase="3/4 · Installazione Wasalight"
write_status running "Esecuzione di install.sh"
echo "[$current_phase]"
echo "Installo Wasalight dal commit $commit..."
"$checkout/install.sh" --allow-missing-magicq

current_phase="4/4 · Finalizzazione"
write_status running "Registrazione del completamento e riavvio"
echo "[$current_phase]"
printf '\n========================================\n'
printf '  WASALIGHT INSTALLATO CORRETTAMENTE\n'
printf '========================================\n'
echo "Commit: $commit"
echo "Riavvio in modalita' protetta..."
write_status complete "Wasalight installato dal commit $commit; riavvio richiesto"
systemctl disable wasalight-first-boot.service
touch "$complete_file"
chmod 0644 "$complete_file"
sync
systemctl reboot --no-block
