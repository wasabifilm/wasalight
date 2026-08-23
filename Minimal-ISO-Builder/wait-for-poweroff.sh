#!/bin/sh
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
# Hand the console back to the operator before Autoinstall powers the system off.

set -eu

TTY=/dev/tty2
[ -c "$TTY" ] || TTY=/dev/console
PID_FILE=/run/wasalight-ui.pid

if [ -r "$PID_FILE" ]; then
  ui_pid=$(sed -n '1p' "$PID_FILE")
  case "$ui_pid" in
    ''|*[!0-9]*) ui_pid= ;;
  esac
  if [ -n "$ui_pid" ] && kill -0 "$ui_pid" 2>/dev/null; then
    kill "$ui_pid" 2>/dev/null || true
    attempts=0
    while kill -0 "$ui_pid" 2>/dev/null && [ "$attempts" -lt 5 ]; do
      attempts=$((attempts + 1))
      sleep 1
    done
  fi
fi

chvt 2 2>/dev/null || true
exec <"$TTY" >"$TTY" 2>&1
printf '\033[2J\033[H\033[?25h'
printf '\033[1;32m%s\033[0m\n' '┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓'
printf '\033[1;32m┃%60s┃\033[0m\n' ' '
printf '\033[1;32m┃%s┃\033[0m\n' '              WASALIGHT INSTALLATION COMPLETE               '
printf '\033[1;32m┃%60s┃\033[0m\n' ' '
printf '\033[1;32m┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\033[0m\n'
printf '\n'
printf '  Ubuntu and the Wasalight bootstrap are ready.\n'
printf '  Press ENTER to power off the system safely.\n\n'
printf '  After the system is off:\n'
printf '    1. Remove the Wasalight installation USB drive.\n'
printf '    2. Power the system on from the internal disk.\n\n'
printf '  Press ENTER to power off... '
IFS= read -r _answer
sync
