# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Validated external colour palette for Wasalight Control."""

import configparser
import re


DEFAULT_THEME_PATH = "/usr/local/share/wasalight-control/themes/console-dark.ini"
COLOUR = re.compile(r"^#[0-9a-fA-F]{6}$")

DEFAULT_PALETTE = {
    "background": "#1b1f20",
    "panel": "#282d30",
    "panel_alt": "#353b3e",
    "surface": "#222729",
    "surface_hover": "#303639",
    "separator": "#4a5154",
    "text": "#f1f3f3",
    "text_muted": "#aeb5b7",
    "technical": "#0088bd",
    "technical_hover": "#079bd2",
    "brand": "#76bd22",
    "brand_hover": "#8dcc3e",
    "brand_text": "#10130d",
    "warning": "#e0a928",
    "danger": "#b93636",
    "danger_hover": "#ce4646",
}

_theme_name = "Console Dark"
_palette = dict(DEFAULT_PALETTE)


def _load_file(path):
    parser = configparser.ConfigParser(interpolation=None)
    with open(path, encoding="utf-8") as source:
        parser.read_file(source)
    if not parser.has_section("colors"):
        raise ValueError("missing [colors] section")
    palette = {}
    for token in DEFAULT_PALETTE:
        value = parser.get("colors", token, fallback="").strip()
        if not COLOUR.fullmatch(value):
            raise ValueError(f"invalid or missing colour: {token}")
        palette[token] = value.lower()
    name = parser.get("theme", "name", fallback="").strip()
    return name or "Console Dark", palette


def configure(*, theme_path=DEFAULT_THEME_PATH):
    """Load the fixed external palette, falling back to built-in colours."""
    global _theme_name, _palette
    try:
        name, palette = _load_file(theme_path)
    except (OSError, ValueError, configparser.Error):
        name, palette = "Console Dark", dict(DEFAULT_PALETTE)
    _theme_name = name
    _palette = palette
    return _theme_name


def current_theme_name():
    return _theme_name


def current_palette():
    return dict(_palette)
