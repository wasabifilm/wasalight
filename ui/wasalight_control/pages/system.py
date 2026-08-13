"""System services and Control preferences."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from ..i18n import _, current_language
from ..widgets import card_flow, section_heading
from .common import scroll_page


class SystemPage:
    def __init__(self, save_language):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("System"),
            _("Remote services and preferences for this Control interface.")),
            False, False, 0)

        page.pack_start(section_heading(
            _("Remote access"),
            _("Current state and automatic startup of Wasalight services.")),
            False, False, 0)
        self.service_cards = card_flow()
        page.pack_start(self.service_cards, False, False, 0)

        language_frame = Gtk.Frame()
        language_row = Gtk.Box(spacing=14)
        language_row.set_border_width(14)
        language_text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        label = Gtk.Label(label=_("Language"))
        label.set_xalign(0)
        description = Gtk.Label(label=_("Applied the next time Wasalight Control starts."))
        description.set_xalign(0)
        description.get_style_context().add_class("section-subtitle")
        language_text.pack_start(label, False, False, 0)
        language_text.pack_start(description, False, False, 0)
        language_row.pack_start(language_text, True, True, 0)
        self.language = Gtk.ComboBoxText()
        self.language.append("auto", _("Automatic"))
        self.language.append("it", "Italiano")
        self.language.append("en", "English")
        self.language.set_active_id(current_language())
        language_row.pack_start(self.language, False, False, 0)
        save = Gtk.Button(label=_("Save"))
        save.connect("clicked", save_language, self.language)
        language_row.pack_start(save, False, False, 0)
        language_frame.add(language_row)
        page.pack_start(language_frame, False, False, 0)
        self.widget = scroll_page(page)
