# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Parsing and discovery of applications exposed by Wasalight Control."""

import configparser
import glob
import os
import re
import shutil
from collections.abc import Callable

from .models import ControlPaths, Launcher


COMPANION = re.compile(
    r"magicvis|magichd|magicq[ -]?remote|chamsys.*(?:remote|viewer|media)", re.I)
SECTIONS = ("MagicQ", "Applications", "Support")


def _desktop_bool(item, key, default=False):
    try:
        return item.getboolean(key, fallback=default)
    except ValueError:
        return default


def read_launcher(path: str, forced_section: str | None = None, *,
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
    name = item.get("Name", "").strip()
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
        comment=item.get("Comment", ""),
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
