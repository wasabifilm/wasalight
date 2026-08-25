#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Render-level checks for the dependency-free installer wizard."""

from __future__ import annotations

import importlib.util
import io
import os
from pathlib import Path
import re
import sys


class FakeTTY(io.StringIO):
    def fileno(self) -> int:
        return 123


def fail(message: str) -> None:
    raise SystemExit(f"ERRORE: {message}")


wizard_path = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("wasalight_install_wizard", wizard_path)
if spec is None or spec.loader is None:
    fail("impossibile caricare install-wizard.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

wizard = module.Wizard.__new__(module.Wizard)
wizard.tty = FakeTTY()
wizard.version = "41"
wizard.variant = "FULL"
wizard.pending_prompt = None

original_terminal_size = module.os.get_terminal_size
module.os.get_terminal_size = lambda _fd: os.terminal_size((160, 50))
try:
    wizard.draw(
        5,
        "Review and confirm",
        ["TARGET DISK /dev/sda", "ALL DATA ON THE TARGET DISK WILL BE ERASED."],
        danger=True,
        prompt_label="Confirmation",
    )
finally:
    module.os.get_terminal_size = original_terminal_size

rendered = wizard.tty.getvalue()
plain = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", rendered)
top = next((line for line in plain.splitlines() if "┏" in line), "")
if not top.startswith(" " * 22):
    fail("pannello da 116 colonne non centrato su una console da 160")
if len(top) != 22 + 116:
    fail("larghezza del pannello adattivo errata")
frame_lines = [line for line in plain.splitlines() if "┃" in line]
if any(len(line) != 22 + 116 for line in frame_lines):
    fail("bordo destro disallineato in una o più righe del pannello")
if "┃  Confirmation:" not in plain:
    fail("prompt di conferma non renderizzato dentro la cornice")
if f"{module.GREEN}┏" not in rendered:
    fail("cornice esterna non verde")
if f"{module.RED}ALL DATA ON THE TARGET DISK WILL BE ERASED." not in rendered:
    fail("avviso distruttivo non evidenziato in rosso")

print("Rendering wizard verificato a 160 colonne.")
