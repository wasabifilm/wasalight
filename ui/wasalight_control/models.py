"""Domain models and filesystem layout used by Wasalight Control."""

from dataclasses import dataclass


@dataclass(frozen=True)
class ControlPaths:
    """Runtime paths, injectable so the core can be tested off-appliance."""

    system_apps_dir: str = "/etc/wasalight/apps.d"
    persistent_apps_dir: str = "/data/system/apps.d"
    desktop_apps_dir: str = "/usr/share/applications"
    version_file: str = "/etc/wasalight/version"
    magicq_autostart_file: str = "/data/system/service-flags/magicq-autostart"
    plugin_command: str = "/usr/local/bin/wasalight-plugin"
    status_command: str = "/usr/local/bin/wasalight-status"
    update_terminal: str = "/usr/local/bin/wasalight-update-terminal"
    mode_toggle: str = "/usr/local/bin/wasalight-mode-toggle"
    magicq_start: str = "/usr/local/bin/magicq-start"
    companion_launcher: str = "/usr/local/sbin/wasalight-companion-launcher"
    remote_persistence: str = "/usr/local/sbin/wasalight-remote-persistence"


@dataclass(frozen=True)
class Launcher:
    name: str
    comment: str
    command: str
    icon: str
    terminal: bool
    working_directory: str | None
    section: str
    order: int


@dataclass(frozen=True)
class SystemIdentity:
    mode: str
    version: str


@dataclass(frozen=True)
class MagicQState:
    running: bool
    automatic: bool
