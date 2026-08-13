# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""MagicQ and registered application launchers."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import card_flow, section_heading, software_button
from .common import launcher_flow, scroll_page


class ApplicationsPage:
    def __init__(self, launchers, paths, run_command, launch_application):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            "MagicQ", _("Lighting console and ChamSys companion applications.")),
            False, False, 0)

        magicq_flow = card_flow()
        magicq = software_button(
            "MagicQ", _("Main lighting console"),
            "/usr/share/pixmaps/magicq.png",
            lambda button: run_command(button, [paths.magicq_start]))
        magicq.set_sensitive(os.path.exists("/opt/magicq"))
        magicq_flow.add(magicq)
        for item in (item for item in launchers if item.section == "MagicQ"):
            magicq_flow.add(software_button(
                item.name, item.comment or _("ChamSys application"), item.icon,
                lambda button, selected=item: launch_application(button, selected)))
        page.pack_start(magicq_flow, False, False, 0)
        page.pack_start(section_heading(
            _("Other applications"), _("Programs registered with Wasalight.")),
            False, False, 0)
        page.pack_start(
            launcher_flow("Applications", launchers, launch_application),
            False, False, 0)
        self.widget = scroll_page(page)
