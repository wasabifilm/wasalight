#!/usr/bin/env python3
"""Touch-first unified Wasalight desktop management interface."""

import configparser
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk


PLUGIN_COMMAND = "/usr/local/bin/wasalight-plugin"
FIELD_CODE = re.compile(r"%[fFuUdDnNickvm]")
COMPANION = re.compile(r"magicvis|magichd|magicq[ -]?remote|chamsys.*(?:remote|viewer|media)", re.I)


def desktop_bool(item, key, default=False):
    try:
        return item.getboolean(key, fallback=default)
    except ValueError:
        return default


def read_launcher(path, forced_section=None):
    parser = configparser.RawConfigParser(interpolation=None, strict=False)
    try:
        parser.read(path, encoding="utf-8")
        item = parser["Desktop Entry"]
    except (OSError, KeyError, configparser.Error):
        return None
    if item.get("Type", "Application") != "Application":
        return None
    if desktop_bool(item, "Hidden") or desktop_bool(item, "NoDisplay"):
        return None
    name = item.get("Name", "").strip()
    command = item.get("Exec", "").strip()
    try_exec = item.get("TryExec", "").strip()
    if not name or not command:
        return None
    if try_exec and not (os.path.exists(try_exec) if os.path.isabs(try_exec) else shutil.which(try_exec)):
        return None
    section = forced_section or item.get("X-Wasalight-Section", "Applications")
    try:
        order = int(item.get("X-Wasalight-Order", "500"))
    except ValueError:
        order = 500
    return {
        "name": name,
        "comment": item.get("Comment", ""),
        "exec": command,
        "icon": item.get("Icon", "application-x-executable"),
        "terminal": desktop_bool(item, "Terminal"),
        "path": item.get("Path", "").strip() or None,
        "section": section if section in ("MagicQ", "Applications", "Support") else "Applications",
        "order": order,
    }


def installed_launchers():
    result, seen = [], set()
    for pattern in ("/etc/wasalight/apps.d/*.desktop", "/data/system/apps.d/*.desktop"):
        for path in sorted(glob.glob(pattern)):
            launcher = read_launcher(path)
            if launcher and (launcher["name"], launcher["exec"]) not in seen:
                result.append(launcher)
                seen.add((launcher["name"], launcher["exec"]))
    for path in sorted(glob.glob("/usr/share/applications/*.desktop")):
        launcher = read_launcher(path, "MagicQ")
        if not launcher:
            continue
        searchable = " ".join((launcher["name"], launcher["exec"], launcher["comment"]))
        if COMPANION.search(searchable) and (launcher["name"], launcher["exec"]) not in seen:
            result.append(launcher)
            seen.add((launcher["name"], launcher["exec"]))
    return sorted(result, key=lambda value: (value["section"], value["order"], value["name"].lower()))


def image_for(icon, size=64):
    if os.path.isabs(icon) and os.path.isfile(icon):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon, size, size, True)
            return Gtk.Image.new_from_pixbuf(pixbuf)
        except Exception:
            pass
    image = Gtk.Image.new_from_icon_name(icon or "application-x-executable", Gtk.IconSize.DIALOG)
    image.set_pixel_size(size)
    return image


def mode_and_version():
    version = "unknown"
    try:
        with open("/etc/wasalight/version", encoding="utf-8") as source:
            version = source.read().strip()
    except OSError:
        pass
    result = subprocess.run(
        ["findmnt", "-n", "-o", "FSTYPE", "/"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    mode = "SHOW" if result.stdout.strip() == "overlay" else "MAINTENANCE"
    return mode, version


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
        self.connect("destroy", Gtk.main_quit)
        self.plugins = []
        self.plugin_cards = Gtk.FlowBox()
        self.service_cards = Gtk.FlowBox()
        self.status_view = Gtk.TextView()

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_border_width(16)
        outer.pack_start(self.header(), False, False, 0)
        self.notebook = Gtk.Notebook()
        self.notebook.set_scrollable(True)
        outer.pack_start(self.notebook, True, True, 0)
        self.add_dashboard()
        launchers = installed_launchers()
        self.add_launcher_page("MagicQ", launchers)
        self.add_plugin_page("Services", self.service_cards)
        self.add_launcher_page("Applications", launchers)
        self.add_launcher_page("Support", launchers)
        self.add_plugin_page("Plugins", self.plugin_cards)

        footer = Gtk.Box(spacing=10)
        refresh = Gtk.Button(label="Refresh")
        refresh.set_size_request(160, 54)
        refresh.connect("clicked", lambda _button: self.refresh_all())
        close = Gtk.Button(label="Close")
        close.set_size_request(160, 54)
        close.connect("clicked", lambda _button: self.destroy())
        footer.pack_start(Gtk.Label(), True, True, 0)
        footer.pack_start(refresh, False, False, 0)
        footer.pack_start(close, False, False, 0)
        outer.pack_start(footer, False, False, 0)
        self.add(outer)
        self.refresh_all()
        GLib.timeout_add_seconds(3, self.periodic_refresh)

    def header(self):
        mode, version = mode_and_version()
        box = Gtk.Box(spacing=14)
        box.pack_start(image_for("/usr/local/share/icons/wasalight/hub.svg", 58), False, False, 0)
        title = Gtk.Label()
        title.set_xalign(0)
        title.set_markup("<span size='23000' weight='bold'>Wasalight Control</span>\n"
                         "<span size='10500'>MagicQ · services · applications · system</span>")
        box.pack_start(title, True, True, 0)
        state = Gtk.Label()
        colour = "#76bd22" if mode == "SHOW" else "#f2cc60"
        state.set_markup(f"<span foreground='{colour}' weight='bold'>{mode}</span>\n"
                         f"<span size='9500'>Wasalight {GLib.markup_escape_text(version)}</span>")
        state.set_justify(Gtk.Justification.RIGHT)
        box.pack_start(state, False, False, 0)
        return box

    def add_dashboard(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        controls = Gtk.Box(spacing=10)
        for label, command in (
                ("Start MagicQ", ["/usr/local/bin/magicq-start"]),
                ("Stop MagicQ", ["/usr/local/bin/magicq-stop"]),
                ("Update", ["/usr/local/bin/wasalight-update-terminal"]),
                ("Files", ["pcmanfm", "/data"])):
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
        self.notebook.append_page(box, Gtk.Label(label="Dashboard"))

    def add_launcher_page(self, section, launchers):
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
        flow.set_max_children_per_line(5)
        flow.set_min_children_per_line(2)
        items = [item for item in launchers if item["section"] == section]
        if not items:
            empty = Gtk.Label(label="No applications registered")
            empty.set_margin_top(40)
            flow.add(empty)
        for item in items:
            button = Gtk.Button()
            button.set_size_request(180, 132)
            button.set_tooltip_text(item["comment"])
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
            content.pack_start(image_for(item["icon"], 58), True, True, 0)
            label = Gtk.Label(label=item["name"])
            label.set_line_wrap(True)
            label.set_justify(Gtk.Justification.CENTER)
            content.pack_start(label, False, False, 0)
            button.add(content)
            button.connect("clicked", self.launch_application, item)
            flow.add(button)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(flow)
        self.notebook.append_page(scroll, Gtk.Label(label=section))

    def add_plugin_page(self, title, flow):
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_row_spacing(12)
        flow.set_column_spacing(12)
        flow.set_max_children_per_line(3)
        flow.set_min_children_per_line(1)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(flow)
        self.notebook.append_page(scroll, Gtk.Label(label=title))

    def plugin_card(self, item, management=False):
        frame = Gtk.Frame()
        frame.set_size_request(300, 220 if management else 190)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
        box.set_border_width(12)
        heading = Gtk.Box(spacing=10)
        heading.pack_start(image_for(item["icon"], 48), False, False, 0)
        text = Gtk.Label()
        text.set_xalign(0)
        text.set_line_wrap(True)
        colour = "#76bd22" if item["active"] else "#f2cc60"
        if not item["installed"] or not item["compatible"]:
            colour = "#f85149"
        shown_state = item["state_label"] if item["installed"] else "Not installed"
        if item["installed"] and not item["compatible"]:
            shown_state = f"Requires Wasalight {item['minimum_wasalight']}"
        text.set_markup(f"<span size='14500' weight='bold'>{GLib.markup_escape_text(item['name'])}</span>\n"
                        f"<span foreground='{colour}'>{GLib.markup_escape_text(shown_state)}</span>")
        heading.pack_start(text, True, True, 0)
        box.pack_start(heading, False, False, 0)
        description = Gtk.Label(label=item["description"])
        description.set_xalign(0)
        description.set_line_wrap(True)
        box.pack_start(description, True, True, 0)
        actions = Gtk.Box(spacing=7)
        if management:
            label = "Install with Update" if not item["installed"] else (
                "Disable" if item["enabled"] else "Enable")
            button = Gtk.Button(label=label)
            if item["installed"]:
                button.set_sensitive(item["compatible"] or item["enabled"])
                button.connect("clicked", self.change_plugin_state, item, not item["enabled"])
            else:
                button.connect("clicked", self.install_plugin, item)
            actions.pack_start(button, True, True, 0)
        elif item["enabled"] and item["installed"] and item["compatible"]:
            for action in item["actions"]:
                button = Gtk.Button(label=action["label"])
                button.set_sensitive(action["available"])
                button.connect("clicked", self.plugin_action, item, action)
                actions.pack_start(button, True, True, 0)
        if not item["enabled"] and not management:
            actions.pack_start(Gtk.Label(label="Plugin disabled"), True, True, 0)
        box.pack_start(actions, False, False, 0)
        frame.add(box)
        return frame

    @staticmethod
    def clear_flow(flow):
        for child in flow.get_children():
            flow.remove(child)

    def refresh_plugins(self):
        try:
            result = subprocess.run(
                [PLUGIN_COMMAND, "list", "--json"], text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or "Plugin registry unavailable")
            self.plugins = json.loads(result.stdout)
            self.clear_flow(self.service_cards)
            self.clear_flow(self.plugin_cards)
            for item in self.plugins:
                if item["category"] == "Services" and item["enabled"]:
                    self.service_cards.add(self.plugin_card(item))
                self.plugin_cards.add(self.plugin_card(item, management=True))
            self.service_cards.show_all()
            self.plugin_cards.show_all()
        except Exception as error:
            self.show_error("Plugin refresh failed", str(error))

    def refresh_status(self):
        result = subprocess.run(
            ["/usr/local/bin/magicq-status"], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10, check=False)
        self.status_view.get_buffer().set_text(result.stdout.strip() or "Status unavailable")

    def refresh_all(self):
        self.refresh_status()
        self.refresh_plugins()

    def periodic_refresh(self):
        self.refresh_status()
        self.refresh_plugins()
        return True

    def run_desktop_command(self, _button, command):
        try:
            subprocess.Popen(command, start_new_session=True)
        except OSError as error:
            self.show_error("Cannot start command", str(error))

    def launch_application(self, _button, item):
        command = FIELD_CODE.sub("", item["exec"])
        try:
            arguments = shlex.split(command)
            executable = os.path.basename(arguments[0]) if arguments else ""
            companion = {"runmagichd.sh": "magichd", "mqhd": "magichd",
                         "runmagicvis.sh": "magicvis", "mqvis": "magicvis"}.get(executable)
            if companion:
                arguments = ["sudo", "-n", "/usr/local/sbin/wasalight-companion-launcher", companion]
            if item["terminal"]:
                arguments = ["lxterminal", "-e"] + arguments
            subprocess.Popen(arguments, cwd=item["path"], start_new_session=True)
        except (OSError, ValueError) as error:
            self.show_error("Cannot start application", str(error))

    def plugin_action(self, _button, item, action):
        if action["confirm"]:
            dialog = Gtk.MessageDialog(
                self, 0, Gtk.MessageType.QUESTION, Gtk.ButtonsType.OK_CANCEL,
                action["confirm"])
            accepted = dialog.run() == Gtk.ResponseType.OK
            dialog.destroy()
            if not accepted:
                return
        self.background_command(
            [PLUGIN_COMMAND, "action", item["id"], action["id"]],
            f"{item['name']} · {action['label']}")

    def change_plugin_state(self, _button, item, enable):
        mode, _version = mode_and_version()
        if mode != "MAINTENANCE":
            self.show_error("Maintenance required",
                            "Restart in MAINTENANCE mode to enable or disable persistent plugins.")
            return
        operation = "enable" if enable else "disable"
        self.background_command([PLUGIN_COMMAND, operation, item["id"]],
                                f"{operation.title()} {item['name']}")

    def install_plugin(self, _button, item):
        mode, _version = mode_and_version()
        if mode != "MAINTENANCE":
            self.show_error("Maintenance required",
                            "Restart in MAINTENANCE mode to install a plugin.")
            return
        try:
            subprocess.Popen([PLUGIN_COMMAND, "install", item["id"]], start_new_session=True)
        except OSError as error:
            self.show_error("Cannot start plugin installation", str(error))

    def background_command(self, command, title):
        def worker():
            try:
                result = subprocess.run(
                    command, text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=120, check=False)
                GLib.idle_add(self.command_finished, result.returncode, title, result.stdout)
            except Exception as error:
                GLib.idle_add(self.command_finished, 1, title, str(error))
        threading.Thread(target=worker, daemon=True).start()

    def command_finished(self, returncode, title, output):
        if returncode:
            self.show_error(title, output.strip() or "Operation failed")
        self.refresh_all()
        return False

    def show_error(self, title, details):
        dialog = Gtk.MessageDialog(
            self, 0, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, title)
        dialog.format_secondary_text(details)
        dialog.run()
        dialog.destroy()


CSS = b"""
window { background-color: #080b10; color: #f0f3f6; }
button { min-height: 44px; font-size: 17px; padding: 8px; background: #1c222b; color: #f0f3f6; }
button:hover { background: #303842; border-color: #76bd22; }
notebook tab { min-height: 38px; padding: 8px 20px; font-size: 17px; }
frame { background: #11151b; border: 1px solid #303842; border-radius: 7px; }
textview, textview text { background: #11151b; color: #f0f3f6; font-size: 16px; }
"""


css = Gtk.CssProvider()
css.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = ControlCenter()
window.show_all()
Gtk.main()
