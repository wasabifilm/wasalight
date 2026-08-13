"""Reusable GTK widgets for Wasalight Control."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import os

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib, Gtk

from .i18n import _

CARD_WIDTH = 290
CARD_HEIGHT = 224


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
    dialog.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
    dialog.set_keep_above(True)
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
    shown_state = _(item["state_label"]) if item["installed"] else _("Not installed")
    if item["installed"] and not item["compatible"]:
        shown_state = _("Requires Wasalight {version}").format(
            version=item["minimum_wasalight"])
    title.set_markup(
        f"<span size='13000' weight='bold'>{GLib.markup_escape_text(_(item['name']))}</span>")
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
    heading.pack_start(heading_text, True, True, 0)
    box.pack_start(heading, False, False, 0)
    description = Gtk.Label(label=_(item["description"]))
    description.set_xalign(0)
    description.set_line_wrap(True)
    box.pack_start(description, True, True, 0)
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
                button = Gtk.Button(label=_(action["label"]))
                button.set_sensitive(action["available"])
                button.connect("clicked", run_action, item, action)
                add_action(button)
    elif item["enabled"] and item["installed"] and item["compatible"]:
        for control in item.get("controls", []):
            switch = Gtk.Switch()
            switch.set_active(control["checked"])
            switch.set_sensitive(control["available"])
            switch.connect("state-set", control_changed, item, control)
            add_action(toggle_row(_(control["label"]), switch), True)
        for action in item["actions"]:
            if action["management"] or action.get("control"):
                continue
            button = Gtk.Button(label=_(action["label"]))
            button.get_style_context().add_class("secondary-button")
            button.set_sensitive(action["available"])
            button.connect("clicked", run_action, item, action)
            add_action(button)
    if not item["enabled"] and not management:
        add_action(Gtk.Label(label=_("Plugin disabled")), True)
    box.pack_start(actions, False, False, 0)
    frame.add(box)
    return frame
