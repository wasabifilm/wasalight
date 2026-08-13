# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Semantic state derived from the human-readable appliance status report."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

from dataclasses import dataclass

from .models import MagicQState


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
    remote_detail: str
    update_level: str
    update_detail: str
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
    if update_lower.startswith("available"):
        update_level = "warning"
    elif update_lower == "up to date":
        update_level = "good"
    else:
        update_level = "neutral"

    critical = (
        data.upper() == "NOT MOUNTED"
        or magicq_detail.lower() in {"missing", "not installed"}
        or network_level == "error"
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
        remote_detail=" · ".join(remote_parts),
        update_level=update_level,
        update_detail=update_detail,
        raw_status=report,
    )
