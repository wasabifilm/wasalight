# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_update() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    install -d -m 0755 /etc/wasalight /usr/local/libexec
    install -d -m 0755 /usr/share/polkit-1/actions
    install -o root -g root -m 0644 "$RELEASE_MANIFEST" \
        /etc/wasalight/release-manifest.ini
    install -o root -g root -m 0755 \
        "$PROJECT_DIR/lib/wasalight-release-manifest.sh" \
        "$PROJECT_DIR/lib/wasalight-operation-lock.sh" \
        /usr/local/libexec/
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 \
        "$DATA_MOUNT/system/update-check"
    install_template /usr/local/sbin/wasalight-update 0755

    install_template /usr/local/libexec/wasalight-update-lib.sh 0755

    install_template /usr/local/libexec/wasalight-update-session 0755

    install_template /usr/local/libexec/wasalight-update-auto-session 0755

    install_template /usr/local/bin/wasalight-update-terminal 0755

    install_template /usr/local/sbin/wasalight-update-schedule 0755

    install_template /usr/local/sbin/wasalight-update-auto 0755

    install_template /usr/local/bin/wasalight-update-check 0755

    install_template /usr/local/sbin/wasalight-update-channel 0755

    if [[ ! -e /etc/wasalight/update-signers ]]; then
        install_template /etc/wasalight/update-signers 0644
    fi
    if mountpoint -q "$DATA_MOUNT" && [[ ! -r $DATA_MOUNT/system/update-channel ]]; then
        printf '%s\n' "$(require_manifest_value "$RELEASE_MANIFEST" Updates DefaultChannel)" \
            >"$DATA_MOUNT/system/update-channel"
        chown root:root "$DATA_MOUNT/system/update-channel"
        chmod 0644 "$DATA_MOUNT/system/update-channel"
    fi

    # pkexec selects these narrowly scoped actions from their executable-path
    # annotations and delegates the password prompt to the graphical agent.
    install_template /usr/share/polkit-1/actions/com.wasalight.updates.policy 0644

    if [[ ${WASALIGHT_UPDATE_TRANSACTION:-0} != 1 ]] && \
       mountpoint -q "$DATA_MOUNT" && [[ ! -d $UPDATE_CHECKOUT/.git ]] && \
       [[ -d $PROJECT_DIR/.git ]]; then
        if [[ $PROJECT_COMMIT =~ ^[0-9a-f]{40}$ && \
              -z $(git -C "$PROJECT_DIR" status --porcelain) ]]; then
            log "initializing the persistent Wasalight checkout from the verified installer source"
            rm -rf -- "$UPDATE_CHECKOUT"
            git clone --quiet --no-hardlinks "$PROJECT_DIR" "$UPDATE_CHECKOUT"
            git -C "$UPDATE_CHECKOUT" checkout --quiet --detach "$PROJECT_COMMIT"
            chown -R root:root "$UPDATE_CHECKOUT"
        else
            warn "installer source has local changes; persistent update checkout not initialized"
        fi
    fi
}
