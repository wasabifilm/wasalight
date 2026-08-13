"""Application chrome and primary navigation for Wasalight Control."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

from .i18n import _
from .widgets import image_for


class ApplicationShell(Gtk.Box):
    def __init__(self, identity, pages, on_close):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.pack_start(self._header(identity, on_close), False, False, 0)
        body = Gtk.Box()
        navigation = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        navigation.set_size_request(210, -1)
        navigation.set_border_width(10)
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

    @staticmethod
    def _header(identity, on_close):
        box = Gtk.Box(spacing=14)
        box.set_border_width(12)
        box.pack_start(
            image_for("/usr/local/share/icons/wasalight/hub.svg", 58),
            False, False, 0)
        title = Gtk.Label()
        title.set_xalign(0)
        title.set_markup(
            "<span foreground='#76bd22' size='20000' weight='bold'>Wasalight Control</span>\n"
            f"<span size='9500'>{GLib.markup_escape_text(_('MagicQ · services · applications · system'))}</span>")
        box.pack_start(title, True, True, 0)
        state = Gtk.Label()
        colour = "#76bd22" if identity.mode == "SHOW" else "#f2cc60"
        state.set_markup(
            f"<span foreground='{colour}' weight='bold'>{identity.mode}</span>\n"
            f"<span size='8500'>Wasalight {GLib.markup_escape_text(identity.version)}</span>")
        state.set_justify(Gtk.Justification.RIGHT)
        box.pack_start(state, False, False, 0)
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
