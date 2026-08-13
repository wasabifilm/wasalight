"""Support and diagnostic launchers."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _
from ..widgets import section_heading
from .common import launcher_flow, scroll_page


class ToolsPage:
    def __init__(self, launchers, launch_application):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("Tools"),
            _("Diagnostics, support and data management utilities.")),
            False, False, 0)
        page.pack_start(launcher_flow("Support", launchers, launch_application),
                        False, False, 0)
        self.widget = scroll_page(page)
