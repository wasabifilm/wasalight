configure_plugins() {
    local plugin source manifest state_file requested
    install -d -m 0755 /usr/lib/wasalight/plugins
    install -d -m 0755 /usr/local/libexec
    install -d -o root -g root -m 0755 "$DATA_MOUNT/system/plugins-state"
    install -d -o root -g root -m 0755 "$DATA_MOUNT/plugins"
    install -d -o root -g adm -m 0755 "$DATA_MOUNT/log/plugins"

    for plugin in ssh vnc companion; do
        source="$PROJECT_DIR/plugins/$plugin/manifest.ini"
        [[ -s $source ]] || die "Wasalight plugin manifest is missing: $source"
        install -D -o root -g root -m 0644 "$source" \
            "/usr/lib/wasalight/plugins/$plugin/manifest.ini"
    done
    install -o root -g root -m 0755 "$PROJECT_DIR/libexec/wasalight-plugin" \
        /usr/local/bin/wasalight-plugin
    install -o root -g root -m 0755 "$PROJECT_DIR/libexec/wasalight-plugin-admin" \
        /usr/local/sbin/wasalight-plugin-admin
    install -o root -g root -m 0755 "$PROJECT_DIR/ui/wasalight-control-center.py" \
        /usr/local/libexec/wasalight-control-center.py

    # Built-in management integrations are visible by default. Companion is
    # enabled on its first installation, while an explicit disabled state from
    # an operator is always preserved by later updates.
    for plugin in ssh vnc; do
        state_file="$DATA_MOUNT/system/plugins-state/$plugin"
        printf 'enabled\n' >"$state_file"
    done
    state_file="$DATA_MOUNT/system/plugins-state/companion"
    if [[ -d /opt/companion && ! -e $state_file ]]; then
        printf 'enabled\n' >"$state_file"
    fi
    ((ENABLE_COMPANION)) && printf 'enabled\n' >"$state_file"
    for requested in "${REQUESTED_PLUGINS[@]-}"; do
        [[ -n $requested ]] || continue
        printf 'enabled\n' >"$DATA_MOUNT/system/plugins-state/$requested"
    done
    chmod 0644 "$DATA_MOUNT/system/plugins-state"/* 2>/dev/null || true
    if [[ -d /opt/companion ]]; then
        if [[ $(<"$DATA_MOUNT/system/plugins-state/companion") == enabled ]]; then
            systemctl enable --now companion.service
        else
            systemctl disable --now companion.service
        fi
    fi

    install_template /usr/local/bin/wasalight-control 0755

    install_template /etc/sudoers.d/wasalight-plugins 0440
    visudo -cf /etc/sudoers.d/wasalight-plugins >/dev/null
}
