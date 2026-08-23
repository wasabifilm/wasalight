#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""WASALIGHT installer UI driven by structured Subiquity/curtin events."""

from __future__ import annotations

import json
import os
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


LISTEN_ADDRESS = "127.0.0.1"
LISTEN_PORT = 8765
READY_FILE = Path("/run/wasalight-ui-ready")
PID_FILE = Path("/run/wasalight-ui.pid")
SUCCESS_FILE = Path("/run/wasalight-install-success")
FAILURE_FILE = Path("/run/wasalight-install-failed")


def read_installer_version() -> str:
    candidates = (
        Path(__file__).resolve().parent / "VERSION",
        Path("/cdrom/wasalight/VERSION"),
        Path("/wasalight/VERSION"),
    )
    for candidate in candidates:
        try:
            value = candidate.read_text(encoding="ascii").strip()
        except OSError:
            continue
        if value.isdigit():
            return value
    return "?"


INSTALLER_VERSION = read_installer_version()

GREEN = "\033[1;32m"
RED = "\033[1;31m"
YELLOW = "\033[1;33m"
WHITE = "\033[1;37m"
DIM = "\033[0;37m"
RESET = "\033[0m"
CLEAR = "\033[2J\033[H"
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"

STAGES = (
    ("prepare", "Preparation"),
    ("disk", "Disk and filesystems"),
    ("base", "Base system"),
    ("configure", "System configuration"),
    ("boot", "Kernel and bootloader"),
    ("finalize", "Finalization"),
)
STAGE_INDEX = {key: index for index, (key, _label) in enumerate(STAGES)}
STAGE_MESSAGES = {
    "prepare": "Preparing the installation",
    "disk": "Preparing the disk and filesystems",
    "base": "Installing the base system",
    "configure": "Configuring the system",
    "boot": "Installing the kernel and bootloader",
    "finalize": "Finalizing the installation",
}


class InstallerState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.active_stage = "prepare"
        self.completed: set[str] = set()
        self.warning_stages: set[str] = set()
        self.message = "Starting the installation"
        self.failed = False
        self.failure_message = ""
        self.finished = False

    def update(self, event: dict[str, Any]) -> None:
        event_type = str(event.get("event_type", "")).lower()
        name = str(event.get("name", ""))
        description = clean_text(str(event.get("description", "")))
        result = str(event.get("result", "")).upper()
        stage = stage_for_event(name, description)

        with self.lock:
            if stage is not None:
                self._activate(stage)
                self.message = STAGE_MESSAGES[stage]
                if event_type == "finish" and result in {"SUCCESS", "WARN"}:
                    self.completed.add(stage)
                if result == "WARN":
                    self.warning_stages.add(stage)

            if event_type == "finish" and result == "FAIL":
                self.failed = True
                self.failure_message = description or name or "Installation failed"

    def _activate(self, stage: str) -> None:
        current_index = STAGE_INDEX[self.active_stage]
        new_index = STAGE_INDEX[stage]
        if new_index < current_index:
            return
        for key, _label in STAGES[:new_index]:
            self.completed.add(key)
        self.active_stage = stage

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return {
                "active_stage": self.active_stage,
                "completed": set(self.completed),
                "warnings": set(self.warning_stages),
                "message": self.message,
                "failed": self.failed,
                "failure_message": self.failure_message,
                "finished": self.finished,
            }

    def mark_success(self) -> None:
        with self.lock:
            self.completed.update(key for key, _label in STAGES)
            self.active_stage = "finalize"
            self.message = "Installation completed successfully"
            self.finished = True

    def mark_failure(self, message: str) -> None:
        with self.lock:
            self.failed = True
            self.failure_message = message


STATE = InstallerState()


def clean_text(value: str) -> str:
    value = " ".join(value.split())
    return "".join(character for character in value if character.isprintable())[:72]


def stage_for_event(name: str, description: str) -> str | None:
    value = f"{name} {description}".lower()
    if any(token in value for token in ("stage-partition", "block-meta", "mkfs", "filesystem")):
        return "disk"
    if any(token in value for token in ("stage-extract", "/extract", "copying image", "installing system")):
        return "base"
    if any(token in value for token in ("curthooks", "system-upgrade", "apt-config", "network config")):
        return "configure"
    if any(token in value for token in ("install-grub", "grub-install", "bootloader", "install-kernel", "initramfs")):
        return "boot"
    if any(token in value for token in ("stage-late", "late-commands", "finalize")):
        return "finalize"
    return None


class EventHandler(BaseHTTPRequestHandler):
    server_version = f"WasalightReporter/{INSTALLER_VERSION}"

    def do_POST(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0

        # Events are small. Consume but do not retain oversized file reports.
        if length > 1024 * 1024:
            remaining = length
            while remaining > 0:
                chunk = self.rfile.read(min(remaining, 65536))
                if not chunk:
                    break
                remaining -= len(chunk)
            self.send_response(204)
            self.end_headers()
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if isinstance(payload, dict) and payload.get("origin") != "files":
                STATE.update(payload)
        except (UnicodeDecodeError, json.JSONDecodeError):
            pass

        self.send_response(204)
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


class LocalServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def read_first_line(path: str) -> str:
    try:
        return clean_text(Path(path).read_text(encoding="utf-8").splitlines()[0])
    except (OSError, IndexError):
        return ""


def fit(value: str, width: int) -> str:
    return value[:width]


def stage_symbol(key: str, snapshot: dict[str, Any], spinner: str) -> tuple[str, str]:
    if key in snapshot["warnings"]:
        return YELLOW, "!"
    if key in snapshot["completed"]:
        return GREEN, "✓"
    if key == snapshot["active_stage"] and not snapshot["finished"]:
        return GREEN, spinner
    return DIM, "○"


def render(tty: Any, spinner: str) -> None:
    snapshot = STATE.snapshot()
    disk = read_first_line("/run/wasalight-target-disk")
    size = read_first_line("/run/wasalight-target-size")
    model = read_first_line("/run/wasalight-target-model")
    boot_mode = read_first_line("/run/wasalight-boot-mode")
    keyboard = read_first_line("/run/wasalight-keyboard-label")
    timezone = read_first_line("/run/wasalight-timezone-label")
    variant = read_first_line("/run/wasalight-install-variant") or "INSTALL"
    title = f"WASALIGHT INSTALLER v{INSTALLER_VERSION} · {variant}"
    ubuntu_title = "Ubuntu Server __WASALIGHT_UBUNTU_VERSION__ LTS"
    if variant == "FULL":
        network_note = "Local Ubuntu media · Internet required for Wasalight"
    else:
        network_note = "Internet required for Ubuntu and Wasalight"

    lines = [
        CLEAR + HIDE_CURSOR,
        GREEN + "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" + RESET,
        GREEN + f"┃{title:^60}┃" + RESET,
        GREEN + f"┃{ubuntu_title:^60}┃" + RESET,
        GREEN + f"┃{network_note:^60}┃" + RESET,
        GREEN + "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫" + RESET,
        "┃                                                            ┃",
    ]

    for key, label in STAGES:
        color, symbol = stage_symbol(key, snapshot, spinner)
        lines.append(f"┃   {color}{symbol}{RESET}  {label:<54}┃")

    lines.extend(("┃                                                            ┃",))
    if snapshot["failed"]:
        message = snapshot["failure_message"] or "Installation failed"
        lines.append(f"┃   {RED}{message[:54]:<54}{RESET}   ┃")
    elif snapshot["finished"]:
        lines.append(f"┃   {GREEN}{'Installation complete. Preparing safe power-off.':<54}{RESET}   ┃")
    else:
        lines.append(f"┃   {WHITE}{snapshot['message'][:54]:<54}{RESET}   ┃")

    lines.extend(
        (
            "┃                                                            ┃",
            GREEN + "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫" + RESET,
            f"┃  Disk: {fit((disk + ' ' + size).strip(), 52):<52}┃",
            f"┃  Model: {fit(model, 51):<51}┃",
            f"┃  Boot: {fit(boot_mode, 52):<52}┃",
            f"┃  Keyboard: {fit(keyboard, 48):<48}┃",
            f"┃  Time zone: {fit(timezone, 47):<47}┃",
            f"┃  Account: {'chamsys · password configured':<49}┃",
            GREEN + "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫" + RESET,
            f"┃  {DIM}{'Technical logs: Ctrl+Alt+F1':<58}{RESET}┃",
            GREEN + "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" + RESET,
        )
    )
    tty.write("\n".join(lines) + "\n")
    tty.flush()


def main() -> int:
    tty_path = sys.argv[1] if len(sys.argv) > 1 else "/dev/tty2"
    if not os.path.exists(tty_path):
        tty_path = "/dev/console"

    try:
        server = LocalServer((LISTEN_ADDRESS, LISTEN_PORT), EventHandler)
    except OSError as exc:
        FAILURE_FILE.write_text(f"UI reporter unavailable: {exc}\n", encoding="utf-8")
        return 1

    READY_FILE.write_text(f"{LISTEN_ADDRESS}:{LISTEN_PORT}\n", encoding="utf-8")
    PID_FILE.write_text(f"{os.getpid()}\n", encoding="ascii")
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    stopped = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    spinner_frames = "◐◓◑◒"
    frame = 0
    with open(tty_path, "w", encoding="utf-8", buffering=1) as tty:
        try:
            while not stopped:
                if SUCCESS_FILE.exists() and not STATE.snapshot()["finished"]:
                    STATE.mark_success()
                if FAILURE_FILE.exists() and not STATE.snapshot()["failed"]:
                    STATE.mark_failure(read_first_line(str(FAILURE_FILE)))
                render(tty, spinner_frames[frame % len(spinner_frames)])
                frame += 1
                time.sleep(0.5)
        finally:
            tty.write(SHOW_CURSOR + RESET)
            tty.flush()
            server.shutdown()
            READY_FILE.unlink(missing_ok=True)
            PID_FILE.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
