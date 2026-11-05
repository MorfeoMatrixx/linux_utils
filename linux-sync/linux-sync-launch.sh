#!/usr/bin/env bash
# Opens a terminal emulator to run linux-sync.sh, picking the first available one.
# When launched from the app menu (KDE sets DESKTOP_STARTUP_ID / XDG_ACTIVATION_TOKEN),
# we must keep this process alive until the terminal window exists; otherwise KDE ends
# the startup sequence before the window is mapped and the window opens behind fullscreen apps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_CMD="${SCRIPT_DIR}/linux-sync; echo; read -p 'Done — press Enter to close'"

_from_app_menu() {
    [[ -n "${DESKTOP_STARTUP_ID:-}" || -n "${XDG_ACTIVATION_TOKEN:-}" ]]
}

# tilix --new-process: without it, a running tilix (e.g. the HA monitor window) receives the request over
# D-Bus and creates the window itself, which KWin then won't raise over a fullscreen app.
if command -v tilix &>/dev/null; then
    tilix --new-process -e bash -c "$RUN_CMD" &
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
