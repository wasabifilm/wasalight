# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""System and remote services."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import card_flow, section_heading
from .common import scroll_page


class SystemPage:
    def __init__(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Remote access"),
            _("Current state and automatic startup of Wasalight services.")),
            False, False, 0)
        self.service_cards = card_flow()
        page.pack_start(self.service_cards, False, False, 0)
        self.widget = scroll_page(page)
