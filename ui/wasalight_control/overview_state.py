# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Semantic state derived from the human-readable appliance status report."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

from dataclasses import dataclass
import re

from .i18n import _
from .models import MagicQState


def localized_mode(value):
    return {
        "automatic": _("automatic"),
        "manual": _("manual"),
    }.get(value.lower(), value)


def localized_magicq_detail(value):
    """Translate status tokens while preserving MagicQ's version verbatim."""
    tokens = [token.strip() for token in value.split("·")]
    states = {
        "READY": _("READY"),
        "RUNNING": _("RUNNING"),
        "MISSING": _("MISSING"),
        "NOT INSTALLED": _("NOT INSTALLED"),
        "AUTOMATIC": _("AUTOMATIC"),
        "MANUAL": _("MANUAL"),
    }
    return " · ".join(states.get(token.upper(), token) for token in tokens)


def localized_service_detail(value):
    running = re.fullmatch(r"running on TCP ([0-9]+) \(([^)]+)\)", value,
                           flags=re.IGNORECASE)
    if running:
        return _("running on TCP {port} ({mode})").format(
            port=running.group(1), mode=localized_mode(running.group(2)))
    stopped = re.fullmatch(r"stopped \(([^)]+)\)", value,
                           flags=re.IGNORECASE)
    if stopped:
        return _("stopped ({mode})").format(
            mode=localized_mode(stopped.group(1)))
    return value


def localized_update_detail(value):
    lower = value.lower()
    if lower == "up to date":
        return _("up to date")
    if lower == "not checked":
        return _("not checked")
    prefix, separator, suffix = value.partition(":")
    if separator and prefix.strip().lower() == "available":
        return _("available: {version}").format(version=suffix.strip())
    recovery = re.fullmatch(r"recovery required(?: \((.*)\))?", value,
                            flags=re.IGNORECASE)
    if recovery:
        reason = recovery.group(1)
        return (_("recovery required ({reason})").format(reason=reason)
                if reason else _("recovery required"))
    return value


def localized_health_detail(value):
    """Translate the health state while preserving diagnostic details."""
    state, separator, detail = value.partition("·")
    localized_state = {
        "WARNING": _("WARNING"),
        "CHECK FAILED": _("CHECK FAILED"),
        "CHECKING": _("CHECKING"),
        "NOT CHECKED": _("NOT CHECKED"),
    }.get(state.strip().upper(), state.strip())
    return (f"{localized_state} · {detail.strip()}"
            if separator else localized_state)


@dataclass(frozen=True)
class OverviewSnapshot:
    level: str
    mode: str
    magicq_running: bool
    magicq_automatic: bool
    magicq_detail: str
    network_level: str
    network_detail: str
    network_ip: str
    ssh_running: bool
    vnc_running: bool
    ssh_detail: str
    vnc_detail: str
    remote_detail: str
    update_level: str
    update_detail: str
    health_level: str
    health_detail: str
    raw_status: str


def parse_status_report(report: str,
                        magicq: MagicQState | None = None) -> OverviewSnapshot:
    fields = {}
    for line in report.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip():
            fields[key.strip().upper()] = value.strip()

    mode = fields.get("MODE", "unknown").upper()
    data = fields.get("DATA", "unknown")
    magicq_detail = fields.get("MAGICQ", "unknown")
    network_detail = fields.get("NETWORK", "unknown")
    network_ip = fields.get("IP", "")
    ssh_detail = fields.get("SSH", "unknown")
    vnc_detail = fields.get("VNC", "unknown")
    update_detail = fields.get("UPDATE", "not checked")
    health_detail = fields.get("HEALTH", "not checked")

    if magicq is None:
        magicq_running = magicq_detail.lower().startswith("running")
        magicq_automatic = "automatic" in magicq_detail.lower()
    else:
        magicq_running = magicq.running
        magicq_automatic = magicq.automatic

    network_lower = network_detail.lower()
    if "unmanaged" in network_lower or network_lower == "unknown":
        network_level = "error"
    elif "managed" in network_lower:
        network_level = "good"
    else:
        network_level = "neutral"

    ssh_running = ssh_detail.lower().startswith("running")
    vnc_running = vnc_detail.lower().startswith("running")
    update_lower = update_detail.lower()
    if update_lower.startswith("recovery required"):
        update_level = "error"
    elif update_lower.startswith("available"):
        update_level = "warning"
    elif update_lower == "up to date":
        update_level = "good"
    else:
        update_level = "neutral"

    health_lower = health_detail.lower()
    if health_lower == "ok":
        health_level = "good"
    elif health_lower.startswith(("warning", "check failed")):
        health_level = "error"
    else:
        health_level = "neutral"

    critical = (
        data.upper() == "NOT MOUNTED"
        or magicq_detail.lower() in {"missing", "not installed"}
        or network_level == "error"
        or update_level == "error"
        or health_level == "error"
    )
    if critical:
        level = "error"
    elif mode == "MAINTENANCE" or update_level == "warning":
        level = "warning"
    else:
        level = "good"

    remote_parts = [f"SSH: {ssh_detail}", f"VNC: {vnc_detail}"]
    return OverviewSnapshot(
        level=level,
        mode=mode,
        magicq_running=magicq_running,
        magicq_automatic=magicq_automatic,
        magicq_detail=magicq_detail,
        network_level=network_level,
        network_detail=network_detail,
        network_ip=network_ip,
        ssh_running=ssh_running,
        vnc_running=vnc_running,
        ssh_detail=ssh_detail,
        vnc_detail=vnc_detail,
        remote_detail=" · ".join(remote_parts),
        update_level=update_level,
        update_detail=update_detail,
        health_level=health_level,
        health_detail=health_detail,
        raw_status=report,
    )
