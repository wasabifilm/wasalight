#!/usr/bin/env python3
"""Behavioral tests for the display-independent Wasalight Control core."""

import json
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_DIR / "ui"))

from wasalight_control.commands import CommandResult, CommandRunner
from wasalight_control.launchers import installed_launchers, read_launcher
from wasalight_control.models import ControlPaths
from wasalight_control.system import magicq_state, mode_and_version, read_plugins, read_status


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


if __name__ == "__main__":
    unittest.main()
