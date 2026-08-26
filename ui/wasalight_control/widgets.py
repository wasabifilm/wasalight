# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Reusable GTK widgets for Wasalight Control."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import os

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, GObject, Gtk

from .i18n import _

CARD_WIDTH = 290
CARD_HEIGHT = 224


class TouchChoice(Gtk.Button):
    """Large button opening a modal list that is reliable on touchscreens."""

    __gsignals__ = {
        "changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self, parent, title):
        super().__init__()
        self.parent = parent
        self.title = title
        self.items = []
        self.active_index = -1
        self.set_hexpand(True)
        self.set_halign(Gtk.Align.FILL)
        self.get_style_context().add_class("touch-choice")
        self.connect("clicked", self._choose)
        self._update_label()

    def append(self, item_id, label):
        self.items.append((item_id, label))
        if self.active_index < 0:
            self.active_index = 0
            self._update_label()

    def remove_all(self):
        self.items.clear()
        self.active_index = -1
        self._update_label()

    def get_active(self):
        return self.active_index

    def set_active(self, index):
        if not 0 <= index < len(self.items):
            return
        changed = index != self.active_index
        self.active_index = index
        self._update_label()
        if changed:
            self.emit("changed")

    def get_active_id(self):
        if not 0 <= self.active_index < len(self.items):
            return None
        return self.items[self.active_index][0]

    def set_active_id(self, item_id):
        for index, (candidate, _label) in enumerate(self.items):
            if candidate == item_id:
                self.set_active(index)
                return True
        return False

    def _update_label(self):
        label = self.items[self.active_index][1] \
            if 0 <= self.active_index < len(self.items) else _("Choose…")
        self.set_label(f"{label}  ▾")

    def _choose(self, _button):
        dialog = Gtk.Dialog(
            title=self.title, transient_for=self.parent, modal=True,
            destroy_with_parent=True)
        dialog.set_default_size(620, min(640, 150 + 64 * len(self.items)))
        dialog.add_button(_("Cancel"), Gtk.ResponseType.CANCEL)
        content = dialog.get_content_area()
        content.set_border_width(16)
        content.set_spacing(10)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        choices = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        for index, (_item_id, label) in enumerate(self.items):
            choice = Gtk.Button(label=label)
            choice.set_size_request(-1, 56)
            choice.set_hexpand(True)
            if index == self.active_index:
                choice.get_style_context().add_class("primary-button")
            choice.connect(
                "clicked", lambda _choice, selected=index:
                dialog.response(selected + 1))
            choices.pack_start(choice, False, False, 0)
        scroller.add(choices)
        content.pack_start(scroller, True, True, 0)
        dialog.show_all()
        prepare_dialog(dialog, self.parent)
        response = dialog.run()
        dialog.destroy()
        if 1 <= response <= len(self.items):
            self.set_active(response - 1)


def image_for(icon, size=64):
    if os.path.isabs(icon) and os.path.isfile(icon):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon, size, size, True)
            return Gtk.Image.new_from_pixbuf(pixbuf)
        except Exception:
            pass
    if os.path.basename(icon) == "companion-official.png":
        fallback = "/usr/local/share/icons/wasalight/companion.svg"
        if os.path.isfile(fallback):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                    fallback, size, size, True)
                return Gtk.Image.new_from_pixbuf(pixbuf)
            except Exception:
                pass
    if os.path.isabs(icon):
        icon = "application-x-executable"
    image = Gtk.Image.new_from_icon_name(
        icon or "application-x-executable", Gtk.IconSize.DIALOG)
    image.set_pixel_size(size)
    return image


def section_heading(title, subtitle):
    heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
    title_label = Gtk.Label()
    title_label.set_xalign(0)
    title_label.set_markup(
        f"<span size='16000' weight='bold'>{GLib.markup_escape_text(title)}</span>")
    title_label.get_style_context().add_class("technical-label")
    subtitle_label = Gtk.Label(label=subtitle)
    subtitle_label.set_xalign(0)
    subtitle_label.set_line_wrap(True)
    subtitle_label.get_style_context().add_class("section-subtitle")
    heading.pack_start(title_label, False, False, 0)
    heading.pack_start(subtitle_label, False, False, 0)
    return heading


def card_flow():
    flow = Gtk.FlowBox()
    flow.set_selection_mode(Gtk.SelectionMode.NONE)
    flow.set_row_spacing(14)
    flow.set_column_spacing(14)
    flow.set_min_children_per_line(1)
    flow.set_max_children_per_line(3)
    flow.set_homogeneous(True)
    flow.set_halign(Gtk.Align.CENTER)
    return flow


def software_button(name, comment, icon, callback):
    button = Gtk.Button()
    button.get_style_context().add_class("software-tile")
    button.set_size_request(CARD_WIDTH, CARD_HEIGHT)
    button.set_tooltip_text(comment)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    content.set_border_width(14)
    content.pack_start(image_for(icon, 72), True, True, 0)
    label = Gtk.Label()
    label.set_markup(
        f"<span size='14000' weight='bold'>{GLib.markup_escape_text(name)}</span>")
    label.set_line_wrap(True)
    label.set_justify(Gtk.Justification.CENTER)
    content.pack_start(label, False, False, 0)
    description = Gtk.Label(label=comment)
    description.set_line_wrap(True)
    description.set_justify(Gtk.Justification.CENTER)
    description.get_style_context().add_class("card-description")
    content.pack_start(description, False, False, 0)
    button.add(content)
    button.connect("clicked", callback)
    return button


def toggle_row(label, switch):
    row = Gtk.Box(spacing=12)
    row.get_style_context().add_class("control-row")
    text = Gtk.Label(label=label)
    text.set_xalign(0)
    row.pack_start(text, True, True, 0)
    row.pack_start(switch, False, False, 0)
    return row


def clear_flow(flow):
    for child in flow.get_children():
        flow.remove(child)


def prepare_dialog(dialog, parent):
    dialog.set_transient_for(parent)
    dialog.set_modal(True)
    dialog.set_destroy_with_parent(True)
    dialog.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
    dialog.set_type_hint(Gdk.WindowTypeHint.DIALOG)
    dialog.set_skip_taskbar_hint(True)
    dialog.set_keep_above(True)
    dialog.set_urgency_hint(True)
    dialog.present()


def plugin_card(item, *, management, change_state, install, run_action,
                control_changed):
    frame = Gtk.Frame()
    frame.get_style_context().add_class("flat-card")
    frame.set_size_request(CARD_WIDTH, CARD_HEIGHT if not management else 300)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
    box.set_border_width(12)
    heading = Gtk.Box(spacing=10)
    heading.pack_start(image_for(item["icon"], 48), False, False, 0)
    heading_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=5)
    title = Gtk.Label()
    title.set_xalign(0)
    title.set_line_wrap(True)
    shown_state = item["state_label"] if item["installed"] else _("Not installed")
    if item["installed"] and not item["compatible"]:
        shown_state = _("Requires Wasalight {version}").format(
            version=item["minimum_wasalight"])
    title.set_markup(
        f"<span size='13000' weight='bold'>{GLib.markup_escape_text(item['name'])}</span>")
    state = Gtk.Label(label=f"●  {shown_state}")
    state.set_xalign(0)
    state.get_style_context().add_class("status-pill")
    if not item["installed"] or not item["compatible"]:
        state.get_style_context().add_class("status-error")
    elif item["active"]:
        state.get_style_context().add_class("status-good")
    else:
        state.get_style_context().add_class("status-neutral")
    heading_text.pack_start(title, False, False, 0)
    heading_text.pack_start(state, False, False, 0)
    if not management and item.get("endpoint"):
        endpoint = Gtk.Label(label=_("Address: {endpoint}").format(
            endpoint=item["endpoint"]))
        endpoint.set_xalign(0)
        endpoint.get_style_context().add_class("section-subtitle")
        heading_text.pack_start(endpoint, False, False, 0)
    heading.pack_start(heading_text, True, True, 0)
    box.pack_start(heading, False, False, 0)
    description = Gtk.Label(label=item["description"])
    description.set_xalign(0)
    description.set_line_wrap(True)
    box.pack_start(description, True, True, 0)
    if management and item.get("installed_version"):
        version = Gtk.Label(label=_("Installed version: {version}").format(
            version=item["installed_version"]))
        version.set_xalign(0)
        version.get_style_context().add_class("section-subtitle")
        box.pack_start(version, False, False, 0)
    actions = Gtk.Grid()
    actions.set_row_spacing(7)
    actions.set_column_spacing(7)
    action_row = 0
    action_column = 0

    def add_action(widget, full_width=False):
        nonlocal action_row, action_column
        widget.set_hexpand(True)
        if isinstance(widget, Gtk.Button):
            widget.set_size_request(-1, 46)
        if full_width:
            if action_column:
                action_row += 1
                action_column = 0
            actions.attach(widget, 0, action_row, 2, 1)
            action_row += 1
            return
        actions.attach(widget, action_column, action_row, 1, 1)
        action_column += 1
        if action_column == 2:
            action_row += 1
            action_column = 0

    if management:
        label = _("Install with Update") if not item["installed"] else (
            _("Disable") if item["enabled"] else _("Enable"))
        button = Gtk.Button(label=label)
        button.get_style_context().add_class("primary-button")
        if item["installed"]:
            button.set_sensitive(item["compatible"] or item["enabled"])
            button.connect("clicked", change_state, item, not item["enabled"])
        else:
            button.connect("clicked", install, item)
        add_action(button, True)
        if item["installed"] and item["enabled"]:
            for action in item["actions"]:
                if not action["management"]:
                    continue
                button = Gtk.Button(label=action["label"])
                button.set_sensitive(action["available"])
                button.connect("clicked", run_action, item, action)
                add_action(button)
    elif item["enabled"] and item["installed"] and item["compatible"]:
        for control in item.get("controls", []):
            switch = Gtk.Switch()
            switch.set_active(control["checked"])
            switch.set_sensitive(control["available"])
            switch.connect("state-set", control_changed, item, control)
            add_action(toggle_row(control["label"], switch), True)
        for action in item["actions"]:
            if action["management"] or action.get("control"):
                continue
            button = Gtk.Button(label=action["label"])
            button.get_style_context().add_class("secondary-button")
            button.set_sensitive(action["available"])
            button.connect("clicked", run_action, item, action)
            add_action(button)
    if not item["enabled"] and not management:
        add_action(Gtk.Label(label=_("Plugin disabled")), True)
    box.pack_start(actions, False, False, 0)
    frame.add(box)
    return frame
