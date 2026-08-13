#!/usr/bin/env python3
"""Touch-first unified Wasalight desktop management interface."""

import concurrent.futures
import os
import re
import shlex
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

from wasalight_control.commands import CommandRunner
from wasalight_control.i18n import _, configure, save_language
from wasalight_control.launchers import installed_launchers
from wasalight_control.models import ControlPaths
from wasalight_control.overview_state import parse_status_report
from wasalight_control.pages import (
    AboutPage, ApplicationsPage, MaintenancePage, OverviewPage, SystemPage,
    ToolsPage,
)
from wasalight_control.shell import ApplicationShell
from wasalight_control.system import magicq_state, mode_and_version, read_plugins, read_status
from wasalight_control.style import install_style
from wasalight_control.widgets import (
    clear_flow, plugin_card, prepare_dialog,
)

PATHS = ControlPaths()
COMMANDS = CommandRunner()
configure(language_file=PATHS.control_language_file, locale_dir=PATHS.locale_dir)
PLUGIN_COMMAND = PATHS.plugin_command
FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")
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
        launchers = installed_launchers(PATHS)
        identity = mode_and_version(PATHS, COMMANDS)
        self.overview_page = OverviewPage(
            identity, PATHS, self.run_desktop_command, self.navigate_to)
        self.applications_page = ApplicationsPage(
            launchers, PATHS, self.run_desktop_command,
            self.launch_application, self.magicq_auto_changed)
        self.system_page = SystemPage(self.language_saved)
        self.tools_page = ToolsPage(launchers, self.launch_application)
        self.maintenance_page = MaintenancePage()
        self.about_page = AboutPage(identity)
        pages = (
            ("overview", _("Overview"), self.overview_page),
            ("applications", _("Applications"), self.applications_page.widget),
            ("system", _("System"), self.system_page.widget),
            ("tools", _("Tools"), self.tools_page.widget),
            ("maintenance", _("Maintenance"), self.maintenance_page.widget),
            ("about", _("About"), self.about_page.widget),
        )
        self.shell = ApplicationShell(identity, pages, self.destroy)
        self.add(self.shell)
        self.refresh_all()
        GLib.timeout_add_seconds(3, self.periodic_refresh)

    def on_destroy(self, _window):
        self.destroyed = True
        Gtk.main_quit()

    def navigate_to(self, page_id):
        if hasattr(self, "shell"):
            self.shell.show_page(page_id)

    def apply_refresh(self, status, plugins, magicq, error):
        self.refresh_running = False
        if self.destroyed:
            return False
        if error:
            status = _("{status}\n\nCONTROL:    refresh warning: {error}").format(
                status=status, error=error)
        self.overview_page.set_snapshot(parse_status_report(status, magicq))
        if magicq is not None:
            self.applications_page.set_magicq_state(magicq)
        if plugins is not None and plugins != self.plugins:
            self.plugins = plugins
            clear_flow(self.system_page.service_cards)
            clear_flow(self.maintenance_page.plugin_cards)
            for item in self.plugins:
                if item["category"] == "Services" and item["enabled"]:
                    self.system_page.service_cards.add(self.make_plugin_card(item))
                if item["optional"]:
                    self.maintenance_page.plugin_cards.add(
                        self.make_plugin_card(item, management=True))
            self.system_page.service_cards.show_all()
            self.maintenance_page.plugin_cards.show_all()
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
        status = _("Status unavailable")
        plugins = None
        magicq = None
        errors = []
        # These probes are independent. Running them concurrently prevents a
        # slow XInput scan from consuming the whole Control refresh budget.
        tasks = {
            "status": (_("status"), lambda: read_status(PATHS, COMMANDS)),
            "plugins": (_("plugins"), lambda: read_plugins(PATHS, COMMANDS)),
            "magicq": ("MagicQ", lambda: magicq_state(PATHS, COMMANDS)),
        }
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            futures = {task_id: executor.submit(task) for task_id, (_label, task)
                       in tasks.items()}
            for task_id, future in futures.items():
                try:
                    value = future.result()
                    if task_id == "status":
                        status = value
                    elif task_id == "plugins":
                        plugins = value
                    else:
                        magicq = value
                except Exception as error:
                    errors.append(f"{tasks[task_id][0]}: {error}")
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
            self.show_error(_("Unable to start command"), str(error))

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
            self.show_error(_("Unable to start application"), str(error))

    def plugin_action(self, _button, item, action):
        if action["confirm"]:
            dialog = Gtk.MessageDialog(
                transient_for=self, modal=True, destroy_with_parent=True,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.OK_CANCEL, text=_(action["confirm"]))
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
            _("MagicQ · Automatic startup"),
            lambda success: switch.set_sensitive(True))
        return True

    def language_saved(self, _button, chooser):
        language = chooser.get_active_id() or "auto"
        try:
            save_language(language, language_file=PATHS.control_language_file)
        except (OSError, ValueError) as error:
            self.show_error(_("Unable to save language"), str(error))
            return
        dialog = Gtk.MessageDialog(
            transient_for=self, modal=True, destroy_with_parent=True,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.CLOSE,
            text=_("Language saved"))
        dialog.format_secondary_text(
            _("The new language will be used the next time Wasalight Control starts."))
        prepare_dialog(dialog, self)
        dialog.run()
        dialog.destroy()

    def change_plugin_state(self, _button, item, enable):
        identity = mode_and_version(PATHS, COMMANDS)
        if identity.mode != "MAINTENANCE":
            self.show_error(_("MAINTENANCE mode required"),
                            _("Restart in MAINTENANCE to enable or disable persistent plugins."))
            return
        operation = "enable" if enable else "disable"
        operation_title = _("Enable") if enable else _("Disable")
        self.background_command([PLUGIN_COMMAND, operation, item["id"]],
                                f"{operation_title} {item['name']}")

    def install_plugin(self, _button, item):
        identity = mode_and_version(PATHS, COMMANDS)
        if identity.mode != "MAINTENANCE":
            self.show_error(_("MAINTENANCE mode required"),
                            _("Restart in MAINTENANCE to install a plugin."))
            return
        try:
            COMMANDS.spawn([PLUGIN_COMMAND, "install", item["id"]])
        except OSError as error:
            self.show_error(_("Unable to start plugin installation"), str(error))

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
            self.show_error(title, output.strip() or _("Operation failed"))
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


install_style()
window = ControlCenter()
window.show_all()
Gtk.main()
