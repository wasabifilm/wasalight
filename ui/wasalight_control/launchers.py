# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Parsing and discovery of applications exposed by Wasalight Control."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import configparser
import glob
import os
import re
import shutil
from collections.abc import Callable

from .i18n import current_language
from .models import ControlPaths, Launcher


COMPANION = re.compile(
    r"magicvis|magichd|magicq[ -]?remote|chamsys.*(?:remote|viewer|media)", re.I)
SECTIONS = ("MagicQ", "Applications", "Support")
SUPPORTED_DESKTOP_LANGUAGES = ("en", "it")


def _desktop_bool(item, key, default=False):
    try:
        return item.getboolean(key, fallback=default)
    except ValueError:
        return default


def _effective_language(language=None, environment=os.environ):
    requested = current_language() if language is None else language
    if requested in SUPPORTED_DESKTOP_LANGUAGES:
        return requested
    for variable in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        value = environment.get(variable, "")
        for candidate in value.split(":"):
            normalized = candidate.split(".", 1)[0].split("@", 1)[0]
            normalized = normalized.split("_", 1)[0].lower()
            if normalized in SUPPORTED_DESKTOP_LANGUAGES:
                return normalized
    return "en"


def _localized_value(item, key, language):
    return item.get(f"{key}[{language}]", fallback=item.get(key, "")).strip()


def read_launcher(path: str, forced_section: str | None = None, *, language=None,
                  which: Callable[[str], str | None] = shutil.which) -> Launcher | None:
    parser = configparser.RawConfigParser(interpolation=None, strict=False)
    try:
        parser.read(path, encoding="utf-8")
        item = parser["Desktop Entry"]
    except (OSError, KeyError, configparser.Error):
        return None
    if item.get("Type", "Application") != "Application":
        return None
    if _desktop_bool(item, "Hidden") or _desktop_bool(item, "NoDisplay"):
        return None
    selected_language = _effective_language(language)
    name = _localized_value(item, "Name", selected_language)
    command = item.get("Exec", "").strip()
    try_exec = item.get("TryExec", "").strip()
    if not name or not command:
        return None
    if try_exec and not (
            os.path.exists(try_exec) if os.path.isabs(try_exec) else which(try_exec)):
        return None
    section = forced_section or item.get("X-Wasalight-Section", "Applications")
    try:
        order = int(item.get("X-Wasalight-Order", "500"))
    except ValueError:
        order = 500
    return Launcher(
        name=name,
        comment=_localized_value(item, "Comment", selected_language),
        command=command,
        icon=item.get("Icon", "application-x-executable"),
        terminal=_desktop_bool(item, "Terminal"),
        working_directory=item.get("Path", "").strip() or None,
        section=section if section in SECTIONS else "Applications",
        order=order,
    )


def installed_launchers(paths: ControlPaths = ControlPaths()) -> list[Launcher]:
    result: list[Launcher] = []
    seen: set[tuple[str, str]] = set()
    for directory in (paths.system_apps_dir, paths.persistent_apps_dir):
        for path in sorted(glob.glob(os.path.join(directory, "*.desktop"))):
            launcher = read_launcher(path)
            if launcher and (launcher.name, launcher.command) not in seen:
                result.append(launcher)
                seen.add((launcher.name, launcher.command))
    for path in sorted(glob.glob(os.path.join(paths.desktop_apps_dir, "*.desktop"))):
        launcher = read_launcher(path, "MagicQ")
        if not launcher:
            continue
        searchable = " ".join((launcher.name, launcher.command, launcher.comment))
        if COMPANION.search(searchable) and (launcher.name, launcher.command) not in seen:
            result.append(launcher)
            seen.add((launcher.name, launcher.command))
    return sorted(result, key=lambda value: (
        value.section, value.order, value.name.lower()))
