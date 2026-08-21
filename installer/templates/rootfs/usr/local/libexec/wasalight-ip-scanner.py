#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
import gettext
import os
import subprocess
import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk

_ = gettext.translation(
    "wasalight-system",
    localedir=os.environ.get("WASALIGHT_LOCALE_DIR", "/usr/local/share/locale"),
    fallback=True,
).gettext
BACKEND_MESSAGES = {
    "No network interface is connected": _("No network interface is connected"),
}


class Scanner(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight IP Scanner")
        self.set_default_size(900, 560)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect("destroy", Gtk.main_quit)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(16)
        title = Gtk.Label()
        title.set_markup(_("<span size='18000' weight='bold'>IP Scanner</span>\n"
                           "<span size='10000'>Reachable devices on the local network</span>"))
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str)
        view = Gtk.TreeView(model=self.store)
        for index, label in enumerate((_("Interface"), _("IP address"), "MAC", _("Vendor"))):
            renderer = Gtk.CellRendererText()
            renderer.set_property("ypad", 9)
            column = Gtk.TreeViewColumn(label, renderer, text=index)
            column.set_resizable(True)
            column.set_expand(index == 3)
            view.append_column(column)
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)

        controls = Gtk.Box(spacing=10)
        self.status = Gtk.Label(label=_("Ready"))
        self.status.set_xalign(0)
        self.scan_button = Gtk.Button(label=_("Scan network"))
        self.scan_button.set_size_request(210, 58)
        self.scan_button.connect("clicked", self.start_scan)
        close = Gtk.Button(label=_("Close"))
        close.set_size_request(150, 58)
        close.connect("clicked", lambda _button: self.destroy())
        controls.pack_start(self.status, True, True, 0)
        controls.pack_start(self.scan_button, False, False, 0)
        controls.pack_start(close, False, False, 0)
        box.pack_start(controls, False, False, 0)
        self.add(box)
        self.start_scan()

    def start_scan(self, _button=None):
        self.store.clear()
        self.status.set_text(_("Scanning…"))
        self.scan_button.set_sensitive(False)
        threading.Thread(target=self.scan_worker, daemon=True).start()

    def scan_worker(self):
        try:
            result = subprocess.run(
                ["sudo", "-n", "/usr/local/sbin/wasalight-ip-scan"],
                text=True, capture_output=True, timeout=60, check=False)
            rows, message = [], ""
            for line in result.stdout.splitlines():
                if line.startswith("!\t"):
                    message = line.split("\t", 1)[1]
                elif not line.startswith("#\t"):
                    fields = line.split("\t", 3)
                    if len(fields) == 4:
                        rows.append(fields)
            if result.returncode and not message:
                message = result.stderr.strip() or _("Scan failed")
            GLib.idle_add(self.finish_scan, rows, message)
        except Exception as error:
            GLib.idle_add(self.finish_scan, [], str(error))

    def finish_scan(self, rows, message):
        for row in rows:
            self.store.append(row)
        self.status.set_text(BACKEND_MESSAGES.get(message, message) if message else
                             _("{count} devices found").format(count=len(rows)))
        self.scan_button.set_sensitive(True)
        return False


css = Gtk.CssProvider()
css.load_from_data(b"button { font-size: 15px; padding: 10px; } treeview { font-size: 14px; }")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(),
    css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = Scanner()
window.show_all()
Gtk.main()
