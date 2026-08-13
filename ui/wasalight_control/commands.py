# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
"""Uniform command execution for Control probes and actions."""
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

import subprocess
from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


class CommandRunner:
    def run(self, command: Sequence[str], *, timeout: int | None = None,
            merge_stderr: bool = False) -> CommandResult:
        result = subprocess.run(
            list(command), text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT if merge_stderr else subprocess.PIPE,
            timeout=timeout, check=False)
        return CommandResult(
            result.returncode,
            result.stdout or "",
            "" if merge_stderr else (result.stderr or ""))

    def spawn(self, command: Sequence[str], *, cwd: str | None = None):
        return subprocess.Popen(list(command), cwd=cwd, start_new_session=True)
