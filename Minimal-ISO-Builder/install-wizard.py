#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Dependency-free Wasalight setup wizard; Subiquity remains the installer."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys
import termios
import textwrap


GREEN = "\033[1;32m"
BRIGHT = "\033[1;37m"
DIM = "\033[0;37m"
RED = "\033[1;31m"
RESET = "\033[0m"
CLEAR = "\033[2J\033[H"
STEPS = ("Language", "Keyboard", "Time zone", "Password", "Disk", "Review")
RUNTIME_DIR = Path(os.environ.get("WASALIGHT_RUNTIME_DIR", "/run"))
ANSI_PATTERN = re.compile(r"\x1b\[[0-9;]*m")


class WizardError(RuntimeError):
    """A validation or backend error safe to show to the operator."""


def write_failure_log(message: str) -> None:
    try:
        (RUNTIME_DIR / "wasalight-wizard.log").write_text(
            message.strip() + "\n", encoding="utf-8")
    except OSError:
        pass


class Wizard:
    def __init__(self, tty_path: str) -> None:
        self.tty_path = tty_path if os.path.exists(tty_path) else "/dev/console"
        # Character devices are not seekable, so Python cannot safely open one
        # in update (r+) mode. Separate descriptors also avoid any buffered
        # read/write direction switch while the wizard is active.
        self.reader = open(self.tty_path, "r", encoding="utf-8", buffering=1)
        self.tty = open(self.tty_path, "w", encoding="utf-8", buffering=1)
        self.base = Path(__file__).resolve().parent
        self.keyboard_backend = self.base / "select-keyboard.sh"
        self.disk_backend = self.base / "select-disk.sh"
        self.version = self._read_version()
        self.variant = self._runtime_value("wasalight-install-variant", "INSTALL")
        self.preflight = self._runtime_value("wasalight-preflight-status", "ready")
        self.language = ("it", "Italiano")
        self.keyboard = ("it", "", "Italian")
        self.timezone = "Europe/Rome"
        self.password_hash = ""
        self.disk: dict[str, str] | None = None
        self.pending_prompt: str | None = None

    def _read_version(self) -> str:
        value = (self.base / "VERSION").read_text(encoding="ascii").strip()
        if not value.isdigit():
            raise WizardError("Installer VERSION is invalid.")
        return value

    @staticmethod
    def _runtime_value(name: str, default: str = "") -> str:
        try:
            return (RUNTIME_DIR / name).read_text(encoding="utf-8").splitlines()[0]
        except (OSError, IndexError):
            return default

    def close(self) -> None:
        self.tty.write("\033[?25h" + RESET)
        self.tty.close()
        self.reader.close()

    def run_backend(self, program: Path, *arguments: str) -> str:
        result = subprocess.run(
            [str(program), *arguments], text=True, capture_output=True, check=False)
        if result.returncode:
            message = result.stderr.strip() or result.stdout.strip() or "Backend operation failed."
            raise WizardError(message.removeprefix("ERROR: ").strip())
        return result.stdout.strip()

    def draw(
        self, step: int, title: str, body: list[str], *, danger: bool = False,
        prompt_label: str | None = None,
    ) -> None:
        try:
            terminal = os.get_terminal_size(self.tty.fileno())
            terminal_width, terminal_height = terminal.columns, terminal.lines
        except OSError:
            terminal_width, terminal_height = 80, 24
        width = max(64, min(116, terminal_width - 4))
        inner = width - 2
        margin = max(0, (terminal_width - width) // 2)
        prefix = " " * margin
        accent = GREEN
        progress = []
        for index, label in enumerate(STEPS):
            if index < step:
                progress.append(f"{GREEN}✓ {label}{RESET}")
            elif index == step:
                progress.append(f"{BRIGHT}[{index + 1} {label}]{RESET}")
            else:
                progress.append(f"{DIM}{index + 1} {label}{RESET}")
        progress_line = "   ".join(progress)
        if len(ANSI_PATTERN.sub("", progress_line)) > inner - 4:
            progress_line = "   ".join(
                f"{GREEN}✓{index + 1}{RESET}" if index < step else
                f"{BRIGHT}[{index + 1}]{RESET}" if index == step else
                f"{DIM}{index + 1}{RESET}"
                for index in range(len(STEPS)))

        wrapped_body: list[str] = []
        for source_line in body:
            wrapped_body.extend(textwrap.wrap(source_line, width=inner - 6) or [""])
        fixed_lines = 14 + (2 if prompt_label else 0)
        top_margin = max(0, (terminal_height - fixed_lines - len(wrapped_body)) // 3)

        self.pending_prompt = prompt_label
        self.tty.write(CLEAR + "\033[?25h" + "\n" * top_margin)
        self.tty.write(prefix + accent + "┏" + "━" * inner + "┓\n" + RESET)
        heading = f"WASALIGHT INSTALLER v{self.version} · {self.variant}"
        self.tty.write(prefix + accent + f"┃{heading:^{inner}}┃\n" + RESET)
        self.tty.write(prefix + accent + "┣" + "━" * inner + "┫\n" + RESET)
        self.tty.write(prefix + f"┃  {self._pad_ansi(progress_line, inner - 4)}  ┃\n")
        self.tty.write(prefix + accent + "┣" + "━" * inner + "┫\n" + RESET)
        title_color = RED if danger else BRIGHT
        self.tty.write(prefix + f"┃  {title_color}{title:<{inner - 4}}{RESET}  ┃\n")
        self.tty.write(prefix + "┃" + " " * inner + "┃\n")
        for line in wrapped_body:
            destructive = any(token in line for token in (
                "ALL DATA", "TARGET DISK", "ERASE to start", "[REMOVABLE]", "[USB]"))
            color = RED if destructive else ""
            reset = RESET if destructive else ""
            self.tty.write(prefix + f"┃   {color}{line}{reset}{' ' * (inner - 3 - len(line))}┃\n")
        self.tty.write(prefix + "┃" + " " * inner + "┃\n")
        self.tty.write(prefix + accent + "┣" + "━" * inner + "┫\n" + RESET)
        footer = "Q Quit" if step == 0 else "B Back   ·   Q Quit"
        self.tty.write(prefix + f"┃  {DIM}{footer:<{inner - 4}}{RESET}  ┃\n")
        if prompt_label:
            self.tty.write(prefix + accent + "┣" + "━" * inner + "┫\n" + RESET)
            prompt = f"{prompt_label}: "
            self.tty.write(prefix + f"┃  {BRIGHT}{prompt:<{inner - 4}}{RESET}  ┃\n")
        self.tty.write(prefix + accent + "┗" + "━" * inner + "┛\n" + RESET)
        if prompt_label:
            cursor_column = margin + 3 + len(prompt_label) + 2
            self.tty.write(f"\033[2A\r\033[{cursor_column}C")
        self.tty.flush()

    @staticmethod
    def _pad_ansi(value: str, width: int) -> str:
        visible = len(ANSI_PATTERN.sub("", value))
        return value + " " * max(0, width - visible)

    def prompt(self, label: str, *, secret: bool = False) -> str:
        inline = self.pending_prompt == label
        if secret:
            if not inline:
                self.tty.write(f"{label}: ")
                self.tty.flush()
            attributes = termios.tcgetattr(self.reader.fileno())
            hidden = attributes.copy()
            hidden[3] &= ~termios.ECHO
            try:
                termios.tcsetattr(self.reader.fileno(), termios.TCSADRAIN, hidden)
                value = self.reader.readline().rstrip("\n")
            finally:
                termios.tcsetattr(self.reader.fileno(), termios.TCSADRAIN, attributes)
                self.tty.write("\n")
            self.pending_prompt = None
            return value
        if not inline:
            self.tty.write(f"{label}: ")
            self.tty.flush()
        value = self.reader.readline().rstrip("\n")
        self.pending_prompt = None
        return value

    @staticmethod
    def navigation(value: str, *, allow_back: bool = True) -> str | None:
        lowered = value.strip().lower()
        if lowered == "q":
            raise KeyboardInterrupt
        if allow_back and lowered == "b":
            return "back"
        return None

    def error(self, step: int, message: str) -> None:
        self.draw(step, "Cannot continue", [message], danger=True, prompt_label="Press ENTER")
        self.prompt("Press ENTER")

    def choose_language(self) -> str:
        while True:
            self.draw(0, "Wasalight interface language", [
                "Choose the language used by Wasalight, its menus and icon labels.",
                "",
                "1  Italiano   (default)",
                "2  English",
                "",
                "This choice is independent from the keyboard layout.",
            ], prompt_label="Selection [1]")
            value = self.prompt("Selection [1]")
            self.navigation(value, allow_back=False)
            if value in ("", "1"):
                self.language = ("it", "Italiano")
                return "next"
            if value == "2":
                self.language = ("en", "English")
                return "next"
            self.error(0, "Select 1 or 2.")

    def choose_keyboard(self) -> str:
        presets = {
            "1": ("it", "", "Italian"), "2": ("us", "", "English (US)"),
            "3": ("gb", "", "English (UK)"), "4": ("de", "", "Deutsch"),
            "5": ("fr", "", "Francais"), "6": ("es", "", "Espanol"),
            "7": ("ch", "de", "Swiss German"), "8": ("ch", "fr", "Swiss French"),
        }
        while True:
            self.draw(1, "Keyboard layout", [
                "1  Italian                 5  Francais",
                "2  English (US)            6  Espanol",
                "3  English (UK)            7  Swiss German",
                "4  Deutsch                  8  Swiss French",
                "9  Other XKB layout",
                "",
                f"Interface language: {self.language[1]} (unchanged by this choice)",
            ], prompt_label="Selection")
            value = self.prompt("Selection")
            if self.navigation(value) == "back":
                return "back"
            if value == "9":
                self.draw(1, "Custom keyboard layout", [
                    "Enter an XKB layout code, for example: pl, pt or no.",
                ], prompt_label="XKB layout code")
                layout = self.prompt("XKB layout code")
                if self.navigation(layout) == "back":
                    continue
                self.draw(1, "Custom keyboard variant", [
                    f"Layout: {layout}",
                    "Leave the variant empty to use the layout default.",
                ], prompt_label="XKB variant [default]")
                variant = self.prompt("XKB variant [default]")
                try:
                    self.run_backend(self.keyboard_backend, "--validate-layout", layout, variant)
                except WizardError as error:
                    self.error(1, str(error) or "Invalid or unavailable XKB layout/variant.")
                    continue
                selected = (layout, variant, f"{layout} ({variant})" if variant else layout)
            elif value in presets:
                selected = presets[value]
            else:
                self.error(1, "Select a keyboard layout from 1 to 9.")
                continue
            try:
                self.run_backend(self.keyboard_backend, "--apply-live-keyboard", selected[0], selected[1])
            except WizardError as error:
                self.error(1, str(error))
                continue
            self.draw(1, "Test keyboard", [
                f"Active layout: {selected[2]}",
                "Type a short test including symbols such as @, /, - or _.",
            ], prompt_label="Test")
            typed = self.prompt("Test")
            self.draw(1, "Confirm keyboard", [
                f"Active layout: {selected[2]}",
                f"You typed: {typed}",
            ], prompt_label="Is this correct? [Y/n]")
            confirmed = self.prompt("Is this correct? [Y/n]")
            if confirmed.lower() in ("", "y", "yes"):
                self.keyboard = selected
                return "next"

    def choose_timezone(self) -> str:
        zones = {
            "1": "Europe/Rome", "2": "Europe/Zurich", "3": "Europe/London",
            "4": "Europe/Berlin", "5": "Europe/Paris", "6": "Europe/Madrid",
            "7": "Etc/UTC",
        }
        while True:
            self.draw(2, "Time zone", [
                "1  Italy          Europe/Rome       5  France          Europe/Paris",
                "2  Switzerland    Europe/Zurich     6  Spain           Europe/Madrid",
                "3  United Kingdom Europe/London     7  UTC             Etc/UTC",
                "4  Germany        Europe/Berlin     8  Other IANA zone",
            ], prompt_label="Selection [1]")
            value = self.prompt("Selection [1]")
            if self.navigation(value) == "back":
                return "back"
            if value in ("", "1"):
                zone = zones["1"]
            elif value in zones:
                zone = zones[value]
            elif value == "8":
                self.draw(2, "Custom time zone", [
                    "Enter an IANA time zone, for example America/New_York.",
                ], prompt_label="IANA time zone")
                zone = self.prompt("IANA time zone")
            else:
                self.error(2, "Select a time zone from 1 to 8.")
                continue
            try:
                self.run_backend(self.keyboard_backend, "--validate-timezone", zone)
            except WizardError:
                self.error(2, f"Invalid or unavailable time zone: {zone}")
                continue
            self.timezone = zone
            return "next"

    def choose_password(self) -> str:
        while True:
            self.draw(3, "Administrator password", [
                "Set the password for the chamsys administrator account.",
                "It must contain at least 6 characters and is never displayed.",
                "Type B at the first password prompt to return to the previous step.",
            ], prompt_label="Password")
            password = self.prompt("Password", secret=True)
            if password.lower() == "b":
                return "back"
            if password.lower() == "q":
                raise KeyboardInterrupt
            if len(password) < 6:
                self.error(3, "The password is too short.")
                continue
            self.draw(3, "Repeat administrator password", [
                "Type the same password again to confirm it.",
                "The password remains hidden.",
            ], prompt_label="Repeat password")
            repeated = self.prompt("Repeat password", secret=True)
            if password != repeated:
                self.error(3, "The passwords do not match.")
                continue
            result = subprocess.run(
                ["openssl", "passwd", "-6", "-stdin"], input=password + "\n",
                text=True, capture_output=True, check=False)
            password = repeated = ""
            if result.returncode or not result.stdout.startswith("$6$"):
                self.error(3, "Unable to generate the password hash.")
                continue
            self.password_hash = result.stdout.strip()
            return "next"

    def available_disks(self) -> list[dict[str, str]]:
        output = self.run_backend(self.disk_backend, "--list-disks")
        disks = []
        for line in output.splitlines():
            fields = line.split("|")
            if len(fields) != 7:
                raise WizardError("Disk backend returned invalid data.")
            disks.append(dict(zip(
                ("number", "device", "size", "model", "serial", "transport", "removable"),
                fields, strict=True)))
        return disks

    def choose_disk(self) -> str:
        while True:
            try:
                disks = self.available_disks()
            except WizardError as error:
                self.error(4, str(error))
                continue
            body = [
                "Select the target disk. The installation media is excluded and disks below 32 GiB are hidden.",
                "",
            ]
            for disk in disks:
                flags = []
                if disk["removable"] == "1":
                    flags.append("REMOVABLE")
                if disk["transport"] == "usb":
                    flags.append("USB")
                suffix = f"  [{' '.join(flags)}]" if flags else ""
                body.append(f"{disk['number']}  {disk['device']}  {disk['size']}  {disk['model']}{suffix}")
                if disk["serial"]:
                    body.append(f"   Serial: {disk['serial']}")
            if not disks:
                body.extend(("No installable disk was found.", "Press R to rescan."))
            disk_prompt = "Disk number" if disks else "R rescan"
            self.draw(4, "Installation disk", body, danger=True, prompt_label=disk_prompt)
            value = self.prompt(disk_prompt)
            if self.navigation(value) == "back":
                return "back"
            if not disks and value.lower() == "r":
                continue
            selected = next((disk for disk in disks if disk["number"] == value), None)
            if selected is None:
                self.error(4, "Select one of the listed disk numbers.")
                continue
            self.disk = selected
            return "next"

    def review(self) -> str:
        assert self.disk is not None
        boot_mode = self.run_backend(self.disk_backend, "--boot-mode")
        disk = self.disk
        self.draw(5, "Review and confirm", [
            f"Mode                 {self.variant}",
            f"Preflight            {self.preflight}",
            f"Interface language   {self.language[1]}",
            f"Keyboard             {self.keyboard[2]}",
            f"Time zone            {self.timezone}",
            "Password             configured",
            f"Boot mode            {boot_mode}",
            "",
            f"TARGET DISK          {disk['device']}  {disk['size']}",
            f"Model                {disk['model']}",
            f"Serial               {disk['serial'] or 'not reported'}",
            "",
            "Storage: GPT, EFI, /boot and LVM; / uses 50%, /data uses the rest.",
            "ALL DATA ON THE TARGET DISK WILL BE ERASED.",
            "Type exactly ERASE to start. Nothing is formatted before this confirmation.",
        ], danger=True, prompt_label="Confirmation")
        value = self.prompt("Confirmation")
        if self.navigation(value) == "back":
            return "back"
        if value != "ERASE":
            self.error(5, "Confirmation did not match. Nothing was changed.")
            return "again"
        return "next"

    def apply(self) -> None:
        assert self.disk is not None
        config = RUNTIME_DIR / "wasalight-wizard-config"
        values = (
            self.language[0], self.language[1], self.keyboard[0], self.keyboard[1],
            self.keyboard[2], self.timezone, self.password_hash,
        )
        if any("\n" in value or "\r" in value for value in values):
            raise WizardError("Wizard configuration contains an invalid newline.")
        descriptor = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as destination:
                destination.write("\n".join(values) + "\n")
            self.run_backend(self.keyboard_backend, "--apply-config", str(config))
        finally:
            try:
                config.unlink()
            except FileNotFoundError:
                pass
            self.password_hash = ""
        # The disk backend rebuilds its list and repeats all safety checks here.
        self.run_backend(self.disk_backend, "--apply-target", self.disk["device"])

    def complete(self) -> None:
        self.draw(5, "Configuration accepted", [
            "The target disk was revalidated successfully.",
            "Subiquity will now install Ubuntu and Wasalight using these settings.",
            "Installation progress is available on Ctrl+Alt+F2.",
        ])

    def run(self) -> int:
        handlers = (
            self.choose_language, self.choose_keyboard, self.choose_timezone,
            self.choose_password, self.choose_disk, self.review,
        )
        step = 0
        while step < len(handlers):
            result = handlers[step]()
            if result == "back":
                step = max(0, step - 1)
            elif result == "next":
                step += 1
        self.apply()
        self.complete()
        return 0


def main() -> int:
    tty_path = sys.argv[1] if len(sys.argv) > 1 else "/dev/tty1"
    wizard: Wizard | None = None
    try:
        wizard = Wizard(tty_path)
        return wizard.run()
    except KeyboardInterrupt:
        write_failure_log("Installer setup cancelled by the operator.")
        if wizard is not None:
            wizard.draw(0, "Installation cancelled", [
                "No disk configuration was accepted. Subiquity will stop safely.",
            ], danger=True)
        return 130
    except (OSError, WizardError) as error:
        write_failure_log(f"Installer setup failed: {error}")
        if wizard is not None:
            wizard.draw(0, "Installer setup failed", [str(error)], danger=True)
        return 1
    finally:
        if wizard is not None:
            wizard.close()


if __name__ == "__main__":
    raise SystemExit(main())
