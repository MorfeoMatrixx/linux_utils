#!/usr/bin/env bash
# launcher-raise <launcher-name> <launcher-pid>
# Called detached by the *-launch scripts just before they exec the terminal.
# KWin sometimes refuses to activate the new terminal window (it stays behind the
# maximized/fullscreen Claude app) even though the startup notification is intact, and the rule
# that triggers it can't be reproduced from a script. So this watches for the new tilix window and,
# if it did not become active on its own, activates it explicitly (xdotool sends the request as
# coming from a pager/tool, which KWin accepts).
# Every launch is logged to ~/.cache/launcher-focus.log (one line) so the cause can still be found:
#   time, launcher | startup-notification vars | other tilix processes | startup-id time vs the active
#   window's last user-input time | window active at launch | what happened to the new window
set -u
name=${1:-?}; lpid=${2:-0}
log="$HOME/.cache/launcher-focus.log"; mkdir -p "$(dirname "$log")"

active_dec() { printf '%d' "$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')" 2>/dev/null || echo 0; }
tilix_wins() { xdotool search --onlyvisible --class '^tilix$' 2>/dev/null | sort; }
describe() {   # decimal id -> "id|class|title|fs=yes/no"
    local id=$1 cls title fs=no
    [ "$id" -eq 0 ] 2>/dev/null && { echo none; return; }
    cls=$(xprop -id "$id" WM_CLASS 2>/dev/null | sed 's/.*= //; s/"//g; s/, /\//')
    title=$(xdotool getwindowname "$id" 2>/dev/null | cut -c1-30)
    [[ $(xprop -id "$id" _NET_WM_STATE 2>/dev/null) == *FULLSCREEN* ]] && fs=yes
    echo "$id|$cls|$title|fs=$fs"
}

before_id=$(active_dec); before=$(describe "$before_id")
before_wins=$(tilix_wins)
others=$(pgrep -x tilix | grep -vx "$lpid" | wc -l)
sid=no;   [ -n "${DESKTOP_STARTUP_ID:-}" ] && sid=yes
token=no; [ -n "${XDG_ACTIVATION_TOKEN:-}" ] && token=yes
sidtime=""; [[ ${DESKTOP_STARTUP_ID:-} =~ _TIME([0-9]+) ]] && sidtime=${BASH_REMATCH[1]}
ut=$(xprop -id "$before_id" _NET_WM_USER_TIME 2>/dev/null | awk '{print $NF}')
ut=${ut//[^0-9]/}

# wait (max 4 s) for the new visible tilix window
newid=""
for _ in $(seq 1 20); do
    sleep 0.2
    newid=$(comm -13 <(echo "$before_wins") <(tilix_wins) | tail -1)
    [ -n "$newid" ] && break
done

if [ -z "$newid" ]; then
    result="NO-NEW-WINDOW"
else
    sleep 0.5
    if [ "$(active_dec)" -eq "$newid" ]; then
        result="ACTIVATED-BY-KWIN"
    else
        xdotool windowactivate "$newid" 2>/dev/null
        sleep 0.5
        if [ "$(active_dec)" -eq "$newid" ]; then result="BEHIND->RAISED"; else result="BEHIND->RAISE-FAILED"; fi
    fi
fi

printf '%s %-11s | sid=%s token=%s | other_tilix=%s | sid_time=%s active_user_time=%s | before=[%s] | %s\n' \
    "$(date '+%F %T')" "$name" "$sid" "$token" "$others" "${sidtime:-?}" "${ut:-?}" "$before" "$result" >>"$log"
tail -n 300 "$log" >"$log.tmp" && mv "$log.tmp" "$log"
