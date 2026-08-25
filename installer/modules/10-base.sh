# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_data_mount() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    install -d -m 0755 "$DATA_MOUNT"

    if [[ -n "$DATA_DEVICE" ]]; then
        if [[ "$DATA_DEVICE" == UUID=* || "$DATA_DEVICE" == LABEL=* ]]; then
            local resolved
            resolved=$(findfs "$DATA_DEVICE" 2>/dev/null || true)
            [[ -b "$resolved" ]] || die "cannot resolve data filesystem: $DATA_DEVICE"
        else
            [[ -b "$DATA_DEVICE" ]] || die "data device is not a block device: $DATA_DEVICE"
            DATA_DEVICE=$(readlink -f -- "$DATA_DEVICE")
        fi
        ensure_fstab_line "MagicQ persistent data" \
            "$DATA_DEVICE $DATA_MOUNT ext4 rw,noatime,nosuid,nodev 0 2"
        mountpoint -q "$DATA_MOUNT" || mount "$DATA_MOUNT"
    fi

    if mountpoint -q "$DATA_MOUNT"; then
        local data_fs data_source root_source
        data_fs=$(findmnt -n -o FSTYPE -M "$DATA_MOUNT")
        data_source=$(findmnt -n -o SOURCE -M "$DATA_MOUNT")
        root_source=$(findmnt -n -o SOURCE -M /)
        [[ "$data_fs" == ext4 ]] || die "/data must be ext4; found $data_fs"
        [[ "$data_source" != "$root_source" ]] || die "/data must be a separate filesystem"
    elif ((ENABLE_PROTECTION)); then
        die "protected mode requires a separate ext4 filesystem mounted at /data"
    else
        warn "/data is not a separate mount; persistent bindings and SHOW protection are skipped"
        return
    fi

    install -d -m 0750 "$DATA_MOUNT/magicq/Documents/MagicQ"
    install -d -m 0750 "$DATA_MOUNT/magicq/.local/share"
    install -d -m 0700 "$DATA_MOUNT/magicq/root-home/.config"
    install -d -m 0700 "$DATA_MOUNT/magicq/root-home/.local/share"
    install -d -m 0700 "$DATA_MOUNT/system/network"
    install -d -m 0755 "$DATA_MOUNT/system/apps.d"
    install -d -m 0750 "$DATA_MOUNT/log"
}

magicq_deb_version_of() {
    local source=$1 version
    dpkg-deb --info "$source" >/dev/null 2>&1 || return 1
    [[ $(dpkg-deb -f "$source" Package 2>/dev/null) == "$MAGICQ_PACKAGE_NAME" ]] || return 1
    [[ $(dpkg-deb -f "$source" Architecture 2>/dev/null) == "$MAGICQ_ARCHITECTURE" ]] || return 1
    version=$(dpkg-deb -f "$source" Version 2>/dev/null) || return 1
    dpkg --validate-version "$version" >/dev/null 2>&1 || return 1
    printf '%s\n' "$version"
}

consider_bootstrap_magicq_package() {
    local source=$1 version staging
    version=$(magicq_deb_version_of "$source") || {
        warn "ignoring a USB .deb that is not valid MagicQ amd64: $source"
        return 0
    }

    staging="$PACKAGE_STORE/.wasalight-usb-candidate.$$"
    if [[ -z $BOOTSTRAP_MAGICQ_PATH ]] || \
       dpkg --compare-versions "$version" gt "$BOOTSTRAP_MAGICQ_VERSION"; then
        install -o root -g root -m 0640 "$source" "$staging"
        cmp -s -- "$source" "$staging" || \
            die "USB MagicQ package copy verification failed: $source"
        BOOTSTRAP_MAGICQ_PATH=$staging
        BOOTSTRAP_MAGICQ_VERSION=$version
    elif dpkg --compare-versions "$version" eq "$BOOTSTRAP_MAGICQ_VERSION" && \
         ! cmp -s -- "$source" "$BOOTSTRAP_MAGICQ_PATH"; then
        die "conflicting USB packages declare MagicQ version $version"
    fi
}

scan_bootstrap_magicq_directory() {
    local root=$1 candidate
    while IFS= read -r -d '' candidate; do
        consider_bootstrap_magicq_package "$candidate"
    done < <(find "$root" -maxdepth 1 -type f -iname '*.deb' -print0 2>/dev/null)
    if [[ -d $root/packages ]]; then
        while IFS= read -r -d '' candidate; do
            consider_bootstrap_magicq_package "$candidate"
        done < <(find "$root/packages" -maxdepth 1 -type f -iname '*.deb' -print0 2>/dev/null)
    fi
}

discover_magicq_from_usb() {
    [[ -z $DEB_PATH ]] || return 0
    mountpoint -q "$DATA_MOUNT" || {
        warn "automatic initial USB discovery requires the persistent /data mount"
        return 0
    }

    local device device_type filesystem properties parent_device mount_dir target
    local existing_same_version= stored stored_version destination
    install -d -o root -g root -m 0750 "$PACKAGE_STORE"
    install -d -m 0700 /run/wasalight-usb-scan

    # The script-wide IFS deliberately excludes spaces, while lsblk separates
    # these columns with whitespace. Restore it locally so type and filesystem
    # do not remain empty and make every USB device get skipped.
    while IFS=$' \t' read -r device device_type filesystem; do
        [[ $device_type == part || $device_type == disk ]] || continue
        [[ -n $filesystem ]] || continue
        properties=$(udevadm info --query=property --name="$device" 2>/dev/null || true)
        if ! grep -qx 'ID_BUS=usb' <<<"$properties"; then
            parent_device=$(lsblk -dnro PKNAME "$device" 2>/dev/null | head -n1)
            [[ -n $parent_device ]] || continue
            properties=$(udevadm info --query=property --name="/dev/$parent_device" \
                2>/dev/null || true)
            grep -qx 'ID_BUS=usb' <<<"$properties" || continue
        fi

        # findmnt returns 1 when the device is not mounted. That is the normal
        # bootstrap case, not an installer error: keep going so the device can
        # be mounted temporarily below /run/wasalight-usb-scan.
        target=$(findmnt -rn -S "$device" -o TARGET 2>/dev/null | head -n1 || true)
        if [[ -n $target ]]; then
            case $target in
                /|/boot|/boot/efi|/data) continue ;;
            esac
            log "scanning mounted USB for MagicQ: $target"
            scan_bootstrap_magicq_directory "$target"
            continue
        fi

        case $filesystem in
            vfat|exfat|ntfs|ntfs3|ext4) ;;
            *) warn "skipping unsupported initial USB filesystem $filesystem on $device"; continue ;;
        esac
        mount_dir="/run/wasalight-usb-scan/${device##*/}"
        install -d -m 0700 "$mount_dir"
        if mount -o ro,nosuid,nodev,noexec "$device" "$mount_dir"; then
            BOOTSTRAP_TEMP_MOUNTS+=("$mount_dir")
            log "temporarily mounted $device read-only to search for MagicQ"
            scan_bootstrap_magicq_directory "$mount_dir"
            umount "$mount_dir"
            rmdir "$mount_dir" 2>/dev/null || true
        else
            warn "could not mount initial USB $device ($filesystem); FAT32 is recommended"
        fi
    done < <(lsblk -rpno NAME,TYPE,FSTYPE 2>/dev/null)

    [[ -n $BOOTSTRAP_MAGICQ_PATH ]] || return 0

    while IFS= read -r -d '' stored; do
        [[ $stored == "$BOOTSTRAP_MAGICQ_PATH" ]] && continue
        stored_version=$(magicq_deb_version_of "$stored") || continue
        if dpkg --compare-versions "$stored_version" eq "$BOOTSTRAP_MAGICQ_VERSION"; then
            cmp -s -- "$stored" "$BOOTSTRAP_MAGICQ_PATH" || \
                die "persistent MagicQ $stored_version differs from the USB package"
            existing_same_version=$stored
            break
        fi
    done < <(find "$PACKAGE_STORE" -maxdepth 1 -type f -name '*.deb' -print0)

    if [[ -n $existing_same_version ]]; then
        rm -f -- "$BOOTSTRAP_MAGICQ_PATH"
        DEB_PATH=$existing_same_version
    else
        destination="$PACKAGE_STORE/magicq_${BOOTSTRAP_MAGICQ_VERSION}_amd64.deb"
        mv -f -- "$BOOTSTRAP_MAGICQ_PATH" "$destination"
        chmod 0640 "$destination"
        DEB_PATH=$destination
        log "MagicQ $BOOTSTRAP_MAGICQ_VERSION imported from USB into $destination"
    fi
}

require_magicq_or_override() {
    [[ -z $DEB_PATH ]] && ! is_installed magicq || return 0
    ((ALLOW_MISSING_MAGICQ == 0)) || return 0

    if [[ -t 0 && -t 1 && ${WASALIGHT_UPDATE_TRANSACTION:-0} != 1 ]]; then
        local choice
        while :; do
            cat <<'EOF'

MagicQ is not installed and no valid package was found.

  1) Install MagicQ from USB
     Insert the USB drive with the .deb in its root or packages/, then press 1.
  2) Continue without MagicQ
     The Install MagicQ button will remain on the desktop for offline setup.
  3) Stop the installation
EOF
            read -r -p "Scelta [1-3]: " choice
            case $choice in
                1)
                    discover_magicq_from_usb
                    persist_magicq_package
                    [[ -n $DEB_PATH ]] && return 0
                    warn "no valid MagicQ amd64 package was found; check the USB drive"
                    ;;
                2)
                    ALLOW_MISSING_MAGICQ=1
                    log "continuing without MagicQ at the operator's request"
                    return 0
                    ;;
                3) die "installation cancelled by the operator" ;;
                *) warn "choose 1, 2 or 3" ;;
            esac
        done
    fi

    die "MagicQ is not installed and no valid .deb was found locally or on USB.
To continue intentionally without MagicQ, add: --allow-missing-magicq
Example: sudo ./install.sh --allow-missing-magicq [other options]"
}

persist_magicq_package() {
    [[ -n $DEB_PATH ]] || return 0
    mountpoint -q "$DATA_MOUNT" || {
        warn "MagicQ package cannot be persisted because /data is unavailable"
        return 0
    }

    local source destination
    source=$DEB_PATH
    install -d -o root -g root -m 0750 "$PACKAGE_STORE"
    destination="$PACKAGE_STORE/${source##*/}"

    if [[ $(readlink -f -- "$source") != $(readlink -m -- "$destination") ]]; then
        if [[ -e $destination ]] && ! cmp -s -- "$source" "$destination"; then
            die "a different persistent MagicQ package already uses this name: $destination"
        fi
        if [[ ! -e $destination ]]; then
            install -o root -g root -m 0640 "$source" "$destination"
            cmp -s -- "$source" "$destination" || \
                die "persistent MagicQ package verification failed: $destination"
            log "MagicQ package persisted in $destination"
        fi

    fi
    DEB_PATH=$destination
}

configure_time_synchronization() {
    local chrony_config=/etc/chrony/chrony.conf

    # Ubuntu's default permits clock steps only during the first three Chrony
    # updates. Appliances and virtual machines can resume with a large offset
    # much later, leaving APT unable to validate repository metadata for hours.
    if grep -Eq '^[[:space:]]*makestep[[:space:]]+' "$chrony_config"; then
        sed -Ei \
            's/^[[:space:]]*makestep[[:space:]].*/makestep 1.0 -1/' \
            "$chrony_config"
    else
        printf '\nmakestep 1.0 -1\n' >>"$chrony_config"
    fi

    systemctl enable chrony.service
    systemctl restart chrony.service
    chronyc -a online >/dev/null 2>&1 || true
    chronyc -a makestep >/dev/null 2>&1 || \
        warn "Chrony could not step the clock immediately; it will retry automatically"
}

install_packages() {
    # Prevent background APT jobs from competing for dpkg while the installer
    # owns package management. PackageKit is deliberately masked only after all
    # APT operations because masking it earlier produces a misleading warning.
    disable_service_if_present \
        apt-daily.timer apt-daily-upgrade.timer apt-daily.service \
        apt-daily-upgrade.service unattended-upgrades.service

    local packages=() package package_file package_output
    local -A seen_packages=()
    local package_files=("$RUNTIME_PACKAGES_FILE" "$MAGICQ_RUNTIME_PACKAGES_FILE")
    if ((ENABLE_COMPANION)) || [[ -d /opt/companion ]]; then
        package_files+=("$COMPANION_RUNTIME_PACKAGES_FILE")
    fi
    for package_file in "${package_files[@]}"; do
        package_output=$(wasalight_runtime_packages "$package_file") || \
            die "required package list is invalid: $package_file"
        while IFS= read -r package; do
            [[ ${seen_packages[$package]+present} ]] || packages+=("$package")
            seen_packages["$package"]=1
        done <<<"$package_output"
    done
    ((${#packages[@]})) || die "runtime package list is empty or invalid"

    # Most Wasalight releases only replace configuration or UI files. Avoid a
    # network metadata refresh when every package required by the selected
    # feature set is already correctly installed.
    local missing_packages=()
    for package in "${packages[@]}"; do
        is_installed "$package" || missing_packages+=("$package")
    done

    if ((${#missing_packages[@]})); then
        log "refreshing package metadata for ${#missing_packages[@]} missing packages"
        apt-get update

        # Openbox, libinput-tools, lxrandr and other appliance components are
        # in Ubuntu's official Universe component. Standard Server installs
        # normally enable it; minimal/custom images may not.
        if ! apt-cache show openbox >/dev/null 2>&1; then
            log "enabling the official Ubuntu Universe component"
            apt_install software-properties-common
            add-apt-repository -y universe
            apt-get update
        fi
        apt_install "${missing_packages[@]}"
    else
        log "all required packages are installed; skipping apt metadata refresh"
    fi

    # The operator can select either supported language for the graphical
    # session without changing Ubuntu's global locale.
    locale-gen en_US.UTF-8 it_IT.UTF-8

    systemctl enable NetworkManager.service
    configure_time_synchronization
    # SSH reboot persistence is deliberately stored on /data instead of in
    # systemd's root-filesystem state, which is volatile in protected mode.
    systemctl disable ssh.service 2>/dev/null || true
}

configure_networkmanager() {
    # Ubuntu Server's installer normally leaves Netplan on systemd-networkd.
    # In that state network clients open but list no usable devices.
    # A late Netplan file changes only the renderer, preserving the interface,
    # DHCP, static address, route and DNS definitions created during install.
    install_template /etc/netplan/99-wasalight-networkmanager.yaml 0600

    netplan generate
    systemctl enable NetworkManager.service
    netplan apply
    systemctl restart NetworkManager.service

    # The Server installer may leave networkd and its wait-online unit enabled.
    # Once Netplan is rendered by NetworkManager they have no interface to
    # configure; wait-online can then time out and leave a misleading failed
    # unit on every boot. Keep NetworkManager as the single network owner.
    disable_service_if_present \
        systemd-networkd-wait-online.service systemd-networkd.service
    systemctl reset-failed systemd-networkd-wait-online.service 2>/dev/null || true

    if nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | \
       grep -E '^[^:]+:(ethernet|wifi):unmanaged$' >/dev/null; then
        warn "a physical network interface is still unmanaged after applying Netplan"
    fi
}
