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

    install_template /usr/local/bin/wasalight-update-terminal 0755

    install_template /usr/local/bin/wasalight-update-check 0755

    # pkexec selects these narrowly scoped actions from their executable-path
    # annotations and delegates the password prompt to the graphical agent.
    install_template /usr/share/polkit-1/actions/com.wasalight.updates.policy 0644

    if mountpoint -q "$DATA_MOUNT" && [[ ! -d $UPDATE_CHECKOUT/.git ]]; then
        log "initializing the persistent Wasalight update checkout"
        /usr/local/sbin/wasalight-update --code-only || \
            warn "persistent update checkout could not be initialized; retry later with sudo wasalight-update --code-only"
    fi
}
