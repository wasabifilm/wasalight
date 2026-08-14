# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""GTK layout rules generated from the selected Wasalight colour theme."""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk

from .theme import current_palette


def build_css(palette):
    """Build GTK CSS from validated semantic colour tokens."""
    return f"""
window {{ background: {palette['background']}; color: {palette['text']}; }}
.control-header {{
    background: {palette['panel_alt']};
    border-bottom: 2px solid {palette['technical']};
}}
.sidebar {{ background: {palette['surface']}; }}
button, combobox button {{
    min-height: 44px; padding: 8px 12px; font-size: 15px;
    background: {palette['panel_alt']}; color: {palette['text']};
    border: 1px solid {palette['separator']}; border-radius: 2px;
    background-image: none; box-shadow: none; text-shadow: none;
}}
button:hover {{
    background: {palette['surface_hover']};
    border-color: {palette['technical']};
}}
button:focus {{ border-color: {palette['brand']}; }}
button:active {{
    background: {palette['technical']}; color: {palette['text']};
    border-color: {palette['technical']};
}}
.primary-button {{
    background: {palette['brand']}; color: {palette['brand_text']};
    border-color: {palette['brand']}; font-weight: bold;
}}
.primary-button:hover {{
    background: {palette['brand_hover']}; color: {palette['brand_text']};
    border-color: {palette['brand_hover']};
}}
.close-button {{
    min-width: 150px; min-height: 56px; padding: 8px 18px;
    background: {palette['danger']}; color: {palette['text']};
    border: 2px solid {palette['danger_hover']};
    font-size: 16px; font-weight: bold;
}}
.close-button:hover, .close-button:focus {{
    background: {palette['danger_hover']}; color: {palette['text']};
    border-color: {palette['text']};
}}
.close-button:active {{
    background: {palette['danger']}; color: {palette['text']};
    border-color: {palette['text']};
}}
.secondary-button {{
    background: {palette['panel_alt']}; border-color: {palette['separator']};
}}
.text-button {{
    background: {palette['panel_alt']}; color: {palette['text']};
    border-color: {palette['separator']};
}}
.text-button:hover {{
    background: {palette['technical']}; color: {palette['text']};
    border-color: {palette['technical']};
}}
.navigation-button {{
    min-height: 50px; padding: 8px 14px;
    background: transparent; color: {palette['text_muted']};
    border: 0 solid transparent; border-radius: 0;
    background-image: none; box-shadow: none;
}}
.navigation-button:hover {{
    background: {palette['panel']}; color: {palette['text']};
    border: 0 solid transparent; box-shadow: none;
}}
.navigation-button:checked {{
    background: {palette['brand']}; color: {palette['brand_text']};
    border: 0 solid transparent; box-shadow: none; font-weight: bold;
}}
.preference-button {{
    min-height: 46px; background: {palette['panel']};
    color: {palette['text_muted']};
    border: 0 solid transparent; border-radius: 0; box-shadow: none;
}}
.preference-button:hover {{
    background: {palette['panel_alt']}; color: {palette['text']};
    border: 0 solid transparent; box-shadow: none;
}}
switch {{
    min-width: 64px; min-height: 32px;
    background: {palette['surface_hover']};
    border: 1px solid {palette['separator']}; border-radius: 2px;
}}
switch:checked {{
    background: {palette['brand']}; border-color: {palette['brand']};
}}
switch slider {{
    min-width: 28px; min-height: 28px;
    background: {palette['text']}; border-radius: 1px;
}}
stack, scrolledwindow, viewport, flowbox {{
    background: {palette['background']}; color: {palette['text']};
}}
frame {{
    background: {palette['panel']};
    border: 1px solid {palette['separator']}; border-radius: 2px;
}}
.flat-card {{ background: {palette['panel']}; border-color: {palette['separator']}; }}
.flat-card:hover {{ border-color: {palette['technical']}; }}
.software-tile {{
    background: {palette['panel']}; border-color: {palette['separator']};
}}
.software-tile:hover {{
    background: {palette['panel_alt']}; border-color: {palette['technical']};
}}
.status-pill {{
    padding: 4px 9px; border-radius: 2px;
    font-size: 12px; font-weight: bold;
}}
.status-good {{ color: {palette['brand']}; background: {palette['surface']}; }}
.status-warning {{ color: {palette['warning']}; background: {palette['surface']}; }}
.status-error {{ color: {palette['danger']}; background: {palette['surface']}; }}
.status-neutral {{ color: {palette['text_muted']}; background: {palette['surface']}; }}
.brand-title {{ color: {palette['brand']}; }}
.technical-label {{ color: {palette['technical_hover']}; }}
textview, textview text {{
    background: {palette['surface']}; color: {palette['text']}; font-size: 14px;
}}
.overview-title {{ color: {palette['text']}; font-size: 22px; font-weight: bold; }}
.overview-card-title {{ color: {palette['text']}; font-size: 16px; font-weight: bold; }}
.section-subtitle {{ color: {palette['text_muted']}; font-size: 13px; }}
.card-description {{ color: {palette['text_muted']}; font-size: 13px; }}
.control-row {{ padding: 4px 0; }}
""".encode("utf-8")


def install_style(palette=None):
    provider = Gtk.CssProvider()
    provider.load_from_data(build_css(palette or current_palette()))
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    return provider
