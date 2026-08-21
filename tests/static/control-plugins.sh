# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Controlli statici per Wasalight Control, plugin e Companion.
plugin_command="$PROJECT_DIR/libexec/wasalight-plugin"
plugin_admin="$PROJECT_DIR/libexec/wasalight-plugin-admin"
control_center="$PROJECT_DIR/ui/wasalight-control-center.py"
control_core="$PROJECT_DIR/ui/wasalight_control"
for python_tool in "$plugin_command" "$plugin_admin" "$control_center"; do
    [[ -s $python_tool ]] || fail "componente plugin mancante: $python_tool"
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$python_tool"
done
for python_tool in "$control_core"/*.py; do
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$python_tool"
done
for python_tool in "$control_core/pages"/*.py; do
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$python_tool"
done
grep -Fq '["systemctl", "disable", "--now", unit]' "$plugin_admin" || \
    fail "disabilitare un plugin non ferma il servizio systemd"
grep -Fq '["pkill", "-u", user, "-x", process]' "$plugin_admin" || \
    fail "disabilitare un plugin di sessione non ferma il processo"
grep -Fq 'os.replace(temporary, os.path.join(STATE_ROOT, plugin_id))' "$plugin_admin" || \
    fail "lo stato plugin persistente non viene scritto atomicamente"
grep -Fq 'except subprocess.TimeoutExpired:' "$plugin_command" || \
    fail "lo stato plugin non gestisce servizi lenti senza bloccare Control"
grep -Fq 'plugin_command: str = "/usr/local/bin/wasalight-plugin"' \
    "$control_core/models.py" || fail "Wasalight Control non usa il registro plugin"
grep -Fq 'self.overview_page = OverviewPage(' "$control_center" || \
    fail "Wasalight Control non espone la dashboard unificata"
grep -Fq 'parse_status_report(status, magicq)' "$control_center" || \
    fail "la Panoramica Control non deriva uno stato operativo strutturato"
grep -Fq 'class OverviewSnapshot:' "$control_core/overview_state.py" || \
    fail "la Panoramica Control non ha un modello di stato testabile"
grep -Fq 'Gtk.Expander(label=_("Technical details"))' \
    "$control_core/pages/overview.py" || \
    fail "la Panoramica Control mostra sempre i dettagli tecnici"
grep -Fq '"good": _("Configured"), "error": _("To configure")' \
    "$control_core/pages/overview.py" || \
    fail "la rete Control usa ancora stati tecnici"
grep -Fq 'IP address: {address}' "$control_core/pages/overview.py" || \
    fail "la Panoramica Control non mostra l'indirizzo IP"
grep -Fq 'title.get_style_context().add_class("brand-title")' \
    "$control_core/shell.py" || fail "il titolo di Control non usa il colore tema del marchio"
grep -Fq 'self.set_decorated(False)' "$control_center" || \
    fail "Control mostra ancora la barra titolo nativa duplicata"
if grep -Fq 'mode = Gtk.Label(label=identity.mode)' "$control_core/shell.py"; then
    fail "la modalità è ancora duplicata nell'intestazione Control"
fi
grep -Fq '.navigation-button:checked {' "$control_core/style.py" || \
    fail "la sezione attiva di Control non ha una palette dedicata"
grep -Fq "background: {palette['brand']}; color: {palette['brand_text']};" \
    "$control_core/style.py" || fail "la sezione attiva non usa i token del marchio"
grep -Fq 'min-height: 44px; padding: 8px 12px; font-size: 15px;' \
    "$control_core/style.py" || \
    fail "i font dei pulsanti Control non usano la misura compatta touch"
grep -Fq "size='20000' weight='bold'>Wasalight Control" "$control_core/shell.py" || \
    fail "il titolo Control non usa la misura compatta"
grep -Fq 'desktop_font=Sans 12' "$INSTALLER" || \
    fail "il desktop non usa il font compatto"
grep -Fq 'gtk-font-name=Sans 10' "$INSTALLER" || \
    fail "GTK non usa un font prevedibile tra monitor diversi"
grep -Fq '<size>16</size>' "$INSTALLER" || \
    fail "i titoli Openbox non usano la misura compatta"
grep -Fq 'task_font = Sans 11' "$INSTALLER" || \
    fail "la barra applicazioni non usa il font compatto"
grep -Fq 'stack, scrolledwindow, viewport, flowbox {' \
    "$control_core/style.py" || fail "le pagine Control non impongono il fondo scuro"
grep -Fq 'gi.require_version("Gdk", "3.0")' "$control_core/style.py" || \
    fail "Control non fissa la versione Gdk e genera warning PyGI"
if grep -Fq 'add_with_viewport' "$control_center"; then
    fail "Control usa ancora l'API GTK deprecata add_with_viewport"
fi
grep -Fq 'fill="#76bd22"' "$INSTALLER" || \
    fail "l'icona Wasalight Control non usa il verde Wasabi"
if grep -Fq '#8957e5' "$INSTALLER"; then
    fail "l'icona Wasalight Control usa ancora l'accento viola"
fi
grep -Fq 'mode_label = _("Switch to MAINTENANCE") if identity.mode == "SHOW" else _("Switch to SHOW")' \
    "$control_core/pages/overview.py" || fail "la home Control non mostra il cambio modalità contestuale"
if grep -Fq 'self.summary_state' "$control_core/pages/overview.py"; then
    fail "la home Control duplica ancora la modalità nella stessa scheda"
fi
grep -Fq 'lambda button: run_command(button, [paths.update_terminal])' \
    "$control_core/pages/overview.py" || \
    fail "la scheda Aggiornamenti non avvia direttamente l'updater"
if grep -Fq '("File", ["pcmanfm", "/data"])' "$control_center"; then
    fail "la home Control contiene ancora il pulsante File"
fi
grep -Fq 'self.applications_page = ApplicationsPage(' "$control_center" || \
    fail "Wasalight Control non espone il pannello MagicQ dedicato"
grep -Fq '"/usr/share/pixmaps/magicq.png"' "$control_core/pages/applications.py" || \
    fail "Wasalight Control non usa l'icona originale MagicQ"
grep -Fq 'CARD_WIDTH = 290' "$control_core/widgets.py" || \
    fail "le schede software e servizi di Control non hanno una misura comune"
grep -Fq 'def card_flow()' "$control_core/widgets.py" || \
    fail "MagicQ e Servizi non condividono la griglia Control"
if grep -Fq '"Ferma MagicQ"' "$control_center"; then
    fail "Wasalight Control espone ancora il pulsante Ferma MagicQ"
fi
if grep -Fq '<item label="Avvia MagicQ">' "$INSTALLER" || \
   grep -Fq '<item label="Ferma MagicQ">' "$INSTALLER"; then
    fail "il menu contestuale Openbox espone ancora Avvia/Ferma MagicQ"
fi
grep -Fq 'self.magicq_auto_switch = Gtk.Switch()' \
    "$control_core/pages/overview.py" || \
    fail "Wasalight Control non espone il toggle automatico MagicQ"
grep -Fq 'magicq-autostart' "$INSTALLER" || \
    fail "l'avvio automatico MagicQ non ha un flag persistente"
grep -Fq 'wasalight-remote-persistence magicq enable' "$INSTALLER" || \
    fail "il toggle MagicQ non dispone del comando sudo ristretto"
grep -Fq 'magicq_auto=enabled' "$INSTALLER" || \
    fail "l'autostart SHOW di MagicQ non legge il flag persistente"
grep -Fq 'def plugin_control_changed' "$control_center" || \
    fail "Wasalight Control non gestisce i toggle servizio dichiarativi"
grep -Fq "background: {palette['brand']}; border-color: {palette['brand']};" \
    "$control_core/style.py" || fail "i toggle Control non usano il token verde Wasabi"
grep -Fq '.flat-card {' "$control_core/style.py" || \
    fail "Control non espone il nuovo componente card flat"
grep -Fq '.text-button {' "$control_core/style.py" || \
    fail "Control non espone le azioni testuali flat"
grep -Fq 'background-image: none; box-shadow: none; text-shadow: none;' \
    "$control_core/style.py" || fail "Control non azzera effetti e ombre GTK native"
grep -Fq 'border: 0 solid transparent; box-shadow: none; font-weight: bold;' \
    "$control_core/style.py" || fail "la navigazione attiva conserva bordi GTK"
grep -Fq "border: 1px solid {palette['separator']}; border-radius: 2px;" \
    "$control_core/style.py" || fail "i pulsanti Control non hanno un bordo tema uniforme"
grep -Fq 'self.shell.configure_language_button(self.show_language_dialog)' \
    "$control_center" || fail "la lingua Control non è separata dalle pagine operative"
grep -Fq 'def show_language_dialog(self):' "$control_center" || \
    fail "la lingua Control non usa un dialogo affidabile"
if grep -Fq 'Gtk.MenuButton' "$control_core/shell.py"; then
    fail "la lingua Control usa ancora il popover non funzionante"
fi
if grep -Fq 'Theme' "$control_core/shell.py" || \
   grep -Fq 'theme_saved' "$control_center"; then
    fail "Control espone ancora un selettore tema"
fi
if grep -Fq '_("Applications")' "$control_core/pages/applications.py" || \
   grep -Fq '_("System")' "$control_core/pages/system.py" || \
   grep -Fq '_("Tools")' "$control_core/pages/tools.py"; then
    fail "le pagine Control ripetono ancora il titolo della navigazione"
fi
if grep -Fq 'Gtk.ComboBoxText()' "$control_core/pages/system.py"; then
    fail "la lingua Control è ancora incorporata nella pagina Sistema"
fi
grep -Fq 'toggle_row(_("Automatic startup"), self.magicq_auto_switch)' \
    "$control_core/pages/overview.py" || \
    fail "MagicQ non usa la riga di avvio automatico comune"
grep -Fq 'if action["management"] or action.get("control")' \
    "$control_core/widgets.py" || \
    fail "le azioni collegate ai toggle sono ancora duplicate come pulsanti"
grep -Fq 'self.system_page = SystemPage(' "$control_center" || \
    fail "Wasalight Control non espone la gestione servizi"
grep -Fq 'self.about_page = AboutPage(' "$control_center" || \
    fail "Wasalight Control non espone la pagina Crediti"
grep -Fq 'Created by Michele Moser /' "$control_core/pages/about.py" || \
    fail "la pagina Crediti non attribuisce Wasalight"
grep -Fq 'https://github.com/wasabifilm/wasalight' "$control_core/pages/about.py" || \
    fail "la pagina Crediti non collega il repository ufficiale"
grep -Fq 'https://www.instagram.com/wasabi_lightbulbfarm/' \
    "$control_core/pages/about.py" || \
    fail "la pagina Crediti non collega Instagram"
for about_contact in \
    'Viale Verona 190/11' '38123 Trento' 'mailto:info@wasabi.eu' \
    'https://www.wasabi.eu/' 'https://www.facebook.com/wasabilightbulbfarm' \
    'https://www.youtube.com/@Wasabi_lightbulbfarm' \
    'https://www.linkedin.com/company/wasabi-lightbulbfarm/'; do
    grep -Fq "$about_contact" "$control_core/pages/about.py" || \
        fail "contatto mancante dalla pagina Crediti: $about_contact"
done
for launcher in files ip-scanner artnet-monitor; do
    launcher_body=$(cat "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/$launcher.desktop")
    grep -Fq 'X-Wasalight-Section=Applications' <<<"$launcher_body" || \
        fail "$launcher non è classificato in Applicazioni"
done
grep -Fq 'installed the verified official Bitfocus Companion icon' "$INSTALLER" || \
    fail "l'installer non registra l'uso dell'icona ufficiale Companion"
grep -Fq 'PLUGIN_COMMAND, "install"' "$control_center" || \
    fail "Wasalight Control non permette di installare plugin disponibili"
grep -Fq 'identity.mode != "MAINTENANCE"' "$control_center" || \
    fail "Wasalight Control consente modifiche plugin persistenti in SHOW"
grep -Fq 'flock -n 9' "$tmp_dir/wasalight-control" || \
    fail "Wasalight Control non impedisce istanze multiple"
grep -Fq 'wmctrl -a "Wasalight Control Center"' "$tmp_dir/wasalight-control" || \
    fail "un secondo avvio di Control non porta in primo piano la finestra esistente"
grep -Fq 'wasalight-control.log' "$tmp_dir/wasalight-control" || \
    fail "Wasalight Control non conserva gli errori di avvio"
grep -Fq 'threading.Thread(target=self.refresh_worker, daemon=True).start()' \
    "$control_center" || \
    fail "Wasalight Control aggiorna ancora lo stato nel thread GTK"
grep -Fq 'ThreadPoolExecutor(max_workers=3)' "$control_center" || \
    fail "Control esegue ancora in serie stato, plugin e MagicQ"
grep -Fq 'timeout=20' "$control_core/system.py" || \
    fail "Control usa ancora un timeout troppo breve per i sistemi lenti"
grep -Fq '/usr/local/libexec/wasalight_control' "$INSTALLER" || \
    fail "l'installer non installa il core Python di Wasalight Control"
grep -Fq 'gettext locales arp-scan' "$INSTALLER" || \
    fail "l'installer non installa gettext e le locale supportate"
grep -Fq 'msgfmt --check' "$INSTALLER" || \
    fail "l'installer non compila i cataloghi di Wasalight Control"
grep -Fq "printf 'it\\n' >\"\$DATA_MOUNT/system/control/language\"" "$INSTALLER" || \
    fail "l'installer non preserva l'italiano come lingua Control iniziale"
grep -Fq '/usr/local/share/wasalight-control/themes/console-dark.ini' "$INSTALLER" || \
    fail "l'installer non installa le palette Control"
grep -Fq 'wasalight_control/pages/' "$INSTALLER" || \
    fail "l'installer non installa i moduli pagina di Wasalight Control"
for locale in en it; do
    for domain in wasalight-control wasalight-system; do
        catalog="$PROJECT_DIR/ui/locale/$locale/LC_MESSAGES/$domain.po"
        [[ -s $catalog ]] || fail "catalogo $domain mancante: $locale"
        grep -Fq "Language: $locale" "$catalog" || \
            fail "catalogo $domain privo della lingua dichiarata: $locale"
    done
done
for manifest in "$PROJECT_DIR"/plugins/*/manifest.ini; do
    for key in Description ActiveLabel InactiveLabel; do
        grep -Eq "^${key}=.+$" "$manifest" || \
            fail "manifest plugin senza testo inglese $key: $manifest"
        grep -Eq "^${key}\[it\]=.+$" "$manifest" || \
            fail "manifest plugin senza testo italiano $key: $manifest"
    done
    while IFS= read -r key; do
        grep -Fq "${key}[it]=" "$manifest" || \
            fail "campo plugin senza variante italiana $key: $manifest"
    done < <(sed -n 's/^\(Name\|Label\|Confirm\)=.*/\1/p' "$manifest" | sort -u)
done
grep -Fq 'def localized(section, key, fallback=""):' "$plugin_command" || \
    fail "il registro plugin non seleziona i campi localizzati"
while IFS= read -r desktop_file; do
    grep -Eq '^Name=.+$' "$desktop_file" || \
        fail "launcher senza nome inglese: $desktop_file"
    grep -Eq '^Name\[it\]=.+$' "$desktop_file" || \
        fail "launcher senza nome italiano: $desktop_file"
    grep -Eq '^Comment=.+$' "$desktop_file" || \
        fail "launcher senza descrizione inglese: $desktop_file"
    grep -Eq '^Comment\[it\]=.+$' "$desktop_file" || \
        fail "launcher senza descrizione italiana: $desktop_file"
done < <(find "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d" \
    "$INSTALLER_TEMPLATE_ROOT/usr/local/share/wasalight/desktop" \
    -type f -name '*.desktop' -print | sort)
grep -Fq 'control_language_file: str = "/data/system/control/language"' \
    "$control_core/models.py" || fail "la lingua Control non è persistente su /data"
grep -Fq 'control_theme_path: str = "/usr/local/share/wasalight-control/themes/console-dark.ini"' \
    "$control_core/models.py" || fail "Control non usa la palette esterna fissa"
grep -Fq 'DEFAULT_PALETTE = {' "$control_core/theme.py" || \
    fail "Control non dispone del fallback tema incorporato"
grep -Fq 'COLOUR.fullmatch(value)' "$control_core/theme.py" || \
    fail "Control non valida i colori dei temi"
grep -Fq 'from wasalight_control.i18n import (' "$control_center" || \
    fail "Wasalight Control non inizializza la localizzazione"
grep -Fq 'timeout --signal=TERM 6 /usr/local/bin/wasalight-touch-status' \
    "$INSTALLER" || fail "lo stato touchscreen può bloccare il refresh Control"
grep -Fq 'dialog.set_keep_above(True)' "$control_core/widgets.py" || \
    fail "i dialoghi GTK di Control non restano in primo piano"
grep -Fq 'Icon=/usr/local/share/icons/wasalight/system-monitor.svg' \
    "$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/system-monitor.desktop" || \
    fail "Monitor sistema non usa l'icona Wasalight dedicata"

date_time_ui="$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-date-time"
time_control="$INSTALLER_TEMPLATE_ROOT/usr/local/sbin/wasalight-time-control"
time_policy="$INSTALLER_TEMPLATE_ROOT/usr/share/polkit-1/actions/com.wasalight.time.policy"
date_time_launcher="$INSTALLER_TEMPLATE_ROOT/etc/wasalight/apps.d/date-time.desktop"
[[ -s $date_time_ui && -s $time_control && -s $time_policy && -s $date_time_launcher ]] || \
    fail "strumento Data e ora incompleto"
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' \
    "$date_time_ui"
bash -n "$time_control"
python3 - "$time_policy" <<'PY' || fail "policy Polkit Data e ora non valida"
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY
grep -Fq 'Exec=/usr/local/bin/wasalight-date-time' "$date_time_launcher" || \
    fail "Data e ora non è registrato in Wasalight Control"
grep -Fq 'X-Wasalight-Section=Support' "$date_time_launcher" || \
    fail "Data e ora non è nella pagina Supporto"
grep -Fq '["pkexec", BACKEND, *arguments]' "$date_time_ui" || \
    fail "Data e ora non usa l'autenticazione grafica Polkit"
grep -Fq 'timedatectl list-timezones | grep -Fqx -- "$2"' "$time_control" || \
    fail "il backend Data e ora non valida il fuso"
grep -Fq 'chronyc -a makestep' "$time_control" || \
    fail "Data e ora non corregge immediatamente scarti NTP elevati"
grep -Fq 'timedatectl set-ntp true' "$time_control" || \
    fail "Data e ora non riattiva esplicitamente la sincronizzazione NTP"
grep -Fq 'timeout 25 chronyc waitsync 25 1' "$time_control" || \
    fail "Data e ora non verifica l'esito della sincronizzazione NTP"
grep -Fq 'systemctl disable --now chrony.service' "$time_control" || \
    fail "l'impostazione manuale non disattiva la sincronizzazione automatica"
grep -Fq 'timedatectl set-ntp false' "$time_control" || \
    fail "l'impostazione manuale lascia attivo lo stato NTP di timedated"
grep -Fq 'if item["optional"]:' "$control_center" || \
    fail "la scheda Plugin mostra ancora i servizi fondamentali"
grep -Fq 'if action["management"] or action.get("control"):' \
    "$control_core/widgets.py" || \
    fail "Control non separa le azioni operative da quelle di gestione"
grep -Fq 'if not optional:' "$plugin_admin" || \
    fail "il gestore permette di disabilitare servizi fondamentali"

plugin_fixture="$tmp_dir/plugin-root"
plugin_state_fixture="$tmp_dir/plugin-state"
service_flag_fixture="$tmp_dir/service-flags"
mkdir -p "$plugin_fixture" "$plugin_state_fixture" "$service_flag_fixture"
cp -R "$PROJECT_DIR/plugins/." "$plugin_fixture/"
# Keep this fixture independent from Companion installed on the host running
# the verifier. Absolute production paths such as /opt/companion and
# /data/companion/installed-version must not affect static project tests.
companion_fixture_manifest="$plugin_fixture/companion/manifest.ini"
sed -i.bak \
    -e "s|^InstalledVersionFile=.*|InstalledVersionFile=$tmp_dir/missing-companion-version|" \
    -e "s|^InstalledCheck=.*|InstalledCheck=$tmp_dir/missing-companion-runtime|" \
    "$companion_fixture_manifest"
rm -f "$companion_fixture_manifest.bak"
printf 'disabled\n' >"$plugin_state_fixture/ssh"
printf 'enabled\n' >"$service_flag_fixture/ssh-autostart"
printf 'disabled\n' >"$service_flag_fixture/vnc-autostart"
printf 'enabled\n' >"$service_flag_fixture/companion-autostart"
plugin_json=$(WASALIGHT_PLUGIN_ROOT="$plugin_fixture" \
    WASALIGHT_PLUGIN_STATE_ROOT="$plugin_state_fixture" \
    WASALIGHT_SERVICE_FLAG_ROOT="$service_flag_fixture" \
    WASALIGHT_PLUGIN_TEST_MODE=maintenance \
    WASALIGHT_VERSION_OVERRIDE="$project_version" \
    LANGUAGE=it_IT.UTF-8 \
    python3 "$plugin_command" list --json)
python3 - "$plugin_json" <<'PY' || fail "registro plugin Wasalight non valido"
import json
import sys
plugins = {item["id"]: item for item in json.loads(sys.argv[1])}
assert set(plugins) == {"companion", "ssh", "vnc"}
assert plugins["ssh"]["enabled"] is True
assert plugins["vnc"]["enabled"] is True
assert plugins["ssh"]["optional"] is False
assert plugins["vnc"]["optional"] is False
assert plugins["companion"]["optional"] is True
assert plugins["companion"]["category"] == "Services"
assert plugins["companion"]["compatible"] is True
assert plugins["ssh"]["persistent"] is True
assert plugins["vnc"]["persistent"] is False
assert plugins["companion"]["persistent"] is True
assert plugins["ssh"]["state_label"].endswith("AUTO")
assert plugins["vnc"]["state_label"].endswith("MANUALE")
for plugin_id in ("ssh", "vnc", "companion"):
    controls = {control["id"]: control for control in plugins[plugin_id]["controls"]}
    assert set(controls) == {"runtime", "automatic"}
    assert controls["runtime"]["label"] == "Servizio attivo"
    assert controls["automatic"]["label"] == "Avvio automatico"
    assert controls["runtime"]["checked"] is plugins[plugin_id]["active"]
    assert controls["automatic"]["checked"] is plugins[plugin_id]["persistent"]
    controlled = {action["id"] for action in plugins[plugin_id]["actions"]
                  if action["control"]}
    assert controlled == {"start", "stop", "auto-enable", "auto-disable"}
assert any(action["id"] == "open" for action in plugins["companion"]["actions"])
assert any(action["id"] == "update" and action["management"]
           for action in plugins["companion"]["actions"])
backup = next(action for action in plugins["companion"]["actions"]
              if action["id"] == "backup")
assert backup["management"] is True
assert backup["show_output"] is True
assert plugins["companion"]["installed_version"] == ""
assert plugins["companion"]["endpoint"] == ""
PY
if WASALIGHT_PLUGIN_ROOT="$plugin_fixture" \
   WASALIGHT_PLUGIN_STATE_ROOT="$plugin_state_fixture" \
   python3 "$plugin_command" action ssh not-an-action >/dev/null 2>&1; then
    fail "il manager plugin accetta azioni non dichiarate"
fi
for plugin in ssh vnc companion; do
    manifest="$PROJECT_DIR/plugins/$plugin/manifest.ini"
    [[ -s $manifest ]] || fail "manifest plugin mancante: $plugin"
    grep -Fq "Id=$plugin" "$manifest" || fail "ID manifest plugin errato: $plugin"
done
grep -Fq 'Optional=false' "$PROJECT_DIR/plugins/ssh/manifest.ini" || \
    fail "SSH non è dichiarato come servizio fondamentale"
grep -Fq 'Optional=false' "$PROJECT_DIR/plugins/vnc/manifest.ini" || \
    fail "VNC non è dichiarato come servizio fondamentale"
grep -Fq 'Key=ssh-autostart' "$PROJECT_DIR/plugins/ssh/manifest.ini" || \
    fail "il manifest SSH non dichiara il flag persistente"
grep -Fq 'Key=vnc-autostart' "$PROJECT_DIR/plugins/vnc/manifest.ini" || \
    fail "il manifest VNC non dichiara il flag persistente"
grep -Fq 'Key=companion-autostart' "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "il manifest Companion non dichiara il flag persistente"
for manifest in "$PROJECT_DIR/plugins/ssh/manifest.ini" \
                "$PROJECT_DIR/plugins/vnc/manifest.ini" \
                "$PROJECT_DIR/plugins/companion/manifest.ini"; do
    grep -Fq '[Control runtime]' "$manifest" || fail "toggle runtime mancante: $manifest"
    grep -Fq '[Control automatic]' "$manifest" || fail "toggle automatico mancante: $manifest"
done
grep -Fq 'Command=/usr/local/bin/wasalight-companion-update-terminal' \
    "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "Companion non espone l'aggiornamento dal Control Center"
grep -Fq 'Command=/usr/local/sbin/wasalight-companion-backup' \
    "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "Companion non espone il backup dal Control Center"
grep -Fq 'InstalledVersionFile=/data/companion/installed-version' \
    "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "Companion non espone la versione installata"
grep -Fq 'Port=8000' "$PROJECT_DIR/plugins/companion/manifest.ini" || \
    fail "Companion non espone la porta per l'indirizzo di Sistema"

for embedded in \
    'wasalight-ip-scanner.py:/usr/local/libexec/wasalight-ip-scanner.py' \
    'wasalight-artnet-capture:/usr/local/sbin/wasalight-artnet-capture' \
    'wasalight-artnet-monitor.py:/usr/local/libexec/wasalight-artnet-monitor.py'; do
    output=${embedded%%:*}
    marker=${embedded#*:}
    cp "$INSTALLER_TEMPLATE_ROOT$marker" "$tmp_dir/$output"
    [[ -s $tmp_dir/$output ]] || fail "strumento Python non estraibile: $output"
    python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
        "$tmp_dir/$output"
done
window_icon="$INSTALLER_TEMPLATE_ROOT/usr/local/bin/wasalight-x11-window-icon"
[[ -s $window_icon ]] || fail "helper icona X11 Companion mancante"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$window_icon"
grep -Fq '_NET_WM_ICON' "$window_icon" || \
    fail "l’helper Companion non imposta la proprietà icona EWMH"

for embedded in \
    'companion-control:/usr/local/sbin/wasalight-companion-control' \
    'companion-backup:/usr/local/sbin/wasalight-companion-backup' \
    'companion-update:/usr/local/sbin/wasalight-companion-update' \
    'companion-update-session:/usr/local/libexec/wasalight-companion-update-session' \
    'companion-panel:/usr/local/bin/wasalight-companion-panel' \
    'companion-browser:/usr/local/bin/wasalight-companion-browser' \
    'falkon-profile:/usr/local/bin/wasalight-falkon-profile'; do
    output=${embedded%%:*}
    marker=${embedded#*:}
    cp "$INSTALLER_TEMPLATE_ROOT$marker" "$tmp_dir/$output"
    [[ -s $tmp_dir/$output ]] || fail "strumento Companion non estraibile: $output"
    bash -n "$tmp_dir/$output"
done
grep -Fq 'pkexec /usr/local/sbin/wasalight-companion-update' \
    "$tmp_dir/companion-update-session" || \
    fail "l'aggiornamento Companion non usa l'autenticazione grafica Polkit"
if grep -Fq 'sudo /usr/local/sbin/wasalight-companion-update' \
    "$tmp_dir/companion-update-session"; then
    fail "l'aggiornamento Companion richiede ancora la password nel terminale"
fi
grep -Fq '!= overlay' "$tmp_dir/companion-backup" || \
    fail "il backup Companion non è limitato alla modalità MAINTENANCE"
grep -Fq '!= overlay' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non è limitato alla modalità MAINTENANCE"
grep -Fq '/usr/local/sbin/wasalight-companion-backup' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non crea prima un backup"
grep -Fq '/opt/companion/BUILD' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non verifica la versione realmente installata"
grep -Fq 'actual=${actual%%+*}' "$tmp_dir/companion-update" || \
    fail "l'aggiornamento Companion non ignora correttamente i metadata SemVer"

update_policy="$INSTALLER_TEMPLATE_ROOT/usr/share/polkit-1/actions/com.wasalight.updates.policy"
[[ -s $update_policy ]] || fail "policy Polkit degli aggiornamenti mancante"
python3 - "$update_policy" <<'PY' || fail "policy Polkit degli aggiornamenti non valida"
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
expected = {
    "com.wasalight.update": "/usr/local/sbin/wasalight-update",
    "com.wasalight.companion.update": "/usr/local/sbin/wasalight-companion-update",
}
actions = {action.attrib.get("id"): action for action in root.findall("action")}
for action_id, executable in expected.items():
    action = actions.get(action_id)
    if action is None:
        raise SystemExit(f"azione mancante: {action_id}")
    defaults = action.find("defaults")
    if defaults is None or defaults.findtext("allow_active") != "auth_admin":
        raise SystemExit(f"autenticazione amministratore mancante: {action_id}")
    if defaults.findtext("allow_any") != "no" or defaults.findtext("allow_inactive") != "no":
        raise SystemExit(f"policy troppo permissiva: {action_id}")
    paths = [node.text for node in action.findall("annotate")
             if node.attrib.get("key") == "org.freedesktop.policykit.exec.path"]
    if paths != [executable]:
        raise SystemExit(f"eseguibile non vincolato: {action_id}")
PY
companion_build='5.0.3+9703-stable-2daa0d7670'
companion_core=${companion_build#[vV]}
companion_core=${companion_core%%+*}
[[ $companion_core == 5.0.3 ]] || \
    fail "normalizzazione SemVer Companion non valida"
grep -Fq 'http://127.0.0.1:8000' "$tmp_dir/companion-browser" || \
    fail "il browser Companion non usa l'interfaccia locale"
grep -Fq '/data/companion/browser/config' "$tmp_dir/companion-browser" || \
    fail "il profilo Falkon Companion non è persistente"
grep -Fq 'wasalight-x11-window-icon' "$tmp_dir/companion-browser" || \
    fail "il browser Companion non sostituisce l’icona Falkon nel dock"
if grep -Fq '/data/companion/browser/cache' "$tmp_dir/companion-browser"; then
    fail "la cache Falkon non deve essere persistente in /data"
fi

falkon_profile_fixture="$tmp_dir/falkon-profile-fixture"
mkdir -p "$falkon_profile_fixture"
cat >"$falkon_profile_fixture/settings.ini" <<'EOF'
[General]
keep=true

[Plugin-Settings]
AllowedPlugins=internal:adblock, lib:KDEFrameworksIntegration.so

[Other]
keep=this-too
EOF
WASALIGHT_FALKON_PROFILE_ROOT="$falkon_profile_fixture" \
    bash "$tmp_dir/falkon-profile"
grep -Fq '#locationbar,' "$falkon_profile_fixture/userChrome.css" || \
    fail "il profilo Falkon non nasconde il campo indirizzo e ricerca"
grep -Fq '#locationbar-bookmarkicon,' "$falkon_profile_fixture/userChrome.css" || \
    fail "il profilo Falkon non nasconde il comando bookmark"
grep -Fq '#locationbar-down-icon {' "$falkon_profile_fixture/userChrome.css" || \
    fail "il profilo Falkon non nasconde la freccia della barra indirizzi"
grep -Fq 'AllowedPlugins=lib:KDEFrameworksIntegration.so' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non conserva gli altri plugin"
if grep -Fq 'internal:adblock' "$falkon_profile_fixture/settings.ini"; then
    fail "il profilo Falkon non disattiva AdBlock"
fi
grep -Fq 'keep=this-too' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon altera sezioni non correlate"
grep -Fq 'homepage=http://127.0.0.1:8000' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non imposta Companion come pagina iniziale"
grep -Fq 'afterLaunch=1' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon ripristina ancora la sessione precedente"
grep -Fq 'DefaultZoomLevel=8' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non usa lo zoom touch al 120 percento"
grep -Fq 'hideTabsWithOneTab=true' "$falkon_profile_fixture/settings.ini" || \
    fail "il profilo Falkon non nasconde la barra con una singola scheda"
grep -Fq 'Layout=button-backforward, button-reloadstop, button-home, button-tools' \
    "$falkon_profile_fixture/settings.ini" || \
    fail "la barra Falkon mantiene ancora indirizzo, ricerca o bookmark"
grep -Fq 'min-height: 46px' "$falkon_profile_fixture/userChrome.css" || \
    fail "il tema Falkon non crea controlli touch sufficientemente grandi"
[[ -e $falkon_profile_fixture/.wasalight-profile-3 ]] || \
    fail "il profilo Falkon non registra l'inizializzazione dei default"

# After the first seed, updates preserve operator preferences while continuing
# to enforce the deliberate AdBlock exclusion.
sed -i.bak 's/showStatusBar=false/showStatusBar=true/' \
    "$falkon_profile_fixture/settings.ini"
rm -f "$falkon_profile_fixture/settings.ini.bak"
sed -i.bak 's/AllowedPlugins=lib:KDEFrameworksIntegration.so/AllowedPlugins=internal:adblock, lib:KDEFrameworksIntegration.so/' \
    "$falkon_profile_fixture/settings.ini"
rm -f "$falkon_profile_fixture/settings.ini.bak"
WASALIGHT_FALKON_PROFILE_ROOT="$falkon_profile_fixture" \
    bash "$tmp_dir/falkon-profile"
grep -Fq 'showStatusBar=true' "$falkon_profile_fixture/settings.ini" || \
    fail "un update Wasalight sovrascrive le preferenze Falkon dell'operatore"
if grep -Fq 'internal:adblock' "$falkon_profile_fixture/settings.ini"; then
    fail "un update Wasalight riattiva AdBlock"
fi

empty_falkon_profile="$tmp_dir/falkon-profile-empty"
WASALIGHT_FALKON_PROFILE_ROOT="$empty_falkon_profile" \
    bash "$tmp_dir/falkon-profile"
grep -Fq 'AllowedPlugins=@Invalid()' "$empty_falkon_profile/settings.ini" || \
    fail "un nuovo profilo Falkon abilita ancora AdBlock per default"
grep -Fq 'showStatusBar=false' "$empty_falkon_profile/settings.ini" || \
    fail "un nuovo profilo Falkon non applica i default Wasalight"
[[ -s $empty_falkon_profile/userChrome.css ]] || \
    fail "un nuovo profilo Falkon non installa il tema Wasalight"

[[ -s "$PROJECT_DIR/docs/touchscreen.md" ]] || fail "guida touchscreen mancante"
grep -Fq 'wasalight-touch-config set' "$PROJECT_DIR/docs/touchscreen.md" || \
    fail "configurazione touchscreen non documentata"
grep -Fq '/stick/<dispositivo>' "$PROJECT_DIR/packages/README.md" || \
    fail "aggiornamento MagicQ da USB non documentato in packages/README.md"
[[ -s "$PROJECT_DIR/docs/vnc.md" ]] || fail "guida VNC mancante"
[[ -s "$PROJECT_DIR/docs/ssh.md" ]] || fail "guida SSH mancante"
[[ -s "$PROJECT_DIR/docs/update.md" ]] || fail "guida aggiornamenti mancante"
[[ -s "$PROJECT_DIR/docs/system-cleanup.md" ]] || fail "guida pulizia sistema mancante"
[[ -s "$PROJECT_DIR/docs/boot-branding.md" ]] || fail "guida branding di avvio mancante"
[[ -s "$PROJECT_DIR/docs/licensing.md" ]] || fail "guida licenza mancante"
[[ -s "$PROJECT_DIR/docs/versioning.md" ]] || fail "guida versionamento mancante"
[[ -s "$PROJECT_DIR/docs/companion.md" ]] || fail "guida Bitfocus Companion mancante"
grep -Fq '/data/companion/home' "$PROJECT_DIR/docs/companion.md" || \
    fail "persistenza Companion non documentata"
grep -Fq '127.0.0.1' "$PROJECT_DIR/docs/companion.md" || \
    fail "collegamento locale MagicQ/Companion non documentato"
grep -Fq 'wasalight-update --with-companion' "$PROJECT_DIR/docs/companion.md" || \
    fail "installazione Companion tramite updater non documentata"
grep -Fq '/data/companion/browser' "$PROJECT_DIR/docs/companion.md" || \
    fail "profilo persistente Falkon non documentato"
grep -Fq 'internal:adblock' "$PROJECT_DIR/docs/companion.md" || \
    fail "disattivazione AdBlock Falkon non documentata"
grep -Fq '## Bitfocus Companion opzionale' "$PROJECT_DIR/docs/hardware-test-checklist.md" || \
    fail "collaudo hardware Companion non documentato"
[[ -s "$PROJECT_DIR/LICENSE" ]] || fail "Apache License 2.0 mancante"
grep -Fq 'Apache License' "$PROJECT_DIR/LICENSE" || fail "testo licenza Apache non valido"
grep -Fq 'Version 2.0, January 2004' "$PROJECT_DIR/LICENSE" || \
    fail "versione della licenza Apache non valida"
while IFS= read -r source_file; do
    grep -Fq 'Copyright 2026 Michele Moser' "$source_file" || \
        fail "copyright mancante dal sorgente: ${source_file#"$PROJECT_DIR/"}"
    grep -Fq 'SPDX-License-Identifier: Apache-2.0' "$source_file" || \
        fail "identificatore SPDX mancante dal sorgente: ${source_file#"$PROJECT_DIR/"}"
    first_line=$(sed -n '1p' "$source_file")
    if [[ $first_line == '#!'* ]]; then
        [[ $(sed -n '2p' "$source_file") == '# Copyright 2026 Michele Moser' ]] || \
            fail "copyright non immediatamente dopo shebang: ${source_file#"$PROJECT_DIR/"}"
    else
        [[ $first_line == '# Copyright 2026 Michele Moser' ]] || \
            fail "copyright non in testa al sorgente: ${source_file#"$PROJECT_DIR/"}"
    fi
done < <(find "$PROJECT_DIR" -path "$PROJECT_DIR/.git" -prune -o -type f \
    \( -name '*.sh' -o -name '*.py' -o -perm -111 \) -print | sort)
[[ -s "$PROJECT_DIR/NOTICE" ]] || fail "NOTICE di attribuzione mancante"
grep -Fq 'Wasalight — created by Michele Moser / Wasabi Lightbulbfarm.' \
    "$PROJECT_DIR/NOTICE" || fail "citazione Wasalight mancante dal NOTICE"
grep -Fq '@wasabi_lightbulbfarm' "$PROJECT_DIR/NOTICE" || \
    fail "account Instagram mancante dal NOTICE"
[[ -s "$PROJECT_DIR/CONTACT.md" ]] || fail "contatti ufficiali mancanti"
for contact_value in \
    'Viale Verona 190/11' '38123 Trento' 'info@wasabi.eu' \
    'https://www.wasabi.eu/' 'https://www.facebook.com/wasabilightbulbfarm' \
    'https://www.youtube.com/@Wasabi_lightbulbfarm' \
    'https://www.linkedin.com/company/wasabi-lightbulbfarm/'; do
    grep -Fq "$contact_value" "$PROJECT_DIR/CONTACT.md" || \
        fail "contatto ufficiale mancante: $contact_value"
done
[[ -s "$PROJECT_DIR/TRADEMARKS.md" ]] || fail "policy sul marchio mancante"
grep -Fq 'non è una distribuzione ufficiale Wasalight' \
    "$PROJECT_DIR/TRADEMARKS.md" || fail "regola per derivazioni non ufficiali mancante"
[[ -s "$PROJECT_DIR/CITATION.cff" ]] || fail "metadati di citazione mancanti"
grep -Fq 'license: Apache-2.0' "$PROJECT_DIR/CITATION.cff" || \
    fail "licenza mancante dai metadati di citazione"
grep -Fq 'install_wasalight_legal_notices' "$INSTALLER" || \
    fail "l'installer non conserva gli avvisi legali nell'appliance"
grep -Fq 'for document in LICENSE NOTICE CONTACT.md TRADEMARKS.md CITATION.cff' \
    "$INSTALLER" || fail "insieme degli avvisi legali installati incompleto"
grep -Fq '/usr/share/doc/wasalight/$document' "$INSTALLER" || \
    fail "destinazione degli avvisi legali non valida"
[[ -s "$PROJECT_DIR/assets/branding/LICENSE" ]] || fail "licenza separata del logo mancante"
grep -Fq 'excluded from the Apache' "$PROJECT_DIR/assets/branding/LICENSE" || \
    fail "esclusione del logo dalla licenza Apache non documentata"
[[ -s "$PROJECT_DIR/assets/branding/boot-logo.png" ]] || fail "logo Plymouth predefinito mancante"
if grep -Fq 'plymouth-set-default-theme' "$INSTALLER"; then
    fail "il comando Plymouth rimosso da Ubuntu 24.04 è ancora utilizzato"
fi
grep -Fq 'readlink -f /usr/share/plymouth/themes/default.plymouth' "$INSTALLER" || \
    fail "il tema Plymouth attivo non viene verificato tramite alternatives"
if grep -Eq -- '--chamsys-admin|--purge-cloud-init|previous_default_sha256' "$INSTALLER" || \
   grep -Fq '/home/*/wasalight/packages/*.deb' "$INSTALLER"; then
    fail "l'installer contiene ancora compatibilità con versioni Wasalight precedenti"
fi
if grep -Fq 'wasalight-hub' "$INSTALLER" || \
   [[ -e "$PROJECT_DIR/docs/migration-24.04.md" ]]; then
    fail "la prima base contiene ancora componenti o guide delle versioni precedenti"
fi
for old_command in \
    magicq-status magicq-maintenance magicq-protect magicq-touch \
    magicq-vnc magicq-audio-test magicq-set-mode magicq-usb magicq-logrotate; do
    if grep -Eq "(^|[/[:space:]\"'])${old_command}([[:space:]\"']|$)" "$INSTALLER"; then
        fail "nome comando non uniforme ancora presente: $old_command"
    fi
done
for label in '("overview", _("Overview"), self.overview_page)' \
    '("applications", _("Applications"), self.applications_page.widget)' \
    '("system", _("System"), self.system_page.widget)' \
    '("tools", _("Tools"), self.tools_page.widget)' \
    '("maintenance", _("Plugins"), self.maintenance_page.widget)' \
    '("about", _("About"), self.about_page.widget)' \
    'ApplicationShell(identity, pages, self.destroy)'; do
    grep -Fq "$label" "$control_center" || \
        fail "etichetta Control non uniformata: $label"
done
grep -Fq 'Gtk.Button(label=f"✕  {_('"'"'Close'"'"')}")' "$control_core/shell.py" || \
    fail "la shell Control non espone un simbolo Chiudi riconoscibile"
grep -Fq 'close.set_size_request(150, 56)' "$control_core/shell.py" || \
    fail "il pulsante Chiudi di Control non ha una dimensione touch evidente"
grep -Fq 'add_class("close-button")' "$control_core/shell.py" || \
    fail "il pulsante Chiudi di Control non usa uno stile dedicato"
grep -Fq '.close-button {' "$control_core/style.py" || \
    fail "lo stile Control non evidenzia il pulsante Chiudi"
grep -Fq "background: {palette['danger']}; color: {palette['text']};" \
    "$control_core/style.py" || fail "il pulsante Chiudi non usa i colori danger del tema"
python3 - "$PROJECT_DIR/assets/branding/boot-logo.png" <<'PY' || fail "logo Plymouth predefinito non valido"
import struct
import sys
with open(sys.argv[1], "rb") as source:
    assert source.read(8) == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">I", source.read(4))[0] == 13
    assert source.read(4) == b"IHDR"
    width, height = struct.unpack(">II", source.read(8))
assert (width, height) == (1200, 627)
PY
grep -Fq 'Ubuntu Server 24.04 LTS' "$PROJECT_DIR/README.md" || \
    fail "target Ubuntu 24.04 non documentato"
grep -Fq 'packages/*.deb' "$PROJECT_DIR/.gitignore" || \
    fail "i pacchetti MagicQ proprietari non sono esclusi da Git"
if grep -Fq 'VERSION_ID:-} == 22.04' "$INSTALLER"; then
    fail "il vecchio target Ubuntu 22.04 è ancora accettato"
fi
if grep -Fq '/media/usb' "$INSTALLER"; then
    fail "il vecchio percorso USB /media/usb è ancora configurato"
fi
if grep -Eq 'usermod .*netdev|groupadd .*netdev' "$INSTALLER"; then
    fail "l'installer dipende ancora dal gruppo opzionale netdev"
fi
if grep -Eq 'chpasswd|usermod .* -p |/etc/shadow' "$INSTALLER"; then
    fail "la password chamsys non deve essere copiata o gestita in forma non interattiva"
fi
if grep -Fq 'ENABLE_CHAMSYS_ADMIN' "$INSTALLER"; then
    fail "l'accesso amministrativo chamsys non deve più essere opzionale"
fi
grep -Fq -- '--reset-chamsys-password' "$PROJECT_DIR/README.md" || \
    fail "l'accesso amministrativo chamsys non è documentato"
grep -Fq 'chown -R "$TARGET_USER:$TARGET_USER" "$DATA_MOUNT/magicq"' "$INSTALLER" || \
    fail "la riparazione dei proprietari MagicQ persistenti è assente"
grep -Fq 'repair_magicq_persistent_permissions' "$INSTALLER" || \
    fail "la riparazione post-installazione dei permessi MagicQ è assente"
if grep -Eq 'gio[[:space:]]+set.*metadata::trusted' "$INSTALLER"; then
    fail "l'installer dipende ancora dal metadato GIO non supportato da PCManFM"
fi
