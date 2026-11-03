#!/usr/bin/env bash
# Opens a terminal emulator to run grok-sync.sh, picking the first available one.
# `exec` the terminal: with StartupNotify=true in the .desktop this keeps the window in front of
# fullscreen apps. The backgrounded `terminal &` + `wait` form tried on 2026-10-26 (5714054) left
# grok-sync behind them (the other launchers are fine with it, so it's specific to this one).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_CMD="${SCRIPT_DIR}/grok-sync.sh ${*}; echo; read -p 'Done — press Enter to close'"

if command -v tilix &>/dev/null; then
    exec tilix -e bash -c "$RUN_CMD"
elif command -v gnome-terminal &>/dev/null; then
    exec gnome-terminal -- bash -c "$RUN_CMD"
elif command -v xterm &>/dev/null; then
    exec xterm -e bash -c "$RUN_CMD"
else
    exec bash -c "$RUN_CMD"
fi
