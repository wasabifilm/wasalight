#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Render-level checks for the Subiquity progress display on tty2."""

from __future__ import annotations

import importlib.util
from importlib.machinery import SourceFileLoader
import io
import os
from pathlib import Path
import re
import sys


class FakeTTY(io.StringIO):
    def fileno(self) -> int:
        return 124


def fail(message: str) -> None:
    raise SystemExit(f"ERRORE: {message}")


ui_path = Path(sys.argv[1]).resolve()
loader = SourceFileLoader("wasalight_install_ui", str(ui_path))
spec = importlib.util.spec_from_loader("wasalight_install_ui", loader)
if spec is None or spec.loader is None:
    fail("impossibile caricare install-ui.sh")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

tty = FakeTTY()
original_terminal_size = module.os.get_terminal_size
module.os.get_terminal_size = lambda _fd: os.terminal_size((160, 50))
try:
    module.render(tty, "◐")
finally:
    module.os.get_terminal_size = original_terminal_size

rendered = tty.getvalue()
plain = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", rendered)
top = next((line for line in plain.splitlines() if "┏" in line), "")
if not top.startswith(" " * 22):
    fail("display tty2 da 116 colonne non centrato su una console da 160")
if len(top) != 22 + 116:
    fail("larghezza adattiva del display tty2 errata")
frame_lines = [line for line in plain.splitlines() if "┃" in line]
if any(len(line) != 22 + 116 for line in frame_lines):
    fail("bordo destro disallineato nel display tty2")
if "WASALIGHT INSTALLER v" not in plain or "Technical logs: Ctrl+Alt+F1" not in plain:
    fail("contenuto essenziale del display tty2 mancante")

print("Rendering avanzamento tty2 verificato a 160 colonne.")
