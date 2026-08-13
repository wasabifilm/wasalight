"""Project information page."""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

from ..i18n import _
from ..widgets import image_for, section_heading
from .common import scroll_page


class AboutPage:
    def __init__(self, identity):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        page.pack_start(section_heading(
            _("About"), _("Authors, license and project acknowledgements.")),
            False, False, 0)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_border_width(22)
        content.pack_start(
            image_for("/usr/share/plymouth/themes/wasalight/boot-logo.png", 190),
            False, False, 0)
        title = Gtk.Label()
        title.set_markup(
            "<span foreground='#76bd22' size='17000' weight='bold'>Wasalight</span>\n"
            f"<span size='9500'>{GLib.markup_escape_text(_('Version {version}').format(version=identity.version))}</span>")
        title.set_justify(Gtk.Justification.CENTER)
        content.pack_start(title, False, False, 0)
        author = Gtk.Label(label=_("Created by Michele Moser / Wasabi Lightbulbfarm"))
        author.set_line_wrap(True)
        author.set_justify(Gtk.Justification.CENTER)
        content.pack_start(author, False, False, 0)
        license_text = Gtk.Label(label=_(
            "Code and documentation: Apache License 2.0. "
            "The Wasabi Lightbulbfarm logo is excluded from the software license and remains protected.\n"
            "ChamSys MagicQ and Bitfocus Companion are external products and retain "
            "their respective trademarks and licenses."))
        license_text.set_line_wrap(True)
        license_text.set_justify(Gtk.Justification.CENTER)
        license_text.set_max_width_chars(78)
        content.pack_start(license_text, False, False, 0)
        links = Gtk.Box(spacing=12)
        github = Gtk.LinkButton.new_with_label(
            "https://github.com/wasabifilm/wasalight", _("GitHub project"))
        instagram = Gtk.LinkButton.new_with_label(
            "https://www.instagram.com/wasabi_lightbulbfarm/",
            "@wasabi_lightbulbfarm")
        links.pack_start(Gtk.Label(), True, True, 0)
        links.pack_start(github, False, False, 0)
        links.pack_start(instagram, False, False, 0)
        links.pack_start(Gtk.Label(), True, True, 0)
        content.pack_start(links, False, False, 0)
        page.pack_start(content, False, False, 0)
        self.widget = scroll_page(page)
