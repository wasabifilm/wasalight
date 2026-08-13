# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Application chrome and primary navigation for Wasalight Control."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from .i18n import _, current_language
from .widgets import image_for


class ApplicationShell(Gtk.Box):
    def __init__(self, identity, pages, on_close):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.pack_start(self._header(identity, on_close), False, False, 0)
        body = Gtk.Box()
        navigation = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        navigation.set_size_request(210, -1)
        navigation.set_border_width(10)
        navigation.get_style_context().add_class("sidebar")
        self.navigation = navigation
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(180)
        self.navigation_buttons = {}
        group = None
        for page_id, label, widget in pages:
            self.stack.add_named(widget, page_id)
            button = Gtk.RadioButton.new_with_label_from_widget(group, label)
            if group is None:
                group = button
            button.set_mode(False)
            button.set_size_request(-1, 56)
            button.get_style_context().add_class("navigation-button")
            button.connect("toggled", self._navigate, page_id)
            navigation.pack_start(button, False, False, 0)
            self.navigation_buttons[page_id] = button
        body.pack_start(navigation, False, False, 0)
        body.pack_start(self.stack, True, True, 0)
        self.pack_start(body, True, True, 0)

    def configure_language_button(self, open_language):
        """Keep language selection outside the operational pages."""
        language_choices = {
            "auto": _("Automatic"), "it": "Italiano", "en": "English",
        }
        current_name = language_choices.get(current_language(), _("Automatic"))
        button = Gtk.Button()
        button.get_style_context().add_class("preference-button")
        button.set_size_request(-1, 46)
        button_box = Gtk.Box(spacing=10)
        button_box.pack_start(
            image_for("preferences-desktop-locale", 20), False, False, 0)
        button_label = Gtk.Label(label=f"{_('Language')}  ·  {current_name}")
        button_label.set_xalign(0)
        button_box.pack_start(button_label, True, True, 0)
        button.add(button_box)
        button.connect("clicked", lambda _button: open_language())
        self.navigation.pack_end(button, False, False, 0)

    @staticmethod
    def _header(identity, on_close):
        box = Gtk.Box(spacing=14)
        box.set_border_width(12)
        box.get_style_context().add_class("control-header")
        box.pack_start(
            image_for("/usr/local/share/icons/wasalight/hub.svg", 58),
            False, False, 0)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        title = Gtk.Label(label="Wasalight Control")
        title.set_xalign(0)
        title.set_markup("<span size='20000' weight='bold'>Wasalight Control</span>")
        title.get_style_context().add_class("brand-title")
        title_box.pack_start(title, False, False, 0)
        box.pack_start(title_box, True, True, 0)
        version = Gtk.Label(label=f"Wasalight {identity.version}")
        version.set_xalign(1)
        version.get_style_context().add_class("section-subtitle")
        box.pack_start(version, False, False, 0)
        close = Gtk.Button(label=_("Close"))
        close.set_size_request(120, 50)
        close.connect("clicked", lambda _button: on_close())
        box.pack_start(close, False, False, 0)
        return box

    def _navigate(self, button, page_id):
        if button.get_active():
            self.stack.set_visible_child_name(page_id)

    def show_page(self, page_id):
        button = self.navigation_buttons.get(page_id)
        if button is not None:
            button.set_active(True)
