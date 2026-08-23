#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -eu

# Subiquity on the configured Ubuntu release:
# progress_complete -> neutral -> Linux basic color index 4 ("dark blue")
# We keep every other console color untouched and replace only index 4.
#
# Wasalight brand green, shared with the updater: #76BD22 = 118, 189, 34.

TTY="${1:-/dev/tty1}"
INTERVAL=1

apply_palette() {
  python3 - "$TTY" <<'PY'
import fcntl
import os
import sys

GIO_CMAP = 0x4B70
PIO_CMAP = 0x4B71

tty = sys.argv[1]

try:
    fd = os.open(tty, os.O_RDWR | os.O_NOCTTY)
except OSError:
    sys.exit(0)

try:
    palette = bytearray(16 * 3)
    fcntl.ioctl(fd, GIO_CMAP, palette, True)

    # Subiquity maps its neutral progress color to VGA index 4. The custom
    # installer uses normal/bright green (indices 2 and 10). Keep all three on
    # the same Wasalight brand color used by the graphical updater.
    for index in (2, 4, 10):
        i = index * 3
        palette[i + 0] = 118
        palette[i + 1] = 189
        palette[i + 2] = 34

    fcntl.ioctl(fd, PIO_CMAP, palette)
except OSError:
    pass
finally:
    os.close(fd)
PY
}

# Subiquity can stop/start its urwid screen and restore its own palette.
# Re-apply periodically for the duration of the installer.
while :; do
  apply_palette
  sleep "$INTERVAL"
done
