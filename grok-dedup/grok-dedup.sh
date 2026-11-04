#!/usr/bin/env bash
# Find duplicate image/video files in a directory and remove all but the oldest.
# Usage:
#   grok-dedup.sh                        — interactive GUI mode
#   grok-dedup.sh <dir>                  — GUI mode, pre-fill directory
#   grok-dedup.sh <dir> --force-delete   — batch mode: silent delete, no GUI
# Requires: python3, python3-tk, python3-pil.imagetk, ffmpeg, xdotool
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/grok-dedup-last-dir"
FORCE_DELETE="${2:-}"

_find_media() {
    find "$1" -type f \( \
        -iname '*.jpg'  -o -iname '*.jpeg' -o -iname '*.png'  -o \
        -iname '*.gif'  -o -iname '*.webp' -o -iname '*.bmp'  -o \
        -iname '*.heic' -o -iname '*.mp4'  -o -iname '*.mov'  -o \
        -iname '*.webm' -o -iname '*.mkv'  -o -iname '*.avi'  \
    \) -print0
}

# ── Batch / non-interactive mode ─────────────────────────────────────────────
if [ "${FORCE_DELETE}" = "--force-delete" ]; then
    DIR="${1:-}"
    DIR="${DIR/#\~/$HOME}"
    if [ ! -d "$DIR" ]; then
        echo "Error: '$DIR' is not a directory." >&2
        exit 1
    fi
    echo "Scanning: $DIR"
    _find_media "$DIR" | python3 "${SCRIPT_DIR}/grok-dedup-ui.py" --force-delete
    exit 0
fi

# ── Interactive / GUI mode ────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
    DEFAULT_DIR="$(cat "$STATE_FILE")"
else
    DEFAULT_DIR="$HOME/Pictures"
fi

INITIAL="${1:-}"

while true; do
    if [ -n "$INITIAL" ]; then
        DIR="$INITIAL"
        INITIAL=""
    else
        read -re -i "$DEFAULT_DIR" -p "Directory to scan: " DIR
    fi
    DIR="${DIR/#\~/$HOME}"
    if [ -d "$DIR" ]; then
        break
    fi
    echo "Error: '$DIR' does not exist or is not a directory — please try again."
    DEFAULT_DIR="$DIR"
done

mkdir -p "$(dirname "$STATE_FILE")"

TERM_WID="$(xdotool getactivewindow 2>/dev/null || true)"

while true; do
    echo "$DIR" > "$STATE_FILE"

    echo "Scanning: $DIR"
    _find_media "$DIR" | python3 "${SCRIPT_DIR}/grok-dedup-ui.py"

    [ -n "$TERM_WID" ] && xdotool windowfocus "$TERM_WID" 2>/dev/null || true

    printf '\nScan another directory? [y/N] '
    read -r again </dev/tty
    [[ "${again,,}" == "y" ]] || break

    DEFAULT_DIR="$DIR"
    while true; do
        read -re -i "$DEFAULT_DIR" -p "Directory to scan: " DIR
        DIR="${DIR/#\~/$HOME}"
        [ -d "$DIR" ] && break
        echo "Error: '$DIR' does not exist or is not a directory — please try again."
        DEFAULT_DIR="$DIR"
    done
done
