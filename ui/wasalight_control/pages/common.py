"""Small layout helpers shared by Control pages."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import image_for


def scroll_page(content):
    scroll = Gtk.ScrolledWindow()
    scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scroll.add(content)
    return scroll


def launcher_flow(section, launchers, launch_application):
    flow = Gtk.FlowBox()
    flow.set_selection_mode(Gtk.SelectionMode.NONE)
    flow.set_row_spacing(12)
    flow.set_column_spacing(12)
    flow.set_max_children_per_line(5)
    flow.set_min_children_per_line(2)
    items = [item for item in launchers if item.section == section]
    if not items:
        empty = Gtk.Label(label=_("No applications registered"))
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
        button.connect("clicked", launch_application, item)
        flow.add(button)
    return flow
