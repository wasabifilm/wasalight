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


class Monitor(Gtk.Window):
    def __init__(self):
        super().__init__(title="Wasalight OSC Monitor")
        self.set_default_size(1100, 580)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.process = None
        self.rows = {}
        self.connect("destroy", self.close)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(16)
        title = Gtk.Label()
        title.set_markup(_("<span size='18000' weight='bold'>OSC Monitor</span>\n"
                           "<span size='10000'>Passive OSC traffic monitor on all interfaces</span>"))
        title.set_xalign(0)
        box.pack_start(title, False, False, 0)

        self.store = Gtk.ListStore(str, int, str, str, int, str)
        view = Gtk.TreeView(model=self.store)
        labels = (_("Source"), _("Port"), _("OSC path"), _("Arguments"),
                  _("Messages"), _("Last seen"))
        for index, label in enumerate(labels):
            renderer = Gtk.CellRendererText()
            renderer.set_property("ypad", 8)
            column = Gtk.TreeViewColumn(label, renderer, text=index)
            column.set_resizable(True)
            column.set_expand(index in (0, 2, 3))
            view.append_column(column)
        scroll = Gtk.ScrolledWindow()
        scroll.add(view)
        box.pack_start(scroll, True, True, 0)

        controls = Gtk.Box(spacing=10)
        self.status = Gtk.Label(label=_("Listening passively without binding UDP ports"))
        self.status.set_xalign(0)
        clear = Gtk.Button(label=_("Clear"))
        clear.set_size_request(150, 58)
        clear.connect("clicked", self.clear)
        close = Gtk.Button(label=_("Close"))
        close.set_size_request(150, 58)
        close.connect("clicked", lambda _button: self.destroy())
        controls.pack_start(self.status, True, True, 0)
        controls.pack_start(clear, False, False, 0)
        controls.pack_start(close, False, False, 0)
        box.pack_start(controls, False, False, 0)
        self.add(box)
        self.start_capture()

    def start_capture(self):
        try:
            self.process = subprocess.Popen(
                ["sudo", "-n", "/usr/local/sbin/wasalight-artnet-capture"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
            threading.Thread(target=self.read_packets, daemon=True).start()
        except Exception as error:
            self.status.set_text(str(error))

    def read_packets(self):
        for line in self.process.stdout:
            fields = line.rstrip().split("\t")
            if len(fields) == 8 and fields[0] == "OSC":
                GLib.idle_add(self.add_packet, *fields[1:])
        error = self.process.stderr.read().strip()
        if error:
            GLib.idle_add(self.status.set_text, error)

    def add_packet(self, timestamp, source, source_port, _destination,
                   destination_port, path, arguments):
        key = (source, destination_port, path, arguments)
        if key in self.rows:
            row = self.rows[key]
            self.store[row][4] += 1
            self.store[row][5] = timestamp
        else:
            self.rows[key] = self.store.append(
                [source, int(destination_port), path, arguments, 1, timestamp])
        self.status.set_text(_("Last packet from {source}:{port}").format(
            source=source, port=source_port))
        return False

    def clear(self, _button):
        self.store.clear()
        self.rows.clear()

    def close(self, _window):
        if self.process and self.process.poll() is None:
            self.process.terminate()
        Gtk.main_quit()


css = Gtk.CssProvider()
css.load_from_data(b"button { font-size: 15px; padding: 10px; } treeview { font-size: 14px; }")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
window = Monitor()
window.show_all()
Gtk.main()
