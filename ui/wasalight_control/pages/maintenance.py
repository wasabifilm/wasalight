# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Persistent plugin management page."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import section_heading
from .common import scroll_page


class MaintenancePage:
    def __init__(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Optional components"),
            _("Install and manage additional Wasalight components.")),
            False, False, 0)
        self.plugin_cards = Gtk.FlowBox()
        self.plugin_cards.set_selection_mode(Gtk.SelectionMode.NONE)
        self.plugin_cards.set_row_spacing(12)
        self.plugin_cards.set_column_spacing(12)
        self.plugin_cards.set_max_children_per_line(3)
        self.plugin_cards.set_min_children_per_line(1)
        page.pack_start(self.plugin_cards, False, False, 0)
        self.widget = scroll_page(page)
