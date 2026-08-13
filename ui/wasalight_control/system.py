"""Read-only appliance probes used by the GTK interface."""

import json

from .commands import CommandRunner
from .i18n import _
from .models import ControlPaths, MagicQState, SystemIdentity


def mode_and_version(paths: ControlPaths = ControlPaths(),
                     runner: CommandRunner | None = None) -> SystemIdentity:
    version = "unknown"
    try:
        with open(paths.version_file, encoding="utf-8") as source:
            version = source.read().strip()
    except OSError:
        pass
    result = (runner or CommandRunner()).run(
        ["findmnt", "-n", "-o", "FSTYPE", "/"])
    mode = "SHOW" if result.stdout.strip() == "overlay" else "MAINTENANCE"
    return SystemIdentity(mode=mode, version=version)


def magicq_state(paths: ControlPaths = ControlPaths(),
                 runner: CommandRunner | None = None) -> MagicQState:
    result = (runner or CommandRunner()).run(["pgrep", "-x", "mqqt"])
    automatic = False
    try:
        with open(paths.magicq_autostart_file, encoding="utf-8") as source:
            automatic = source.read().strip() == "enabled"
    except OSError:
        pass
    return MagicQState(running=result.returncode == 0, automatic=automatic)


def read_plugins(paths: ControlPaths = ControlPaths(),
                 runner: CommandRunner | None = None):
    result = (runner or CommandRunner()).run(
        [paths.plugin_command, "list", "--json"], timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or _("Plugin registry unavailable"))
    return json.loads(result.stdout)


def read_status(paths: ControlPaths = ControlPaths(),
                runner: CommandRunner | None = None) -> str:
    result = (runner or CommandRunner()).run(
        [paths.status_command], timeout=20, merge_stderr=True)
    return result.stdout.strip() or _("Status unavailable")
