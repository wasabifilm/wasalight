# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Testable core services for Wasalight Control."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

from .models import ControlPaths, Launcher, MagicQState, SystemIdentity
from .i18n import _, ngettext

__all__ = ["_", "ngettext", "ControlPaths", "Launcher", "MagicQState",
           "SystemIdentity"]
