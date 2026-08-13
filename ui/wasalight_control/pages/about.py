# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Project information page."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

from ..i18n import _
from ..widgets import image_for
from .common import scroll_page


class AboutPage:
    def __init__(self, identity):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        page.set_border_width(16)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_border_width(22)
        content.pack_start(
            image_for("/usr/share/plymouth/themes/wasalight/boot-logo.png", 190),
            False, False, 0)
        title = Gtk.Label()
        title.set_markup(
            "<span size='17000' weight='bold'>Wasalight</span>\n"
            f"<span size='9500'>{GLib.markup_escape_text(_('Version {version}').format(version=identity.version))}</span>")
        title.get_style_context().add_class("brand-title")
        title.set_justify(Gtk.Justification.CENTER)
        content.pack_start(title, False, False, 0)
        author = Gtk.Label(label=_("Created by Michele Moser / Wasabi Lightbulbfarm"))
        author.set_line_wrap(True)
        author.set_justify(Gtk.Justification.CENTER)
        content.pack_start(author, False, False, 0)
        contact = Gtk.Label(label=(
            "Wasabi sas di Michele Moser & C. · IT02274000229\n"
            "Viale Verona 190/11 · 38123 Trento, Italy"))
        contact.set_line_wrap(True)
        contact.set_justify(Gtk.Justification.CENTER)
        content.pack_start(contact, False, False, 0)
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
        website = Gtk.LinkButton.new_with_label(
            "https://www.wasabi.eu/", _("Website"))
        email = Gtk.LinkButton.new_with_label(
            "mailto:info@wasabi.eu", _("Email"))
        github = Gtk.LinkButton.new_with_label(
            "https://github.com/wasabifilm/wasalight", _("GitHub project"))
        links.pack_start(Gtk.Label(), True, True, 0)
        links.pack_start(website, False, False, 0)
        links.pack_start(email, False, False, 0)
        links.pack_start(github, False, False, 0)
        links.pack_start(Gtk.Label(), True, True, 0)
        content.pack_start(links, False, False, 0)

        social_links = Gtk.Box(spacing=12)
        facebook = Gtk.LinkButton.new_with_label(
            "https://www.facebook.com/wasabilightbulbfarm", "Facebook")
        instagram = Gtk.LinkButton.new_with_label(
            "https://www.instagram.com/wasabi_lightbulbfarm/",
            "@wasabi_lightbulbfarm")
        youtube = Gtk.LinkButton.new_with_label(
            "https://www.youtube.com/@Wasabi_lightbulbfarm", "YouTube")
        linkedin = Gtk.LinkButton.new_with_label(
            "https://www.linkedin.com/company/wasabi-lightbulbfarm/", "LinkedIn")
        social_links.pack_start(Gtk.Label(), True, True, 0)
        for button in (facebook, instagram, youtube, linkedin):
            social_links.pack_start(button, False, False, 0)
        social_links.pack_start(Gtk.Label(), True, True, 0)
        content.pack_start(social_links, False, False, 0)
        page.pack_start(content, False, False, 0)
        self.widget = scroll_page(page)
