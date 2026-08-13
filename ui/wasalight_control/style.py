"""Wasalight Control visual theme."""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk


CSS = b"""
window { background-color: #080b10; color: #e6edf3; }
button, combobox button {
    min-height: 44px; font-size: 15px; padding: 8px;
    background: #171c23; color: #e6edf3;
    border: 1px solid #343d48; border-radius: 7px;
}
button:hover { background: #223016; color: #f0f7e8; border-color: #76bd22; }
button:focus { border-color: #76bd22; box-shadow: inset 0 0 0 1px #76bd22; }
button:active { background: #76bd22; color: #080b10; }
.navigation-button {
    padding: 10px 16px;
    background: #11151b; color: #aeb7c2; border-color: transparent;
}
.navigation-button:checked {
    background: #223016; color: #9bd95a; border-color: #36551c;
}
switch {
    min-width: 64px; min-height: 32px;
    background: #303842; border: 1px solid #4b5563; border-radius: 18px;
}
switch:checked { background: #76bd22; border-color: #9bd95a; }
switch slider {
    min-width: 28px; min-height: 28px;
    background: #e6edf3; border-radius: 15px;
}
stack, scrolledwindow, viewport, flowbox {
    background: #0d1117; color: #e6edf3;
}
frame { background: #11151b; border: 1px solid #303842; border-radius: 7px; }
.state-good { background: #11180d; border-color: #36551c; }
.state-warning { background: #211b0b; border-color: #6f5917; }
.state-error { background: #241010; border-color: #7a3030; }
textview, textview text { background: #0d1117; color: #e6edf3; font-size: 14px; }
.overview-title { color: #e6edf3; font-size: 22px; font-weight: bold; }
.overview-card-title { color: #e6edf3; font-size: 16px; font-weight: bold; }
.section-subtitle { color: #aeb7c2; font-size: 13px; }
.card-description { color: #aeb7c2; font-size: 13px; }
"""


def install_style():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    return provider
