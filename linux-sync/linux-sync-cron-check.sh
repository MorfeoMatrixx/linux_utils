#!/usr/bin/env bash
# Cron catch-up gate for linux-sync.sh.
#
# Meant to run frequently (e.g. every 15 min) via cron. It only actually
# triggers linux-sync.sh once per day, the first time it observes local
# time >= THRESHOLD_HHMM. If the laptop is asleep at that time, cron simply
# doesn't fire — the next tick after it wakes will see "not run yet today,
# already past threshold" and catch up immediately, without needing anacron
# or a systemd timer.
set -euo pipefail

THRESHOLD_HHMM=1600
STATE_FILE="$HOME/.local/share/linux-sync.last-run"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$STATE_FILE")"

today="$(date +%F)"
last_run="$(cat "$STATE_FILE" 2>/dev/null || true)"

[[ "$last_run" == "$today" ]] && exit 0
(( 10#$(date +%H%M) >= THRESHOLD_HHMM )) || exit 0

if "${SCRIPT_DIR}/linux-sync.sh"; then
    printf '%s\n' "$today" > "$STATE_FILE"
fi
