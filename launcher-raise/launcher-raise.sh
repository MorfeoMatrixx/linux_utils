#!/usr/bin/env bash
# launcher-raise   (no arguments)
# Called detached by the *-launch scripts just before they exec the terminal.
# KWin sometimes refuses to activate the new terminal window (it stays behind the maximized Claude
# app) even though the startup notification is intact, and the rule that triggers it can't be
# reproduced from a script. So this watches for the new tilix window and, if it did not become
# active on its own, activates it explicitly (xdotool sends the request as coming from a
# pager/tool, which KWin accepts). X11 only.
set -u

active_dec() { printf '%d' "$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')" 2>/dev/null || echo 0; }
tilix_wins() { xdotool search --onlyvisible --class '^tilix$' 2>/dev/null | sort; }

before_wins=$(tilix_wins)

# wait (max 4 s) for the new visible tilix window
newid=""
for _ in $(seq 1 20); do
    sleep 0.2
    newid=$(comm -13 <(echo "$before_wins") <(tilix_wins) | tail -1)
    [ -n "$newid" ] && break
done
[ -n "$newid" ] || exit 0

sleep 0.5
[ "$(active_dec)" -eq "$newid" ] || xdotool windowactivate "$newid" 2>/dev/null
