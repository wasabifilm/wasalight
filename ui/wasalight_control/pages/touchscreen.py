# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Touch-friendly touchscreen mapping and visual verification."""

import threading

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

from ..commands import CommandRunner
from ..i18n import _
from ..widgets import section_heading
from .common import scroll_page


class TouchTestWindow(Gtk.Window):
    def __init__(self, parent):
        super().__init__(title=_("Touchscreen test"), transient_for=parent,
                         modal=True, destroy_with_parent=True)
        self.fullscreen()
        grid = Gtk.Grid(row_spacing=24, column_spacing=24)
        grid.set_border_width(36)
        self.add(grid)
        for label, column, row in (("1", 0, 0), ("2", 2, 0),
                                   ("3", 0, 2), ("4", 2, 2)):
            button = Gtk.Button(label=label)
            button.set_size_request(150, 110)
            button.connect("clicked", self._mark_target)
            grid.attach(button, column, row, 1, 1)
        message = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        title = Gtk.Label(label=_("Touch all four corners"))
        title.get_style_context().add_class("overview-title")
        detail = Gtk.Label(label=_(
            "Each numbered target turns green when it receives a touch."))
        close = Gtk.Button(label=_("Close test"))
        close.get_style_context().add_class("close-button")
        close.connect("clicked", lambda _button: self.destroy())
        message.pack_start(title, False, False, 0)
        message.pack_start(detail, False, False, 0)
        message.pack_start(close, False, False, 0)
        grid.attach(message, 1, 1, 1, 1)
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)

    @staticmethod
    def _mark_target(button):
        button.get_style_context().add_class("primary-button")
        button.set_sensitive(False)


class TouchscreenPage:
    ROTATIONS = (
        ("normal", "0°"), ("right", "90°"),
        ("inverted", "180°"), ("left", "270°"),
    )

    def __init__(self, parent, show_error, runner=None):
        self.parent = parent
        self.show_error = show_error
        self.runner = runner or CommandRunner()
        self.loading = False
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Touchscreen"),
            _("Detect, associate and rotate touchscreens without using the terminal.")),
            False, False, 0)

        self.status = Gtk.Label(label=_("Reading touchscreen state…"))
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        self.status.get_style_context().add_class("section-subtitle")
        page.pack_start(self.status, False, False, 0)

        form = Gtk.Grid(row_spacing=12, column_spacing=14)
        form.set_hexpand(True)
        self.mode = Gtk.ComboBoxText()
        self.mode.append("auto", _("Automatic"))
        self.mode.append("manual", _("Manual association"))
        self.mode.append("disabled", _("Disabled"))
        self.mode.connect("changed", self._mode_changed)
        self.device = Gtk.ComboBoxText()
        self.output = Gtk.ComboBoxText()
        self.rotation = Gtk.ComboBoxText()
        for value, label in self.ROTATIONS:
            self.rotation.append(value, label)
        self.rotation.set_active_id("normal")
        for row, (label, widget) in enumerate((
                (_("Mode"), self.mode), (_("Touch device"), self.device),
                (_("Display"), self.output), (_("Rotation"), self.rotation))):
            text = Gtk.Label(label=label)
            text.set_xalign(0)
            form.attach(text, 0, row, 1, 1)
            form.attach(widget, 1, row, 1, 1)
        page.pack_start(form, False, False, 0)

        actions = Gtk.Box(spacing=10)
        refresh = Gtk.Button(label=_("Refresh"))
        refresh.connect("clicked", lambda _button: self.refresh())
        apply = Gtk.Button(label=_("Apply"))
        apply.get_style_context().add_class("primary-button")
        apply.connect("clicked", self._apply)
        test = Gtk.Button(label=_("Full-screen touch test"))
        test.connect("clicked", self._test)
        actions.pack_start(refresh, False, False, 0)
        actions.pack_start(apply, False, False, 0)
        actions.pack_start(test, False, False, 0)
        page.pack_start(actions, False, False, 0)
        self.widget = scroll_page(page)
        self.refresh()

    def _mode_changed(self, _chooser):
        manual = self.mode.get_active_id() == "manual"
        self.device.set_sensitive(manual)
        self.output.set_sensitive(manual)

    def refresh(self):
        if self.loading:
            return
        self.loading = True
        threading.Thread(target=self._refresh_worker, daemon=True).start()

    def _refresh_worker(self):
        try:
            result = self.runner.run(
                ["/usr/local/bin/wasalight-touch", "status", "--machine"],
                timeout=10, merge_stderr=True)
            GLib.idle_add(self._apply_state, result.returncode, result.stdout)
        except Exception as error:
            GLib.idle_add(self._apply_state, 1, str(error))

    def _apply_state(self, returncode, output):
        self.loading = False
        if returncode:
            self.status.set_text(output.strip() or _("Touchscreen state unavailable"))
            return False
        config = {"mode": "auto", "rotation": "normal", "device": "", "output": ""}
        devices = []
        outputs = []
        for line in output.splitlines():
            fields = line.split("\t")
            if fields[0] == "CONFIG" and len(fields) >= 5:
                config.update(zip(("mode", "rotation", "device", "output"), fields[1:5]))
            elif fields[0] == "TOUCH" and len(fields) >= 2:
                devices.append(fields[1])
            elif fields[0] == "OUTPUT" and len(fields) >= 2:
                outputs.append(fields[1])
        self.device.remove_all()
        self.output.remove_all()
        for value in devices:
            self.device.append(value, value)
        for value in outputs:
            self.output.append(value, value)
        self.mode.set_active_id(config["mode"])
        self.rotation.set_active_id(config["rotation"])
        if config["device"]:
            self.device.set_active_id(config["device"])
        elif devices:
            self.device.set_active(0)
        if config["output"]:
            self.output.set_active_id(config["output"])
        elif outputs:
            self.output.set_active(0)
        self.status.set_text(_("{touches} touchscreen(s), {outputs} display(s) detected").format(
            touches=len(devices), outputs=len(outputs)))
        self._mode_changed(self.mode)
        return False

    def _apply(self, _button):
        mode = self.mode.get_active_id() or "auto"
        rotation = self.rotation.get_active_id() or "normal"
        command = ["/usr/local/bin/wasalight-touch-config"]
        if mode == "disabled":
            command.append("disable")
        elif mode == "auto":
            command.extend(("auto", rotation))
        else:
            device = self.device.get_active_id()
            output = self.output.get_active_id()
            if not device or not output:
                self.show_error(_("Touchscreen association incomplete"),
                                _("Select both a touch device and a display."))
                return
            command.extend(("set", device, output, rotation))
        threading.Thread(target=self._apply_worker, args=(command,), daemon=True).start()

    def _apply_worker(self, command):
        result = self.runner.run(command, timeout=15, merge_stderr=True)
        GLib.idle_add(self._apply_finished, result.returncode, result.stdout)

    def _apply_finished(self, returncode, output):
        if returncode:
            self.show_error(_("Unable to configure touchscreen"),
                            output.strip() or _("Operation failed"))
        self.refresh()
        return False

    def _test(self, _button):
        window = TouchTestWindow(self.parent)
        window.show_all()
        window.present()
