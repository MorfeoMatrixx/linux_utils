#!/usr/bin/env bash
# Opens a terminal emulator to run dir-backup.sh, picking the first available one.
# `exec` the terminal so this process *is* the terminal and lives until its window closes; with
# StartupNotify=true in the .desktop that keeps KDE's startup sequence valid.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_CMD="${SCRIPT_DIR}/dir-backup; echo; read -p 'Done — press Enter to close'"

# Raises the terminal if KWin leaves it behind a maximized app; logs each launch (see launcher-raise/)
setsid -f "$SCRIPT_DIR/launcher-raise" dir-backup $$ </dev/null >/dev/null 2>&1 || true

# tilix --new-process: without it, a running tilix (e.g. the HA monitor window) receives the request over
# D-Bus and creates the window itself, which KWin then won't raise over a fullscreen app.
if command -v tilix &>/dev/null; then
    exec tilix --new-process -e bash -c "$RUN_CMD"
elif command -v gnome-terminal &>/dev/null; then
    exec gnome-terminal -- bash -c "$RUN_CMD"
elif command -v xterm &>/dev/null; then
    exec xterm -e bash -c "$RUN_CMD"
else
    exec bash -c "$RUN_CMD"
fi
