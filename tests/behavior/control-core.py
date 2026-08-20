#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Behavioral tests for the display-independent Wasalight Control core."""

import json
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


PROJECT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_DIR / "ui"))

from wasalight_control.commands import CommandResult, CommandRunner
from wasalight_control import i18n
from wasalight_control.launchers import installed_launchers, read_launcher
from wasalight_control.models import ControlPaths
from wasalight_control.models import MagicQState
from wasalight_control.overview_state import parse_status_report
from wasalight_control.system import magicq_state, mode_and_version, read_plugins, read_status
from wasalight_control import theme


class FakeRunner:
    def __init__(self, results):
        self.results = list(results)
        self.calls = []

    def run(self, command, **options):
        self.calls.append((list(command), options))
        return self.results.pop(0)


class LauncherTests(unittest.TestCase):
    def test_discovery_is_typed_filtered_deduplicated_and_ordered(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            system = root / "system"
            persistent = root / "persistent"
            desktop = root / "desktop"
            for directory in (system, persistent, desktop):
                directory.mkdir()
            (system / "support.desktop").write_text(
                "[Desktop Entry]\nName=Support\nExec=help-tool\n"
                "X-Wasalight-Section=Support\nX-Wasalight-Order=20\n",
                encoding="utf-8")
            (persistent / "duplicate.desktop").write_text(
                "[Desktop Entry]\nName=Support\nExec=help-tool\n",
                encoding="utf-8")
            (persistent / "application.desktop").write_text(
                "[Desktop Entry]\nName=Scanner\nExec=scan-tool\n"
                "Terminal=not-a-boolean\nX-Wasalight-Order=10\n",
                encoding="utf-8")
            (desktop / "magicvis.desktop").write_text(
                "[Desktop Entry]\nName=MagicVis\nExec=runmagicvis.sh\n",
                encoding="utf-8")
            (desktop / "unrelated.desktop").write_text(
                "[Desktop Entry]\nName=Editor\nExec=editor\n",
                encoding="utf-8")
            paths = ControlPaths(
                system_apps_dir=str(system),
                persistent_apps_dir=str(persistent),
                desktop_apps_dir=str(desktop))

            launchers = installed_launchers(paths)

            self.assertEqual(
                [(item.name, item.section) for item in launchers],
                [("Scanner", "Applications"), ("MagicVis", "MagicQ"),
                 ("Support", "Support")])
            self.assertFalse(launchers[0].terminal)
            self.assertEqual(launchers[0].command, "scan-tool")

    def test_missing_try_exec_hides_launcher(self):
        with tempfile.TemporaryDirectory() as temporary:
            launcher = Path(temporary) / "missing.desktop"
            launcher.write_text(
                "[Desktop Entry]\nName=Missing\nExec=missing\nTryExec=missing\n",
                encoding="utf-8")
            self.assertIsNone(read_launcher(str(launcher), which=lambda _name: None))


class SystemProbeTests(unittest.TestCase):
    def test_paths_and_runner_are_injectable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            version = root / "version"
            autostart = root / "magicq-autostart"
            version.write_text("2026.08.12.1\n", encoding="utf-8")
            autostart.write_text("enabled\n", encoding="utf-8")
            paths = ControlPaths(
                version_file=str(version),
                magicq_autostart_file=str(autostart))
            runner = FakeRunner([
                CommandResult(0, "overlay\n", ""),
                CommandResult(0, "", ""),
            ])

            identity = mode_and_version(paths, runner)
            state = magicq_state(paths, runner)

            self.assertEqual((identity.mode, identity.version),
                             ("SHOW", "2026.08.12.1"))
            self.assertTrue(state.running)
            self.assertTrue(state.automatic)

    def test_status_and_plugins_preserve_command_contracts(self):
        paths = ControlPaths(plugin_command="plugin-test", status_command="status-test")
        runner = FakeRunner([
            CommandResult(0, json.dumps([{"id": "ssh"}]), ""),
            CommandResult(0, "healthy\n", ""),
        ])

        self.assertEqual(read_plugins(paths, runner), [{"id": "ssh"}])
        self.assertEqual(read_status(paths, runner), "healthy")
        self.assertEqual(runner.calls, [
            (["plugin-test", "list", "--json"], {"timeout": 20}),
            (["status-test"], {"timeout": 20, "merge_stderr": True}),
        ])


class CommandRunnerTests(unittest.TestCase):
    def test_result_does_not_expose_subprocess_details(self):
        result = CommandRunner().run(
            [sys.executable, "-c", "import sys; print('ok'); print('bad', file=sys.stderr)"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "ok")
        self.assertEqual(result.stderr.strip(), "bad")


def write_mo(path, messages):
    """Write the small GNU MO fixture needed by the localization tests."""
    keys = sorted(messages)
    originals = [key.encode("utf-8") for key in keys]
    translations = [messages[key].encode("utf-8") for key in keys]
    count = len(keys)
    originals_offset = 28
    translations_offset = originals_offset + count * 8
    strings_offset = translations_offset + count * 8
    original_blob = b"".join(value + b"\0" for value in originals)
    translation_blob = b"".join(value + b"\0" for value in translations)
    original_table = []
    translation_table = []
    offset = strings_offset
    for value in originals:
        original_table.extend((len(value), offset))
        offset += len(value) + 1
    offset = strings_offset + len(original_blob)
    for value in translations:
        translation_table.extend((len(value), offset))
        offset += len(value) + 1
    payload = struct.pack("<7I", 0x950412DE, 0, count,
                          originals_offset, translations_offset, 0, 0)
    payload += struct.pack(f"<{count * 2}I", *original_table)
    payload += struct.pack(f"<{count * 2}I", *translation_table)
    path.write_bytes(payload + original_blob + translation_blob)


class LocalizationTests(unittest.TestCase):
    def test_explicit_language_loads_catalog_and_invalid_value_falls_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog = root / "it" / "LC_MESSAGES" / "wasalight-control.mo"
            catalog.parent.mkdir(parents=True)
            write_mo(catalog, {
                "": "Content-Type: text/plain; charset=UTF-8\nLanguage: it\n",
                "Close": "Chiudi",
            })
            preference = root / "control-language"
            preference.write_text("it\n", encoding="utf-8")
            with mock.patch.dict(os.environ, {}, clear=False):
                os.environ.pop("WASALIGHT_CONTROL_LANGUAGE", None)
                self.assertEqual(i18n.configure(
                    language_file=str(preference), locale_dir=str(root)), "it")
                self.assertEqual(i18n._("Close"), "Chiudi")
                preference.write_text("invalid\n", encoding="utf-8")
                self.assertEqual(i18n.configure(
                    language_file=str(preference), locale_dir=str(root)), "auto")

    def test_language_preference_is_validated_and_written_atomically(self):
        with tempfile.TemporaryDirectory() as temporary:
            preference = Path(temporary) / "system" / "control-language"
            i18n.save_language("en", language_file=str(preference))
            self.assertEqual(preference.read_text(encoding="utf-8"), "en\n")
            self.assertEqual(preference.stat().st_mode & 0o777, 0o640)
            with self.assertRaises(ValueError):
                i18n.save_language("xx", language_file=str(preference))


class ThemeTests(unittest.TestCase):
    @staticmethod
    def write_theme(path, *, name="Test Console", invalid_token=None):
        colors = dict(theme.DEFAULT_PALETTE)
        if invalid_token:
            colors[invalid_token] = "not-a-colour"
        body = "[theme]\nname=" + name + "\n\n[colors]\n"
        body += "".join(f"{key}={value}\n" for key, value in colors.items())
        path.write_text(body, encoding="utf-8")

    def test_external_theme_loading_and_invalid_fallback(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            custom = root / "custom.ini"
            self.write_theme(custom)
            self.assertEqual(
                theme.configure(theme_path=str(custom)), "Test Console")
            self.assertEqual(theme.current_theme_name(), "Test Console")
            self.write_theme(custom, invalid_token="brand")
            self.assertEqual(
                theme.configure(theme_path=str(custom)), "Console Dark")
            self.assertEqual(theme.current_palette(), theme.DEFAULT_PALETTE)

class OverviewStateTests(unittest.TestCase):
    def test_ready_report_exposes_real_operational_states(self):
        report = """MagicQ Appliance
MODE:       PROTECTED
DATA:       /dev/sda3 ext4 rw
MAGICQ:     RUNNING · 1.9.8.3 · AUTOMATIC
NETWORK:    persistent bind; managed
IP:         192.168.10.20
VNC:        stopped (manual)
SSH:        running on TCP 22 (automatic)
UPDATE:     up to date
"""
        snapshot = parse_status_report(
            report, MagicQState(running=True, automatic=True))
        self.assertEqual(snapshot.level, "good")
        self.assertTrue(snapshot.magicq_running)
        self.assertEqual(snapshot.network_level, "good")
        self.assertEqual(snapshot.network_ip, "192.168.10.20")
        self.assertTrue(snapshot.ssh_running)
        self.assertFalse(snapshot.vnc_running)
        self.assertEqual(snapshot.update_level, "good")

    def test_missing_data_or_unmanaged_network_requires_attention(self):
        report = """MagicQ Appliance
MODE:       PROTECTED
DATA:       NOT MOUNTED
MAGICQ:     READY · 1.9.8.3 · MANUAL
NETWORK:    volatile; unmanaged: enp2s0
IP:         unavailable
VNC:        stopped (manual)
SSH:        stopped (manual)
UPDATE:     AVAILABLE: 2026.08.13.1
"""
        snapshot = parse_status_report(report)
        self.assertEqual(snapshot.level, "error")
        self.assertEqual(snapshot.network_level, "error")
        self.assertEqual(snapshot.update_level, "warning")

    def test_incomplete_update_requires_recovery(self):
        report = """MagicQ Appliance
MODE:       MAINTENANCE
DATA:       /dev/sda3 ext4 rw
MAGICQ:     READY · 1.9.8.3 · MANUAL
NETWORK:    persistent bind; managed
IP:         192.168.10.20
VNC:        stopped (manual)
SSH:        stopped (manual)
UPDATE:     RECOVERY REQUIRED (failed)
"""
        snapshot = parse_status_report(report)
        self.assertEqual(snapshot.level, "error")
        self.assertEqual(snapshot.update_level, "error")


if __name__ == "__main__":
    unittest.main()
