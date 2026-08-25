# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Operational overview page."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..overview_state import (
    OverviewSnapshot, localized_health_detail, localized_magicq_detail,
    localized_service_detail, localized_update_detail,
)
from ..widgets import toggle_row


class OverviewPage(Gtk.Box):
    def __init__(self, identity, paths, run_command, open_page,
                 magicq_auto_changed, update_channel_changed):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.set_border_width(16)
        self.paths = paths
        self.run_command = run_command
        self.open_page = open_page

        self.summary = Gtk.Frame()
        self.summary.get_style_context().add_class("flat-card")
        summary_row = Gtk.Box(spacing=18)
        summary_row.set_border_width(18)
        summary_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.summary_title = Gtk.Label()
        self.summary_title.set_xalign(0)
        self.summary_title.get_style_context().add_class("overview-title")
        self.summary_title.set_text(_("Loading status…"))
        self.summary_detail = Gtk.Label()
        self.summary_detail.set_xalign(0)
        self.summary_detail.set_line_wrap(True)
        self.summary_detail.get_style_context().add_class("section-subtitle")
        self.summary_detail.set_text(_("Reading appliance services."))
        summary_text.pack_start(self.summary_title, False, False, 0)
        summary_text.pack_start(self.summary_detail, False, False, 0)
        summary_row.pack_start(summary_text, True, True, 0)
        summary_actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        summary_actions.set_halign(Gtk.Align.END)
        mode_label = _("Switch to MAINTENANCE") if identity.mode == "SHOW" else _("Switch to SHOW")
        mode_button = Gtk.Button(label=mode_label)
        mode_button.get_style_context().add_class("primary-button")
        mode_button.set_size_request(190, 58)
        mode_button.connect("clicked", run_command, [paths.mode_toggle])
        summary_actions.pack_start(mode_button, False, False, 0)
        summary_row.pack_start(summary_actions, False, False, 0)
        self.summary.add(summary_row)
        self.pack_start(self.summary, False, False, 0)

        magicq = Gtk.Frame()
        magicq.get_style_context().add_class("flat-card")
        magicq_row = Gtk.Box(spacing=16)
        magicq_row.set_border_width(16)
        magicq_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        magicq_heading = Gtk.Box(spacing=12)
        heading = Gtk.Label(label="MagicQ")
        heading.set_xalign(0)
        heading.get_style_context().add_class("overview-card-title")
        magicq_heading.pack_start(heading, True, True, 0)
        self.magicq_detail = Gtk.Label()
        self.magicq_detail.set_xalign(0)
        self.magicq_detail.get_style_context().add_class("section-subtitle")
        magicq_text.pack_start(magicq_heading, False, False, 0)
        magicq_text.pack_start(self.magicq_detail, False, False, 0)
        magicq_row.pack_start(magicq_text, True, True, 0)
        magicq_actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.magicq_auto_switch = Gtk.Switch()
        self.magicq_auto_handler = self.magicq_auto_switch.connect(
            "state-set", magicq_auto_changed)
        magicq_actions.pack_start(
            toggle_row(_("Automatic startup"), self.magicq_auto_switch),
            False, False, 0)
        self.magicq_button = Gtk.Button(label=f"{_('Open MagicQ')}  →")
        self.magicq_button.get_style_context().add_class("primary-button")
        self.magicq_button.set_size_request(190, 48)
        self.magicq_button.connect("clicked", run_command, [paths.magicq_action])
        magicq_actions.pack_start(self.magicq_button, False, False, 0)
        magicq_row.pack_start(magicq_actions, False, False, 0)
        magicq.add(magicq_row)
        self.pack_start(magicq, False, False, 0)

        cards = Gtk.Box(spacing=12)
        self.network_card = self._status_card(
            _("Network"),
            lambda _button: open_page("network"),
            _("Configure"))
        self.remote_card = self._status_card(
            _("Remote access"), lambda _button: open_page("system"))
        channel_row = Gtk.Box(spacing=8)
        channel_row.set_halign(Gtk.Align.START)
        stable_label = Gtk.Label(label="STABLE")
        stable_label.get_style_context().add_class("section-subtitle")
        debug_label = Gtk.Label(label="DEBUG")
        debug_label.get_style_context().add_class("section-subtitle")
        self.update_channel_switch = Gtk.Switch()
        self.update_channel_switch.set_tooltip_text(_(
            "Stable uses signed releases. Debug follows the latest main branch."))
        self.update_channel_handler = self.update_channel_switch.connect(
            "state-set", update_channel_changed)
        channel_row.pack_start(stable_label, False, False, 0)
        channel_row.pack_start(self.update_channel_switch, False, False, 0)
        channel_row.pack_start(debug_label, False, False, 0)
        self.update_card = self._status_card(
            _("Updates"),
            lambda button: run_command(button, [paths.update_terminal]),
            extra=channel_row)
        for card in (self.network_card, self.remote_card, self.update_card):
            cards.pack_start(card[0], True, True, 0)
        self.pack_start(cards, False, False, 0)

        details = Gtk.Expander(label=_("Technical details"))
        self.status_view = Gtk.TextView()
        self.status_view.set_editable(False)
        self.status_view.set_cursor_visible(False)
        self.status_view.set_monospace(True)
        self.status_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        scroll = Gtk.ScrolledWindow()
        scroll.set_min_content_height(180)
        scroll.add(self.status_view)
        details.add(scroll)
        self.pack_start(details, True, True, 0)

    @staticmethod
    def _status_card(title, callback, action_label=None, extra=None):
        frame = Gtk.Frame()
        frame.get_style_context().add_class("flat-card")
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        content.set_border_width(14)
        header = Gtk.Box(spacing=10)
        heading = Gtk.Label(label=title)
        heading.set_xalign(0)
        heading.get_style_context().add_class("overview-card-title")
        summary = Gtk.Label()
        summary.get_style_context().add_class("status-pill")
        header.pack_start(heading, True, True, 0)
        header.pack_start(summary, False, False, 0)
        detail = Gtk.Label()
        detail.set_xalign(0)
        detail.set_line_wrap(True)
        detail.set_max_width_chars(30)
        detail.get_style_context().add_class("section-subtitle")
        button = Gtk.Button(label=f"{action_label or _('Open')}  →")
        button.set_halign(Gtk.Align.START)
        button.get_style_context().add_class("text-button")
        button.connect("clicked", callback)
        content.pack_start(header, False, False, 0)
        content.pack_start(detail, True, True, 0)
        if extra is not None:
            content.pack_start(extra, False, False, 2)
        content.pack_start(button, False, False, 0)
        frame.add(content)
        return frame, summary, detail

    @staticmethod
    def _set_card(card, summary, detail, level="neutral"):
        card[1].set_text(summary)
        card[2].set_text(detail)
        context = card[1].get_style_context()
        for state in ("good", "warning", "error", "neutral"):
            context.remove_class(f"status-{state}")
        context.add_class(f"status-{level}")

    def set_snapshot(self, snapshot: OverviewSnapshot):
        if snapshot.health_level == "error":
            title = _("Attention required")
            detail = localized_health_detail(snapshot.health_detail)
        elif snapshot.level == "error":
            title = _("Attention required")
            detail = _("One or more essential appliance components are unavailable.")
        elif snapshot.mode == "MAINTENANCE":
            title = _("Maintenance mode")
            detail = _("Persistent system changes are currently allowed.")
        elif snapshot.update_level == "warning":
            title = _("Ready for the show · update available")
            detail = _("The appliance can operate, but a Wasalight update is available.")
        else:
            title = _("Ready for the show")
            detail = _("No problem requires attention.")
        self.summary_title.set_text(title)
        self.summary_detail.set_text(detail)

        self.magicq_detail.set_text(localized_magicq_detail(snapshot.magicq_detail))
        magicq_missing = snapshot.magicq_detail.lower() in {"missing", "not installed"}
        if magicq_missing:
            magicq_action = _("Install MagicQ")
        elif snapshot.magicq_running:
            magicq_action = _("Bring to foreground")
        else:
            magicq_action = _("Open MagicQ")
        self.magicq_button.set_label(f"{magicq_action}  →")
        self.magicq_auto_switch.handler_block(self.magicq_auto_handler)
        self.magicq_auto_switch.set_active(snapshot.magicq_automatic)
        self.magicq_auto_switch.handler_unblock(self.magicq_auto_handler)

        network_summary = {
            "good": _("Configured"), "error": _("To configure"),
            "neutral": _("State unavailable"),
        }[snapshot.network_level]
        network_detail = _("IP address: {address}").format(
            address=snapshot.network_ip or _("Unavailable"))
        self._set_card(
            self.network_card, network_summary, network_detail,
            snapshot.network_level)

        if snapshot.ssh_running and snapshot.vnc_running:
            remote_summary = _("SSH and VNC active")
        elif snapshot.ssh_running:
            remote_summary = _("SSH active")
        elif snapshot.vnc_running:
            remote_summary = _("VNC active")
        else:
            remote_summary = _("SSH and VNC stopped")
        remote_detail = _("SSH: {ssh} · VNC: {vnc}").format(
            ssh=localized_service_detail(snapshot.ssh_detail),
            vnc=localized_service_detail(snapshot.vnc_detail))
        self._set_card(
            self.remote_card, remote_summary, remote_detail,
            "good" if snapshot.ssh_running or snapshot.vnc_running else "neutral")

        update_summary = {
            "good": _("System up to date"),
            "warning": _("Update available"),
            "error": _("Recovery required"),
            "neutral": _("Not checked"),
        }[snapshot.update_level]
        self._set_card(
            self.update_card, update_summary,
            localized_update_detail(snapshot.update_detail),
            snapshot.update_level)
        self.update_channel_switch.handler_block(self.update_channel_handler)
        self.update_channel_switch.set_active(snapshot.update_channel == "debug")
        self.update_channel_switch.handler_unblock(self.update_channel_handler)
        self.status_view.get_buffer().set_text(snapshot.raw_status)
