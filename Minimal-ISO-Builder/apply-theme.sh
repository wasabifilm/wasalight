#!/bin/sh
set -eu

# Subiquity della release Ubuntu configurata:
# progress_complete -> neutral -> Linux basic color index 4 ("dark blue")
# We keep every other console color untouched and replace only index 4.
#
# RGB WASALIGHT green: #2FAC2F = 47, 172, 47

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

    # Linux VGA palette index 4 is the basic "dark blue". Subiquity maps its
    # neutral progress color to this slot.
    i = 4 * 3
    palette[i + 0] = 47
    palette[i + 1] = 172
    palette[i + 2] = 47

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
