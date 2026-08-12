#!/usr/bin/env python3
"""Touch-first unified Wasalight desktop management interface."""

import concurrent.futures
import os
import re
import shlex
import threading

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

from wasalight_control.commands import CommandRunner
from wasalight_control.launchers import installed_launchers
from wasalight_control.models import ControlPaths
from wasalight_control.system import magicq_state, mode_and_version, read_plugins, read_status
from wasalight_control.widgets import (
    card_flow, clear_flow, image_for, plugin_card, prepare_dialog,
    section_heading, software_button, toggle_row,
)

PATHS = ControlPaths()
COMMANDS = CommandRunner()
PLUGIN_COMMAND = PATHS.plugin_command
FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")
PAGE_LABELS = {
    "Dashboard": "Stato",
    "MagicQ": "MagicQ",
    "Services": "Servizi",
    "Applications": "Applicazioni",
    "Support": "Supporto",
    "Plugins": "Plugin",
    "Credits": "Crediti",
}
class ControlCenter(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight Control Center")
        self.set_default_size(1040, 720)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.maximize()
        try:
            self.set_icon_from_file("/usr/local/share/icons/wasalight/hub.svg")
        except Exception:
            pass
        self.connect("destroy", self.on_destroy)
        self.refresh_running = False
        self.destroyed = False
        self.plugins = []
        self.plugin_cards = Gtk.FlowBox()
        self.service_cards = Gtk.FlowBox()
        self.status_view = Gtk.TextView()
        self.magicq_state_label = Gtk.Label()
        self.magicq_auto_switch = Gtk.Switch()
        self.magicq_auto_handler = None

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_border_width(16)
        outer.pack_start(self.header(), False, False, 0)
        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        outer.pack_start(self.notebook, True, True, 0)
        self.add_dashboard()
        launchers = installed_launchers(PATHS)
        self.add_magicq_page(launchers)
        self.add_service_page()
        self.add_launcher_page("Applications", launchers)
        self.add_launcher_page("Support", launchers)
        self.add_plugin_page("Plugins", self.plugin_cards)
        self.add_credits_page()

        footer = Gtk.Box(spacing=10)
        refresh = Gtk.Button(label="Aggiorna")
        refresh.set_size_request(160, 54)
        refresh.connect("clicked", lambda _button: self.refresh_all())
        close = Gtk.Button(label="Chiudi")
        close.set_size_request(160, 54)
        close.connect("clicked", lambda _button: self.destroy())
        footer.pack_start(Gtk.Label(), True, True, 0)
        footer.pack_start(refresh, False, False, 0)
        footer.pack_start(close, False, False, 0)
        outer.pack_start(footer, False, False, 0)
        self.add(outer)
        self.refresh_all()
        GLib.timeout_add_seconds(3, self.periodic_refresh)

    def on_destroy(self, _window):
        self.destroyed = True
        Gtk.main_quit()

    def header(self):
        identity = mode_and_version(PATHS, COMMANDS)
        box = Gtk.Box(spacing=14)
        box.pack_start(image_for("/usr/local/share/icons/wasalight/hub.svg", 58), False, False, 0)
        title = Gtk.Label()
        title.set_xalign(0)
        title.set_markup("<span foreground='#76bd22' size='20000' weight='bold'>Wasalight Control</span>\n"
                         "<span size='9500'>MagicQ · servizi · applicazioni · sistema</span>")
        box.pack_start(title, True, True, 0)
        state = Gtk.Label()
        colour = "#76bd22" if identity.mode == "SHOW" else "#f2cc60"
        state.set_markup(f"<span foreground='{colour}' weight='bold'>{identity.mode}</span>\n"
                         f"<span size='8500'>Wasalight {GLib.markup_escape_text(identity.version)}</span>")
        state.set_justify(Gtk.Justification.RIGHT)
        box.pack_start(state, False, False, 0)
        return box

    def add_dashboard(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        controls = Gtk.Box(spacing=10)
        identity = mode_and_version(PATHS, COMMANDS)
        mode_label = "Passa a MAINTENANCE" if identity.mode == "SHOW" else "Passa a SHOW"
        for label, command in (
                ("Aggiorna", [PATHS.update_terminal]),
                (mode_label, [PATHS.mode_toggle])):
            button = Gtk.Button(label=label)
            button.set_size_request(180, 64)
            button.connect("clicked", self.run_desktop_command, command)
            controls.pack_start(button, True, True, 0)
        box.pack_start(controls, False, False, 0)
        self.status_view.set_editable(False)
        self.status_view.set_cursor_visible(False)
        self.status_view.set_monospace(True)
        self.status_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.status_view)
        box.pack_start(scroll, True, True, 0)
        self.notebook.append_page(box, Gtk.Label(label=PAGE_LABELS["Dashboard"]))

    def add_magicq_page(self, launchers):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(14)
        page.pack_start(section_heading(
            "Software ChamSys",
            "Avvio rapido dei programmi installati e controllo dell’avvio automatico di MagicQ."),
            False, False, 0)

        status_card = Gtk.Frame()
        status_row = Gtk.Box(spacing=18)
        status_row.set_border_width(14)
        self.magicq_state_label.set_xalign(0)
        status_row.pack_start(self.magicq_state_label, True, True, 0)
        auto_row = toggle_row("Avvio automatico", self.magicq_auto_switch)
        self.magicq_auto_handler = self.magicq_auto_switch.connect(
            "state-set", self.magicq_auto_changed)
        status_row.pack_start(auto_row, False, False, 0)
        status_card.add(status_row)
        page.pack_start(status_card, False, False, 0)

        flow = card_flow()
        magicq = software_button(
            "MagicQ", "Console luci principale",
            "/usr/share/pixmaps/magicq.png",
            lambda button: self.run_desktop_command(button, [PATHS.magicq_start]))
        magicq.set_sensitive(os.path.exists("/opt/magicq"))
        flow.add(magicq)

        companions = [item for item in launchers if item.section == "MagicQ"]
        for item in companions:
            flow.add(software_button(
                item.name, item.comment or "Programma ChamSys",
                item.icon,
                lambda button, selected=item: self.launch_application(button, selected)))
        page.pack_start(flow, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(page)
        self.notebook.append_page(scroll, Gtk.Label(label=PAGE_LABELS["MagicQ"]))

    def add_launcher_page(self, section, launchers):
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
        flow.set_max_children_per_line(5)
        flow.set_min_children_per_line(2)
        items = [item for item in launchers if item.section == section]
        if not items:
            empty = Gtk.Label(label="Nessuna applicazione registrata")
            empty.set_margin_top(40)
            flow.add(empty)
        for item in items:
            button = Gtk.Button()
            button.set_size_request(180, 132)
            button.set_tooltip_text(item.comment)
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
            content.pack_start(image_for(item.icon, 58), True, True, 0)
            label = Gtk.Label(label=item.name)
            label.set_line_wrap(True)
            label.set_justify(Gtk.Justification.CENTER)
            content.pack_start(label, False, False, 0)
            button.add(content)
            button.connect("clicked", self.launch_application, item)
            flow.add(button)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(flow)
        self.notebook.append_page(scroll, Gtk.Label(label=PAGE_LABELS[section]))

    def add_service_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(14)
        page.pack_start(section_heading(
            "Servizi",
            "Controllo uniforme dello stato corrente e della persistenza dei servizi Wasalight."),
            False, False, 0)
        self.service_cards = card_flow()
        page.pack_start(self.service_cards, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(page)
        self.notebook.append_page(scroll, Gtk.Label(label=PAGE_LABELS["Services"]))

    def add_plugin_page(self, title, flow):
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
        flow.set_max_children_per_line(3)
        flow.set_min_children_per_line(1)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(flow)
        self.notebook.append_page(scroll, Gtk.Label(label=PAGE_LABELS[title]))

    def add_credits_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(14)
        page.pack_start(section_heading(
            "Crediti",
            "Autori, licenza e riconoscimenti del progetto."), False, False, 0)

        frame = Gtk.Frame()
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_border_width(22)
        content.pack_start(
            image_for("/usr/share/plymouth/themes/wasalight/boot-logo.png", 190),
            False, False, 0)
        identity = mode_and_version(PATHS, COMMANDS)
        title = Gtk.Label()
        title.set_markup(
            "<span foreground='#76bd22' size='17000' weight='bold'>Wasalight</span>\n"
            f"<span size='9500'>Versione {GLib.markup_escape_text(identity.version)}</span>")
        title.set_justify(Gtk.Justification.CENTER)
        content.pack_start(title, False, False, 0)

        author = Gtk.Label()
        author.set_markup(
            "<span size='11000' weight='bold'>Creato da Michele Moser / "
            "Wasabi Lightbulbfarm</span>")
        author.set_line_wrap(True)
        author.set_justify(Gtk.Justification.CENTER)
        content.pack_start(author, False, False, 0)

        license_text = Gtk.Label(label=(
            "Codice e documentazione: Apache License 2.0. "
            "Il logo Wasabi Lightbulbfarm è escluso dalla licenza software e resta protetto.\n"
            "ChamSys MagicQ e Bitfocus Companion sono prodotti esterni e mantengono "
            "i rispettivi marchi e licenze."))
        license_text.set_line_wrap(True)
        license_text.set_justify(Gtk.Justification.CENTER)
        license_text.set_max_width_chars(78)
        content.pack_start(license_text, False, False, 0)

        links = Gtk.Box(spacing=12)
        github = Gtk.LinkButton.new_with_label(
            "https://github.com/wasabifilm/wasalight", "Progetto GitHub")
        instagram = Gtk.LinkButton.new_with_label(
            "https://www.instagram.com/wasabi_lightbulbfarm/",
            "@wasabi_lightbulbfarm")
        github.set_size_request(220, 58)
        instagram.set_size_request(260, 58)
        links.pack_start(Gtk.Label(), True, True, 0)
        links.pack_start(github, False, False, 0)
        links.pack_start(instagram, False, False, 0)
        links.pack_start(Gtk.Label(), True, True, 0)
        content.pack_start(links, False, False, 0)
        frame.add(content)
        page.pack_start(frame, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(page)
        self.notebook.append_page(scroll, Gtk.Label(label=PAGE_LABELS["Credits"]))

    def apply_refresh(self, status, plugins, magicq, error):
        self.refresh_running = False
        if self.destroyed:
            return False
        if error:
            status = f"{status}\n\nCONTROL:    avviso aggiornamento: {error}"
        self.status_view.get_buffer().set_text(status)
        if magicq is not None:
            self.magicq_state_label.set_markup(
                f"<span foreground='{'#76bd22' if magicq.running else '#f2cc60'}' weight='bold'>"
                f"{'APERTO' if magicq.running else 'CHIUSO'}</span> · "
                f"{'AUTO' if magicq.automatic else 'MANUALE'}")
            self.magicq_auto_switch.handler_block(self.magicq_auto_handler)
            self.magicq_auto_switch.set_active(magicq.automatic)
            self.magicq_auto_switch.handler_unblock(self.magicq_auto_handler)
        if plugins is not None and plugins != self.plugins:
            self.plugins = plugins
            clear_flow(self.service_cards)
            clear_flow(self.plugin_cards)
            for item in self.plugins:
                if item["category"] == "Services" and item["enabled"]:
                    self.service_cards.add(self.make_plugin_card(item))
                if item["optional"]:
                    self.plugin_cards.add(self.make_plugin_card(item, management=True))
            self.service_cards.show_all()
            self.plugin_cards.show_all()
        return False

    def make_plugin_card(self, item, management=False):
        return plugin_card(
            item,
            management=management,
            change_state=self.change_plugin_state,
            install=self.install_plugin,
            run_action=self.plugin_action,
            control_changed=self.plugin_control_changed,
        )

    def refresh_worker(self):
        status = "Stato non disponibile"
        plugins = None
        magicq = None
        errors = []
        # These probes are independent. Running them concurrently prevents a
        # slow XInput scan from consuming the whole Control refresh budget.
        tasks = {
            "stato": lambda: read_status(PATHS, COMMANDS),
            "plugins": lambda: read_plugins(PATHS, COMMANDS),
            "MagicQ": lambda: magicq_state(PATHS, COMMANDS),
        }
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = {name: executor.submit(task) for name, task in tasks.items()}
            for name, future in futures.items():
                try:
                    value = future.result()
                    if name == "stato":
                        status = value
                    elif name == "plugins":
                        plugins = value
                    else:
                        magicq = value
                except Exception as error:
                    errors.append(f"{name}: {error}")
        GLib.idle_add(self.apply_refresh, status, plugins, magicq, "; ".join(errors))

    def refresh_all(self):
        if self.refresh_running or self.destroyed:
            return
        self.refresh_running = True
        threading.Thread(target=self.refresh_worker, daemon=True).start()

    def periodic_refresh(self):
        if self.destroyed:
            return False
        self.refresh_all()
        return True

    def run_desktop_command(self, _button, command):
        try:
            COMMANDS.spawn(command)
        except OSError as error:
            self.show_error("Impossibile avviare il comando", str(error))

    def launch_application(self, _button, item):
        command = FIELD_CODE.sub("", item.command)
        try:
            arguments = shlex.split(command)
            executable = os.path.basename(arguments[0]) if arguments else ""
            companion = {"runmagichd.sh": "magichd", "mqhd": "magichd",
                         "runmagicvis.sh": "magicvis", "mqvis": "magicvis"}.get(executable)
            if companion:
                arguments = ["sudo", "-n", PATHS.companion_launcher, companion]
            if item.terminal:
                arguments = ["lxterminal", "-e"] + arguments
            COMMANDS.spawn(arguments, cwd=item.working_directory)
        except (OSError, ValueError) as error:
            self.show_error("Impossibile avviare l'applicazione", str(error))

    def plugin_action(self, _button, item, action):
        if action["confirm"]:
            dialog = Gtk.MessageDialog(
                transient_for=self, modal=True, destroy_with_parent=True,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.OK_CANCEL, text=action["confirm"])
            prepare_dialog(dialog, self)
            accepted = dialog.run() == Gtk.ResponseType.OK
            dialog.destroy()
            if not accepted:
                return
        self.background_command(
            [PLUGIN_COMMAND, "action", item["id"], action["id"]],
            f"{item['name']} · {action['label']}")

    def plugin_control_changed(self, switch, desired, item, control):
        action_id = control["on_action"] if desired else control["off_action"]
        switch.set_sensitive(False)
        self.background_command(
            [PLUGIN_COMMAND, "action", item["id"], action_id],
            f"{item['name']} · {control['label']}",
            lambda success: switch.set_sensitive(True))
        return True

    def magicq_auto_changed(self, switch, desired):
        switch.set_sensitive(False)
        operation = "enable" if desired else "disable"
        self.background_command(
            ["sudo", "-n", PATHS.remote_persistence, "magicq", operation],
            "MagicQ · Avvio automatico",
            lambda success: switch.set_sensitive(True))
        return True

    def change_plugin_state(self, _button, item, enable):
        identity = mode_and_version(PATHS, COMMANDS)
        if identity.mode != "MAINTENANCE":
            self.show_error("Modalità MAINTENANCE richiesta",
                            "Riavvia in MAINTENANCE per abilitare o disabilitare plugin persistenti.")
            return
        operation = "enable" if enable else "disable"
        operation_title = "Abilita" if enable else "Disabilita"
        self.background_command([PLUGIN_COMMAND, operation, item["id"]],
                                f"{operation_title} {item['name']}")

    def install_plugin(self, _button, item):
        identity = mode_and_version(PATHS, COMMANDS)
        if identity.mode != "MAINTENANCE":
            self.show_error("Modalità MAINTENANCE richiesta",
                            "Riavvia in MAINTENANCE per installare un plugin.")
            return
        try:
            COMMANDS.spawn([PLUGIN_COMMAND, "install", item["id"]])
        except OSError as error:
            self.show_error("Impossibile avviare l'installazione del plugin", str(error))

    def background_command(self, command, title, callback=None):
        def worker():
            try:
                result = COMMANDS.run(command, timeout=120, merge_stderr=True)
                GLib.idle_add(self.command_finished, result.returncode, title,
                              result.stdout, callback)
            except Exception as error:
                GLib.idle_add(self.command_finished, 1, title, str(error), callback)
        threading.Thread(target=worker, daemon=True).start()

    def command_finished(self, returncode, title, output, callback=None):
        if returncode:
            self.show_error(title, output.strip() or "Operazione non riuscita")
        if callback:
            callback(returncode == 0)
        self.refresh_all()
        return False

    def show_error(self, title, details):
        dialog = Gtk.MessageDialog(
            transient_for=self, modal=True, destroy_with_parent=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.CLOSE, text=title)
        dialog.format_secondary_text(details)
        prepare_dialog(dialog, self)
        dialog.run()
        dialog.destroy()


CSS = b"""
window { background-color: #080b10; color: #e6edf3; }
button {
    min-height: 44px; font-size: 15px; padding: 8px;
    background: #171c23; color: #e6edf3;
    border: 1px solid #343d48; border-radius: 7px;
}
button:hover { background: #223016; color: #f0f7e8; border-color: #76bd22; }
button:focus { border-color: #76bd22; box-shadow: inset 0 0 0 1px #76bd22; }
button:active { background: #76bd22; color: #080b10; }
switch {
    min-width: 64px; min-height: 32px;
    background: #303842; border: 1px solid #4b5563; border-radius: 18px;
}
switch:checked { background: #76bd22; border-color: #9bd95a; }
switch slider {
    min-width: 28px; min-height: 28px;
    background: #e6edf3; border-radius: 15px;
}
notebook, notebook > stack, scrolledwindow, viewport, flowbox {
    background: #0d1117; color: #e6edf3;
}
notebook > header { background: #11151b; border-bottom: 1px solid #303842; }
notebook > header tab {
    min-height: 38px; padding: 8px 20px; font-size: 15px;
    background: #151a21; color: #aeb7c2; border: 0;
}
notebook > header tab:hover { background: #202832; color: #e6edf3; }
notebook > header tab:checked {
    background: #223016; color: #9bd95a;
    border-bottom: 3px solid #76bd22;
}
frame { background: #11151b; border: 1px solid #303842; border-radius: 7px; }
textview, textview text { background: #0d1117; color: #e6edf3; font-size: 14px; }
.section-subtitle { color: #aeb7c2; font-size: 13px; }
.card-description { color: #aeb7c2; font-size: 13px; }
"""


css = Gtk.CssProvider()
css.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = ControlCenter()
window.show_all()
Gtk.main()
