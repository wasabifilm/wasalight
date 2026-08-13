"""Wasalight Control visual theme."""

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk


CSS = b"""
window { background-color: #080b10; color: #e6edf3; }
button, combobox button {
    min-height: 44px; font-size: 15px; padding: 8px;
    background: transparent; color: #e6edf3;
    border: 1px solid #303842; border-radius: 6px;
}
button:hover { background: #1a222b; color: #f0f7e8; border-color: #303842; }
button:focus { border-color: #76bd22; }
button:active { background: #76bd22; color: #080b10; }
.primary-button {
    background: #76bd22; color: #080b10; border-color: #76bd22;
    font-weight: bold;
}
.primary-button:hover { background: #8ccc45; color: #080b10; border-color: #9bd95a; }
.secondary-button { background: #171e26; border-color: #303842; }
.text-button { color: #9bd95a; padding-left: 14px; padding-right: 14px; }
.text-button:hover { background: #151d25; color: #b7e77f; border-color: #76bd22; }
.navigation-button {
    padding: 10px 16px;
    background: transparent; color: #aeb7c2; border-color: #252d36;
}
.navigation-button:checked {
    background: #223016; color: #9bd95a; border-color: #36551c;
}
.language-button {
    background: #10151b; color: #aeb7c2; border-color: #252d36;
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
frame { background: #11161d; border: 1px solid #252d36; border-radius: 6px; }
.flat-card { background: #11161d; border-color: #252d36; }
.flat-card:hover { border-color: #3a4652; }
.software-tile { background: #11161d; border-color: #252d36; }
.software-tile:hover { background: #151d25; border-color: #3a4652; }
.status-pill {
    padding: 4px 9px; border-radius: 12px; font-size: 12px; font-weight: bold;
}
.status-good { color: #9bd95a; background: #17220f; }
.status-warning { color: #f2cc60; background: #211b0b; }
.status-error { color: #ff7b72; background: #261313; }
.status-neutral { color: #aeb7c2; background: #1a2028; }
textview, textview text { background: #0d1117; color: #e6edf3; font-size: 14px; }
.overview-title { color: #e6edf3; font-size: 22px; font-weight: bold; }
.overview-card-title { color: #e6edf3; font-size: 16px; font-weight: bold; }
.section-subtitle { color: #aeb7c2; font-size: 13px; }
.card-description { color: #aeb7c2; font-size: 13px; }
.control-row { padding: 4px 0; }
.popover-card { background: #11161d; color: #e6edf3; }
"""


def install_style():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    return provider
