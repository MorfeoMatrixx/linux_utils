#!/usr/bin/env bash
# Opens a terminal emulator to run grok-sync.sh, picking the first available one.
# When launched from the app menu (KDE sets DESKTOP_STARTUP_ID / XDG_ACTIVATION_TOKEN),
# we must keep this process alive until the terminal window exists; otherwise KDE ends
# the startup sequence before the window is mapped and the window opens behind fullscreen apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_CMD="${SCRIPT_DIR}/grok-sync.sh ${*}; echo; read -p 'Done — press Enter to close'"

_from_app_menu() {
    [[ -n "${DESKTOP_STARTUP_ID:-}" || -n "${XDG_ACTIVATION_TOKEN:-}" ]]
}

if command -v tilix &>/dev/null; then
    tilix -e bash -c "$RUN_CMD" &
elif command -v gnome-terminal &>/dev/null; then
    gnome-terminal -- bash -c "$RUN_CMD" &
elif command -v xterm &>/dev/null; then
    xterm -e bash -c "$RUN_CMD" &
else
    exec bash -c "$RUN_CMD"
fi

if _from_app_menu; then
    wait $!
fi
