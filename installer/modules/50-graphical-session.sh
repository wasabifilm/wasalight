# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

configure_graphical_session() {
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
    local companion_dock_item=
    local companion_icon
    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0755 \
        "$TARGET_HOME/.config/wasalight/dock"
    install_template /usr/local/bin/wasalight-dialog 0755
    install_template /usr/local/libexec/wasalight-session-language 0644

    install_template /etc/X11/Xwrapper.config 0644

    write_file "$TARGET_HOME/.xinitrc" 0755 <<'EOF'
#!/bin/sh
. /usr/local/libexec/wasalight-session-language
exec dbus-run-session -- openbox-session
EOF

    # Start from Ubuntu's complete Openbox configuration, changing only the
    # appliance theme and title-button layout. NLC keeps a large close target
    # and removes tiny minimise/maximise controls that are awkward on touch.
    install -m 0644 /etc/xdg/openbox/rc.xml "$TARGET_HOME/.config/openbox/rc.xml"
    sed -i \
        -e '0,/<name>.*<\/name>/s//<name>Wasalight<\/name>/' \
        -e 's#<titleLayout>.*</titleLayout>#<titleLayout>NLC</titleLayout>#' \
        -e '/<font place="ActiveWindow">/,/<\/font>/s#<size>.*</size>#<size>16</size>#' \
        -e '/<font place="InactiveWindow">/,/<\/font>/s#<size>.*</size>#<size>16</size>#' \
        "$TARGET_HOME/.config/openbox/rc.xml"
    grep -A8 '<font place="ActiveWindow">' "$TARGET_HOME/.config/openbox/rc.xml" | \
        grep -q '<size>16</size>' || die "Openbox active title font was not configured"
    grep -A8 '<font place="InactiveWindow">' "$TARGET_HOME/.config/openbox/rc.xml" | \
        grep -q '<size>16</size>' || die "Openbox inactive title font was not configured"
    grep -q '</applications>' "$TARGET_HOME/.config/openbox/rc.xml" || \
        die "Openbox applications section is unavailable"
    sed -i '/<\/applications>/i\
    <application name="zenity" class="zenity">\
      <position force="yes">\
        <x>center</x>\
        <y>center</y>\
      </position>\
      <focus>yes</focus>\
      <layer>above</layer>\
      <decor>yes</decor>\
    </application>' "$TARGET_HOME/.config/openbox/rc.xml"

    install -d -m 0755 /usr/share/themes/Wasalight/openbox-3
    install_template /usr/share/themes/Wasalight/openbox-3/themerc 0644
    install_template /usr/share/themes/Wasalight/openbox-3/close.xbm 0644
    local close_state
    for close_state in close_hover close_pressed close_disabled; do
        install -m 0644 \
            /usr/share/themes/Wasalight/openbox-3/close.xbm \
            "/usr/share/themes/Wasalight/openbox-3/${close_state}.xbm"
    done

    install_template /usr/local/bin/wasalight-desktop-wallpaper 0755

    write_file "$TARGET_HOME/.config/pcmanfm/default/desktop-items-0.conf" 0644 <<EOF
[*]
wallpaper=$TARGET_HOME/.cache/wasalight/desktop-wallpaper.png
wallpaper_mode=stretch
wallpaper_common=1
wallpapers_configured=1
desktop_bg=#080b10
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 12
desktop_icon_size=64
show_wm_menu=1
sort=name;ascending;
show_documents=0
show_trash=0
show_mounts=0
EOF

    # Keep GTK text predictable across displays without forcing a monitor DPI.
    # Touch targets remain large and are controlled independently by CSS.
    write_file "$TARGET_HOME/.config/gtk-3.0/settings.ini" 0644 <<'EOF'
[Settings]
gtk-font-name=Sans 10
EOF

    write_file "$TARGET_HOME/.config/libfm/libfm.conf" 0644 <<'EOF'
[config]
single_click=1
quick_exec=1
auto_selection_delay=600
use_trash=1
confirm_del=1
thumbnail_local=1
EOF

    install -d -m 0755 /usr/local/share/icons/wasalight
    install_template /usr/local/share/icons/wasalight/network.svg 0644
    install_template /usr/local/share/icons/wasalight/ip-scanner.svg 0644
    install_template /usr/local/share/icons/wasalight/artnet-monitor.svg 0644
    install_template /usr/local/share/icons/wasalight/companion.svg 0644
    install_template /usr/local/share/icons/wasalight/companion-web.svg 0644
    install_template /usr/local/share/icons/wasalight/files.svg 0644
    install_template /usr/local/share/icons/wasalight/terminal.svg 0644
    install_template /usr/local/share/icons/wasalight/power.svg 0644
    install_template /usr/local/share/icons/wasalight/reboot.svg 0644
    install_template /usr/local/share/icons/wasalight/hub.svg 0644
    install_template /usr/local/share/icons/wasalight/vnc.svg 0644
    install_template /usr/local/share/icons/wasalight/ssh.svg 0644
    install_template /usr/local/share/icons/wasalight/keyboard.svg 0644
    install_template /usr/local/share/icons/wasalight/system-monitor.svg 0644

    write_file "$TARGET_HOME/.config/wasalight/dock/Wasalight-Control.desktop" 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Wasalight Control
Comment=Gestione unificata di MagicQ, servizi, plugin e strumenti
Exec=/usr/local/bin/wasalight-control
Icon=/usr/local/share/icons/wasalight/hub.svg
Terminal=false
StartupNotify=false
EOF

    write_file "$TARGET_HOME/.config/wasalight/dock/Files.desktop" 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=File
Comment=Apre dati persistenti e chiavette USB
Exec=pcmanfm /data
Icon=/usr/local/share/icons/wasalight/files.svg
Terminal=false
StartupNotify=true
EOF

    if [[ -d /opt/companion && -x /usr/local/bin/wasalight-companion-browser ]]; then
        companion_icon=/usr/local/share/icons/wasalight/companion-official.png
        [[ -s $companion_icon ]] || \
            companion_icon=/usr/local/share/icons/wasalight/companion.svg
        write_file "$TARGET_HOME/.config/wasalight/dock/Companion.desktop" 0644 <<EOF
[Desktop Entry]
Type=Application
Name=Companion
Comment=Apre l'interfaccia locale Bitfocus Companion
Exec=/usr/local/bin/wasalight-companion-browser
Icon=$companion_icon
Terminal=false
StartupNotify=true
StartupWMClass=WasalightCompanion
EOF
        companion_dock_item="launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Companion.desktop"
    else
        rm -f "$TARGET_HOME/.config/wasalight/dock/Companion.desktop"
    fi

    # The keyboard has a dedicated right-side tint2 button next to the tray.
    # Remove the old launcher when this module is reapplied to an installation.
    rm -f "$TARGET_HOME/.config/wasalight/dock/Keyboard.desktop"

    install_template /usr/local/share/wasalight/desktop/MagicQ.desktop 0644
    install_template /usr/local/share/wasalight/desktop/Install-MagicQ.desktop 0644
    install_template /usr/local/share/icons/wasalight/magicq-install.svg 0644
    install_template /usr/local/bin/wasalight-magicq-desktop-action 0755
    install_template /usr/local/sbin/wasalight-magicq-desktop-refresh 0755
    /usr/local/sbin/wasalight-magicq-desktop-refresh

    # Keep the touch desktop and tint2 dock as separate, authoritative layouts.
    # File Manager and Control belong only to the dock.
    rm -f "$TARGET_HOME/Desktop/Files.desktop" \
        "$TARGET_HOME/Desktop/Wasalight-Hub.desktop" \
        "$TARGET_HOME/Desktop/Wasalight-Control.desktop"

    write_file "$TARGET_HOME/Desktop/Power-Off.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Spegni
Comment=Spegne la postazione dopo una conferma
Exec=/usr/local/bin/wasalight-power poweroff
Icon=/usr/local/share/icons/wasalight/power.svg
Terminal=false
StartupNotify=false
EOF

    write_file "$TARGET_HOME/Desktop/Reboot.desktop" 0755 <<'EOF'
[Desktop Entry]
Type=Application
Name=Riavvia
Comment=Riavvia la postazione dopo una conferma
Exec=/usr/local/bin/wasalight-power reboot
Icon=/usr/local/share/icons/wasalight/reboot.svg
Terminal=false
StartupNotify=false
EOF

    install_template /usr/local/bin/magicq-fullscreen-watch 0755

    install_template /usr/local/bin/wasalight-audio-test 0755

    install_template /usr/local/bin/wasalight-power 0755

    install_template /usr/local/sbin/wasalight-power-control 0755

    install_template /usr/local/bin/wasalight-desktop-status 0755

    install_template /usr/local/bin/wasalight-keyboard-toggle 0755

    install -d -o "$TARGET_USER" -g "$TARGET_USER" -m 0750 "$TARGET_HOME/.config/picom"
    write_file "$TARGET_HOME/.config/picom/wasalight.conf" 0644 <<'EOF'
# Minimal compositor for Conky transparency. Fullscreen applications such as
# MagicQ are unredirected to avoid compositing latency during a show.
backend = "xrender";
vsync = false;
shadow = false;
fading = false;
active-opacity = 1.0;
inactive-opacity = 1.0;
frame-opacity = 1.0;
detect-client-opacity = true;
unredir-if-possible = true;
use-damage = true;
log-level = "warn";
EOF

    write_file "$TARGET_HOME/.config/conky/wasalight.conf" 0644 <<'EOF'
conky.config = {
    alignment = 'top_right',
    background = true,
    double_buffer = true,
    update_interval = 2,
    gap_x = 24,
    gap_y = 24,
    minimum_width = 460,
    maximum_width = 520,
    use_xft = true,
    font = 'Sans:size=12',
    default_color = 'white',
    own_window = true,
    own_window_type = 'normal',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_transparent = false,
    own_window_argb_visual = true,
    own_window_argb_value = 165,
    own_window_colour = '#161b22',
    border_inner_margin = 16,
    draw_borders = false,
    draw_outline = false,
    draw_shades = false,
};

conky.text = [[
${font Sans:bold:size=22}${color #58a6ff}WASALIGHT${color white}${font}
${font Sans:size=11}Michele Moser · Wasabi Lightbulbfarm${font}
${color #30363d}${hr 2}${color white}
${execpi 2 /usr/local/bin/wasalight-desktop-status}
]];
EOF

    install_template /usr/local/bin/wasalight-terminal-tool 0755

    install_template /usr/local/sbin/wasalight-ip-scan 0755

    install_template /usr/local/libexec/wasalight-ip-scanner.py 0755

    install_template /usr/local/bin/wasalight-ip-scanner 0755

    install_template /usr/local/sbin/wasalight-artnet-capture 0755

    install_template /usr/local/libexec/wasalight-artnet-monitor.py 0755

    install_template /usr/local/bin/wasalight-artnet-monitor 0755

    install -d -m 0755 /etc/wasalight/apps.d
    install_template /etc/wasalight/apps.d/network.desktop 0644
    install_template /etc/wasalight/apps.d/display.desktop 0644
    install_template /etc/wasalight/apps.d/touch.desktop 0644
    install_template /etc/wasalight/apps.d/audio.desktop 0644
    install_template /etc/wasalight/apps.d/files.desktop 0644
    install_template /etc/wasalight/apps.d/ip-scanner.desktop 0644
    install_template /etc/wasalight/apps.d/artnet-monitor.desktop 0644
    install_template /etc/wasalight/apps.d/system-monitor.desktop 0644
    install_template /etc/wasalight/apps.d/terminal.desktop 0644
    install_template /etc/wasalight/apps.d/status.desktop 0644
    # The keyboard already has a permanent tint2 toggle. SSH and VNC belong to
    # Services. Remove stale registrations so Control never shows duplicates,
    # including copies left in the persistent third-party registry.
    rm -f /etc/wasalight/apps.d/keyboard.desktop \
        /etc/wasalight/apps.d/vnc.desktop \
        /etc/wasalight/apps.d/ssh.desktop \
        /data/system/apps.d/keyboard.desktop
    install_template /etc/wasalight/apps.d/update.desktop 0644

    install_template /usr/local/sbin/wasalight-app-register 0755

    write_file "$TARGET_HOME/.config/tint2/tint2rc" 0644 <<EOF
# Wasalight touch panel: always visible, with a discreet near-black theme.
rounded = 0
border_width = 0
background_color = #080b10 98
border_color = #080b10 100

rounded = 8
border_width = 1
background_color = #20252d 100
border_color = #3d444d 100

panel_items = LTSPC
panel_size = 100% 64
panel_margin = 0 0
panel_padding = 10 6 10
panel_background_id = 1
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_dock = 0
wm_menu = 0
strut_policy = follow_size
autohide = 0

launcher_padding = 8 4 8
launcher_background_id = 2
launcher_icon_background_id = 0
launcher_icon_size = 46
launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Wasalight-Control.desktop
launcher_item_app = $TARGET_HOME/.config/wasalight/dock/Files.desktop
$companion_dock_item

taskbar_mode = single_desktop
taskbar_padding = 4 0 4
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_if_empty = 0
taskbar_distribute_size = 0

task_icon = 1
task_text = 0
task_centered = 1
task_maximum_size = 64 52
task_padding = 10 4 10
task_font = Sans 11
task_font_color = #ffffff 100
task_active_font_color = #ffffff 100
task_background_id = 0
task_active_background_id = 2

systray_padding = 8 4 8
systray_icon_size = 30
systray_icon_asb = 100 0 0

# Touch keyboard: placed immediately to the right of the network tray.
button = new
button_icon = /usr/local/share/icons/wasalight/keyboard.svg
button_text =
button_lclick_command = /usr/local/bin/wasalight-keyboard-toggle
button_rclick_command =
button_mclick_command =
button_uwheel_command =
button_dwheel_command =
button_font = Sans 11
button_font_color = #ffffff 100
button_padding = 10 4 10
button_background_id = 0
button_centered = 1
button_max_icon_size = 36

time1_format = %H:%M
time1_font = Sans Bold 12
clock_font_color = #ffffff 100
clock_padding = 12 0
clock_background_id = 0

mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = none
mouse_scroll_down = none
EOF

    install_template /usr/local/sbin/wasalight-companion-launcher 0755

    install_template /usr/local/sbin/magicq-root-launcher 0755

    install_template /usr/local/sbin/magicq-root-stop 0755

    install_template /usr/local/bin/magicq-session 0755

    install_template /usr/local/bin/magicq-start 0755

    install_template /usr/local/bin/magicq-stop 0755

    write_file "$TARGET_HOME/.config/openbox/autostart" 0755 <<'EOF'
#!/bin/sh
xset s off
xset s noblank
xset -dpms
wmctrl -n 1
/usr/local/bin/wasalight-desktop-wallpaper || \
    logger -t wasalight-desktop "desktop wallpaper generation failed"
pcmanfm --desktop --profile=default &
picom --config "$HOME/.config/picom/wasalight.conf" --daemon
conky --config="$HOME/.config/conky/wasalight.conf" --daemonize --pause=2
tint2 -c "$HOME/.config/tint2/tint2rc" &
nm-applet --indicator &
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
/usr/local/bin/wasalight-touch-watch &
/usr/local/bin/magicq-fullscreen-watch &
/usr/local/bin/wasalight-remote-autostart &
/usr/local/bin/wasalight-magicq-usb-watch &
( sleep 8; /usr/local/bin/wasalight-first-run ) &
( sleep 15; /usr/local/bin/wasalight-update-check ) &
magicq_auto=enabled
[[ ! -r /data/system/service-flags/magicq-autostart ]] || \
    magicq_auto=$(cat /data/system/service-flags/magicq-autostart)
if findmnt -n -o FSTYPE / 2>/dev/null | grep -qx overlay && \
   [ "$magicq_auto" = enabled ]; then
    /usr/local/bin/magicq-session &
elif findmnt -n -o FSTYPE / 2>/dev/null | grep -qx overlay; then
    logger -t magicq-session "SHOW mode: automatic MagicQ start disabled by operator"
else
    logger -t magicq-session "MAINTENANCE mode: automatic MagicQ start skipped"
fi
EOF

    write_file "$TARGET_HOME/.config/openbox/menu.xml" 0644 <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Wasalight">
    <item label="Wasalight Control"><action name="Execute"><command>/usr/local/bin/wasalight-control</command></action></item>
    <item label="File"><action name="Execute"><command>pcmanfm /data</command></action></item>
    <item label="Terminal"><action name="Execute"><command>lxterminal</command></action></item>
    <item label="Aggiorna Wasalight"><action name="Execute"><command>/usr/local/bin/wasalight-update-terminal</command></action></item>
    <separator />
    <item label="Riavvia"><action name="Execute"><command>/usr/local/bin/wasalight-power reboot</command></action></item>
    <item label="Spegni"><action name="Execute"><command>/usr/local/bin/wasalight-power poweroff</command></action></item>
  </menu>
</openbox_menu>
EOF

    write_file "$TARGET_HOME/.config/pcmanfm/default/pcmanfm.conf" 0644 <<'EOF'
[volume]
mount_on_startup=0
mount_removable=0
autorun=0
EOF

    install -d -m 0755 /etc/polkit-1/rules.d
    install_template /etc/polkit-1/rules.d/49-chamsys-network.rules 0644

    chown -R "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.config" "$TARGET_HOME/.xinitrc"
    # LibFM recognises readable application/x-desktop files without an execute
    # bit. Keeping the root-owned launchers at 0444 prevents its fast MIME pass
    # from misclassifying them as generic executables, so their SVGs are used.
    chown -R root:root "$TARGET_HOME/Desktop"
    chmod 0755 "$TARGET_HOME/Desktop"
    find "$TARGET_HOME/Desktop" -maxdepth 1 -type f -name '*.desktop' \
        -exec chmod 0444 {} +

    install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
    write_file /etc/systemd/system/getty@tty1.service.d/autologin.conf 0644 <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear --noissue %I \$TERM
Type=idle
EOF
    systemctl set-default multi-user.target
}
