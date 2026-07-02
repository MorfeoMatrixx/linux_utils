#!/usr/bin/env bash
# Find duplicate image/video files in a directory and remove all but the oldest via a GUI.
# Requires: python3, python3-tk, python3-pil.imagetk
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/grok-dedup-last-dir"

if [ -f "$STATE_FILE" ]; then
    DEFAULT_DIR="$(cat "$STATE_FILE")"
else
    DEFAULT_DIR="$HOME/Pictures"
fi

# Seed from CLI arg on first iteration, then fall through to interactive prompt.
INITIAL="${1:-}"

while true; do
    if [ -n "$INITIAL" ]; then
        DIR="$INITIAL"
        INITIAL=""
    else
        read -re -i "$DEFAULT_DIR" -p "Directory to scan: " DIR
    fi
    DIR="${DIR/#\~/$HOME}"      # expand leading tilde
    if [ -d "$DIR" ]; then
        break
    fi
    echo "Error: '$DIR' does not exist or is not a directory — please try again."
    DEFAULT_DIR="$DIR"          # keep the bad input editable so the user can fix a typo
done

mkdir -p "$(dirname "$STATE_FILE")"

TERM_WID="$(xdotool getactivewindow 2>/dev/null || true)"

while true; do
    echo "$DIR" > "$STATE_FILE"

    echo "Scanning: $DIR"
    find "$DIR" -type f \( \
        -iname '*.jpg'  -o -iname '*.jpeg' -o -iname '*.png'  -o \
        -iname '*.gif'  -o -iname '*.webp' -o -iname '*.bmp'  -o \
        -iname '*.heic' -o -iname '*.mp4'  -o -iname '*.mov'  -o \
        -iname '*.webm' -o -iname '*.mkv'  -o -iname '*.avi'  \
    \) -print0 | python3 "${SCRIPT_DIR}/grok-dedup-ui.py"

    [ -n "$TERM_WID" ] && xdotool windowfocus "$TERM_WID" 2>/dev/null || true

    printf '\nScan another directory? [y/N] '
    read -r again </dev/tty
    [[ "${again,,}" == "y" ]] || break

    # prompt for next dir, pre-filled with current one as starting point
    DEFAULT_DIR="$DIR"
    while true; do
        read -re -i "$DEFAULT_DIR" -p "Directory to scan: " DIR
        DIR="${DIR/#\~/$HOME}"
        [ -d "$DIR" ] && break
        echo "Error: '$DIR' does not exist or is not a directory — please try again."
        DEFAULT_DIR="$DIR"
    done
done
