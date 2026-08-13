"""MagicQ and registered application launchers."""

import os

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import card_flow, section_heading, software_button, toggle_row
from .common import launcher_flow, scroll_page


class ApplicationsPage:
    def __init__(self, launchers, paths, run_command, launch_application,
                 magicq_auto_changed):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Applications"),
            _("MagicQ, ChamSys software and applications registered on the appliance.")),
            False, False, 0)

        status_card = Gtk.Frame()
        status_card.get_style_context().add_class("flat-card")
        status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        status_box.set_border_width(16)
        status_row = Gtk.Box(spacing=12)
        magicq_title = Gtk.Label(label="MagicQ")
        magicq_title.set_xalign(0)
        magicq_title.get_style_context().add_class("overview-card-title")
        status_row.pack_start(magicq_title, True, True, 0)
        self.magicq_state_label = Gtk.Label()
        self.magicq_state_label.get_style_context().add_class("status-pill")
        status_row.pack_start(self.magicq_state_label, False, False, 0)
        status_box.pack_start(status_row, False, False, 0)
        description = Gtk.Label(label=_("Main lighting console"))
        description.set_xalign(0)
        description.get_style_context().add_class("section-subtitle")
        status_box.pack_start(description, False, False, 0)
        self.magicq_auto_switch = Gtk.Switch()
        auto_row = toggle_row(_("Automatic startup"), self.magicq_auto_switch)
        self.magicq_auto_handler = self.magicq_auto_switch.connect(
            "state-set", magicq_auto_changed)
        status_box.pack_start(auto_row, False, False, 0)
        status_card.add(status_box)
        page.pack_start(status_card, False, False, 0)

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

    def set_magicq_state(self, state):
        context = self.magicq_state_label.get_style_context()
        context.remove_class("status-good")
        context.remove_class("status-neutral")
        context.add_class("status-good" if state.running else "status-neutral")
        self.magicq_state_label.set_text(
            f"●  {_('OPEN') if state.running else _('READY')}")
        self.magicq_auto_switch.handler_block(self.magicq_auto_handler)
        self.magicq_auto_switch.set_active(state.automatic)
        self.magicq_auto_switch.handler_unblock(self.magicq_auto_handler)
