"""Operational overview page."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..overview_state import OverviewSnapshot
from ..widgets import section_heading


class OverviewPage(Gtk.Box):
    def __init__(self, identity, paths, run_command, open_page):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.set_border_width(16)
        self.paths = paths
        self.run_command = run_command
        self.open_page = open_page

        self.summary = Gtk.Frame()
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
        mode_label = _("Switch to MAINTENANCE") if identity.mode == "SHOW" else _("Switch to SHOW")
        mode_button = Gtk.Button(label=mode_label)
        mode_button.set_size_request(190, 58)
        mode_button.connect("clicked", run_command, [paths.mode_toggle])
        summary_row.pack_start(mode_button, False, False, 0)
        self.summary.add(summary_row)
        self.pack_start(self.summary, False, False, 0)

        magicq = Gtk.Frame()
        magicq_row = Gtk.Box(spacing=16)
        magicq_row.set_border_width(16)
        magicq_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        heading = Gtk.Label(label="MagicQ")
        heading.set_xalign(0)
        heading.get_style_context().add_class("overview-card-title")
        self.magicq_summary = Gtk.Label()
        self.magicq_summary.set_xalign(0)
        self.magicq_detail = Gtk.Label()
        self.magicq_detail.set_xalign(0)
        self.magicq_detail.get_style_context().add_class("section-subtitle")
        magicq_text.pack_start(heading, False, False, 0)
        magicq_text.pack_start(self.magicq_summary, False, False, 0)
        magicq_text.pack_start(self.magicq_detail, False, False, 0)
        magicq_row.pack_start(magicq_text, True, True, 0)
        self.magicq_button = Gtk.Button(label=_("Open MagicQ"))
        self.magicq_button.set_size_request(190, 58)
        self.magicq_button.connect("clicked", run_command, [paths.magicq_start])
        magicq_row.pack_start(self.magicq_button, False, False, 0)
        magicq.add(magicq_row)
        self.pack_start(magicq, False, False, 0)

        cards = Gtk.Box(spacing=12)
        self.network_card = self._status_card(
            _("Network"), lambda _button: open_page("system"))
        self.remote_card = self._status_card(
            _("Remote access"), lambda _button: open_page("system"))
        self.update_card = self._status_card(
            _("Updates"), lambda _button: open_page("maintenance"))
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
    def _status_card(title, callback):
        frame = Gtk.Frame()
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        content.set_border_width(14)
        heading = Gtk.Label(label=title)
        heading.set_xalign(0)
        heading.get_style_context().add_class("overview-card-title")
        summary = Gtk.Label()
        summary.set_xalign(0)
        summary.set_line_wrap(True)
        detail = Gtk.Label()
        detail.set_xalign(0)
        detail.set_line_wrap(True)
        detail.set_max_width_chars(30)
        detail.get_style_context().add_class("section-subtitle")
        button = Gtk.Button(label=_("Open"))
        button.connect("clicked", callback)
        content.pack_start(heading, False, False, 0)
        content.pack_start(summary, False, False, 0)
        content.pack_start(detail, True, True, 0)
        content.pack_start(button, False, False, 0)
        frame.add(content)
        return frame, summary, detail

    @staticmethod
    def _set_card(card, summary, detail):
        card[1].set_text(summary)
        card[2].set_text(detail)

    def set_snapshot(self, snapshot: OverviewSnapshot):
        if snapshot.level == "error":
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
        self.summary.get_style_context().remove_class("state-good")
        self.summary.get_style_context().remove_class("state-warning")
        self.summary.get_style_context().remove_class("state-error")
        self.summary.get_style_context().add_class(f"state-{snapshot.level}")

        self.magicq_summary.set_text(
            _("Open") if snapshot.magicq_running else _("Closed"))
        self.magicq_detail.set_text(
            _("Automatic startup enabled") if snapshot.magicq_automatic
            else _("Manual startup"))
        self.magicq_button.set_label(
            _("Bring to foreground") if snapshot.magicq_running else _("Open MagicQ"))

        network_summary = {
            "good": _("Managed"), "error": _("Configuration problem"),
            "neutral": _("State unknown"),
        }[snapshot.network_level]
        self._set_card(self.network_card, network_summary, snapshot.network_detail)

        if snapshot.ssh_running and snapshot.vnc_running:
            remote_summary = _("SSH and VNC active")
        elif snapshot.ssh_running:
            remote_summary = _("SSH active")
        elif snapshot.vnc_running:
            remote_summary = _("VNC active")
        else:
            remote_summary = _("SSH and VNC stopped")
        self._set_card(self.remote_card, remote_summary, snapshot.remote_detail)

        update_summary = {
            "good": _("System up to date"),
            "warning": _("Update available"),
            "neutral": _("Not checked"),
        }[snapshot.update_level]
        self._set_card(self.update_card, update_summary, snapshot.update_detail)
        self.status_view.get_buffer().set_text(snapshot.raw_status)
