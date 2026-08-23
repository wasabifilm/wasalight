#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Complete the Wasalight appliance setup on the first real Ubuntu boot.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly release_manifest="/etc/wasalight/release-manifest.ini"
readonly manifest_library="/usr/local/libexec/wasalight-release-manifest.sh"
[[ -r $release_manifest ]] || {
    printf 'ERROR: release manifest not found: %s\n' "$release_manifest" >&2
    exit 1
}
[[ -r $manifest_library ]] || {
    printf 'ERROR: release manifest loader not found: %s\n' "$manifest_library" >&2
    exit 1
}
# shellcheck source=../lib/wasalight-release-manifest.sh
. "$manifest_library"
repository=$(require_manifest_value_matching "$release_manifest" Wasalight Repository \
    '^https://[A-Za-z0-9][A-Za-z0-9./_?&=%+~:@-]*$' 'a safe HTTPS URL') || exit 1
branch=$(require_manifest_value_matching "$release_manifest" Wasalight Branch \
    '^[A-Za-z0-9][A-Za-z0-9._/-]*$' 'a Git branch name') || exit 1
readonly repository branch
readonly checkout="/data/system/wasalight"
readonly log_dir="/data/log"
readonly log_file="$log_dir/wasalight-first-boot.log"
readonly status_file="$log_dir/wasalight-first-boot.status"
readonly version_file="$log_dir/wasalight-first-boot.version"
readonly complete_file="/var/lib/wasalight/first-boot-complete"
readonly active_file="/run/wasalight-first-boot-active"

status_ready=0
current_phase="Startup"

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
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local rc=$?
    trap - ERR
    set +e
    write_status failed "Command failed (exit code $rc)"
    printf 'ERROR: automatic installation stopped during phase: %s\n' \
        "$current_phase" >&2
    exit "$rc"
}
trap on_error ERR

download_only=0
case "${1:-}" in
    "") ;;
    --download-only) download_only=1 ;;
    *) die "unknown option: $1" ;;
esac

[[ $EUID -eq 0 ]] || die "the bootstrap must run as root"
if [[ -e $complete_file ]]; then
    echo "Wasalight is already installed: no action is required."
    exit 0
fi
if ((download_only == 0)); then
    touch "$active_file"
    chmod 0644 "$active_file"
fi
mountpoint -q /data || die "/data is not mounted"
[[ $(findmnt -n -o FSTYPE -M /data) == ext4 ]] || die "/data is not ext4"
command -v git >/dev/null 2>&1 || die "Git is not installed"

install -d -o root -g root -m 0755 /data/system /var/lib/wasalight
install -d -o chamsys -g chamsys -m 0750 "$log_dir"
touch "$log_file"
chown root:adm "$log_file" 2>/dev/null || chown root:root "$log_file"
chmod 0640 "$log_file"
exec > >(tee -a "$log_file") 2>&1
status_ready=1
write_status running "Preparing automatic installation"

printf '\n========================================\n'
printf '  WASALIGHT · AUTOMATIC INSTALLATION\n'
printf '========================================\n'
echo "Started: $(date --iso-8601=seconds)"
echo "Repository: $repository"

current_phase="1/4 · Download sources"
write_status running "Checking and updating the Wasalight repository"
echo "[$current_phase]"
if [[ -e $checkout && ! -d $checkout/.git ]]; then
    die "$checkout exists but is not a Git repository"
fi

if [[ -d $checkout/.git ]]; then
    echo "Updating the existing persistent checkout..."
    git -C "$checkout" diff --quiet || die "the checkout contains local changes"
    git -C "$checkout" diff --cached --quiet || die "the Git index contains local changes"
    git -C "$checkout" remote set-url origin "$repository"
    git -C "$checkout" fetch origin "$branch"
    git -C "$checkout" merge --ff-only FETCH_HEAD
else
    temporary_checkout="${checkout}.new.$$"
    cleanup() { rm -rf -- "$temporary_checkout"; }
    trap cleanup EXIT
    echo "Downloading the latest $branch branch..."
    git clone --depth 1 --branch "$branch" --single-branch \
        "$repository" "$temporary_checkout"
    mv "$temporary_checkout" "$checkout"
    trap - EXIT
fi

current_phase="2/4 · Verify sources"
write_status running "Verifying the downloaded project"
echo "[$current_phase]"
echo "Verifying the downloaded project..."
"$checkout/tests/verify-project.sh"
commit=$(git -C "$checkout" rev-parse --verify HEAD)
[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "invalid Git commit: $commit"
printf 'repository=%s\nbranch=%s\ncommit=%s\ndownloaded_at=%s\n' \
    "$repository" "$branch" "$commit" "$(date --iso-8601=seconds)" >"$version_file"
chown root:adm "$version_file" 2>/dev/null || chown root:root "$version_file"
chmod 0640 "$version_file"

if ((download_only)); then
    write_status prepared "Wasalight source verified and ready for first boot"
    echo "Wasalight source verified and prepared for first boot."
    exit 0
fi

current_phase="3/4 · Install Wasalight"
write_status running "Running install.sh"
echo "[$current_phase]"
echo "Installing Wasalight from commit $commit..."
"$checkout/install.sh" --no-protection --allow-missing-magicq
grep -qxF 'overlayroot="disabled"' /etc/overlayroot.local.conf || \
    die "the next boot was not configured for MAINTENANCE mode"

current_phase="4/4 · Finalization"
write_status running "Recording completion and rebooting into MAINTENANCE"
echo "[$current_phase]"
printf '\n========================================\n'
printf '  WASALIGHT INSTALLED SUCCESSFULLY\n'
printf '========================================\n'
echo "Commit: $commit"
echo "Rebooting into MAINTENANCE mode..."
write_status complete "Wasalight installed from commit $commit; rebooting into MAINTENANCE"
systemctl disable wasalight-first-boot.service
touch "$complete_file"
chmod 0644 "$complete_file"
sync
systemctl reboot --no-block
