#!/usr/bin/env bash
# Quick status report for linux-sync: is it running now, when did it last
# succeed, and what did it last say.
set -uo pipefail

LOG_FILE="$HOME/.local/share/linux-sync.log"
LOCK_FILE="$HOME/.local/share/linux-sync.lock"
STATE_FILE="$HOME/.local/share/linux-sync.last-run"
TAIL_LINES=15

echo "=== linux-sync status ==="

# Running now? Try (and release) a non-blocking lock on the same lock file
# the script itself uses — if we can't get it, someone else holds it.
if [ -e "$LOCK_FILE" ]; then
    exec 200>>"$LOCK_FILE"
    if flock -n 200; then
        echo "Running:     no"
        flock -u 200
    else
        holder_pid="$(tr -d '[:space:]' < "$LOCK_FILE" 2>/dev/null)"
        if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
            elapsed="$(ps -o etime= -p "$holder_pid" 2>/dev/null | tr -d ' ')"
            echo "Running:     yes (PID $holder_pid, running ${elapsed:-unknown})"
        else
            echo "Running:     yes (lock held, holder PID unknown)"
        fi
    fi
else
    echo "Running:     no"
fi

# Last successful run
today="$(date +%F)"
if [[ -f "$STATE_FILE" ]]; then
    last_run="$(cat "$STATE_FILE" 2>/dev/null)"
    if [[ "$last_run" == "$today" ]]; then
        echo "Last run:    $last_run (today)"
    else
        echo "Last run:    $last_run (not today — cron rechecks every 15 min after 16:00)"
    fi
else
    echo "Last run:    never recorded"
fi

echo "Log file:    $LOG_FILE"
echo
echo "--- last $TAIL_LINES log line(s) ---"
if [[ -f "$LOG_FILE" ]]; then
    tail -n "$TAIL_LINES" "$LOG_FILE"
else
    echo "(no log file yet)"
fi
