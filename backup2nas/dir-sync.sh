#!/usr/bin/env bash
# dir-sync.sh - Interactive directory sync (rsync) to NAS/media destination
# Usage: ./dir-sync.sh

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/dir-backup.dialogrc" ]; then
    export DIALOGRC="$SCRIPT_DIR/dir-backup.dialogrc"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Audible completion feedback: a real chime if the desktop sound theme is
# available, else a plain terminal bell.
beep() {
    if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 &
    else
        printf '\a' >/dev/tty
    fi
}

# dialog wrapper: runs a dialog widget, prints its answer on stdout,
# returns dialog's own exit status (0=OK, 1=Cancel, 2=Help, 3=Extra/Back, 255=Esc).
# NOTE: never call `exit` in here - this runs inside a subshell whenever
# it's invoked as VAR=$(dg ...), so `exit` would only kill the subshell.
dg() {
    local rc
    rc=0
    dialog "$@" 3>&1 1>&2 2>&3 || rc=$?
    clear >/dev/tty
    return $rc
}

# set -e safe way to call dg: answer in $ANS, exit status in $RC.
# A bare `X=$(dg ...); rc=$?` would kill the whole script on Back (rc 3)
# before rc is read, because set -e fires on the failed substitution.
ask() {
    RC=0
    ANS=$(dg "$@") || RC=$?
}

# Interactive directory browser (dialog --menu based, so the list itself
# has focus from the start - no text-entry field to accidentally submit).
# Prints the chosen absolute path on stdout; returns 1 if cancelled.
browse_dir() {
    local cur="$1"
    local choice rc
    while true; do
        mapfile -t subdirs < <(find "$cur" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
        local menu=("." "[Select this directory]" ".." "[Up one level]")
        local s
        for s in "${subdirs[@]}"; do
            menu+=("$s" "")
        done
        rc=0
        choice=$(dg --title "Browse: $cur" --menu "Select a subdirectory, or choose an action:" 22 78 14 "${menu[@]}") || rc=$?
        if [ $rc -ne 0 ]; then
            return 1
        fi
        case "$choice" in
            ".") printf '%s' "$cur"; return 0 ;;
            "..") cur=$(dirname "$cur") ;;
            *) cur="$cur/$choice" ;;
        esac
    done
}

# Interactive source-directory picker: same browsing as browse_dir, plus a
# "select multiple" action (dialog --checklist over the current level's
# subdirectories). Sets the global array SRC_DIRS and SRC_BROWSE (the level
# the user was browsing, so Back can reopen there); returns 1 if cancelled.
select_sources() {
    local cur="$1"
    local choice rc s
    while true; do
        mapfile -t subdirs < <(find "$cur" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
        local menu=("." "[Select this directory]" "+" "[Select multiple subdirectories here...]" ".." "[Up one level]")
        for s in "${subdirs[@]}"; do
            menu+=("$s" "")
        done
        rc=0
        choice=$(dg --title "Browse: $cur" --menu "Select a source directory, or choose an action:" 22 78 14 "${menu[@]}") || rc=$?
        if [ $rc -ne 0 ]; then
            return 1
        fi
        case "$choice" in
            ".") SRC_DIRS=("$cur"); SRC_BROWSE="$cur"; return 0 ;;
            "+")
                if [ ${#subdirs[@]} -eq 0 ]; then
                    dialog --title "No subdirectories" --msgbox "No subdirectories found under:\n$cur" 8 70
                    clear >/dev/tty
                    continue
                fi
                local checklist=()
                for s in "${subdirs[@]}"; do
                    checklist+=("$s" "" off)
                done
                local selection
                rc=0
                selection=$(dg --title "Select multiple" --checklist "Select one or more subdirectories under:\n$cur" 22 78 14 "${checklist[@]}") || rc=$?
                if [ $rc -ne 0 ] || [ -z "$selection" ]; then
                    continue
                fi
                local sel_arr
                eval "sel_arr=($selection)"
                SRC_DIRS=()
                for s in "${sel_arr[@]}"; do
                    SRC_DIRS+=("$cur/$s")
                done
                SRC_BROWSE="$cur"
                return 0
                ;;
            "..") cur=$(dirname "$cur") ;;
            *) cur="$cur/$choice" ;;
        esac
    done
}

# Build the rsync flag set for the current destination (array RSYNC_FLAGS).
# SMB/NTFS/FAT shares can't hold unix owner/perms (and round mtimes to 2s),
# so -a would error out or re-copy everything on each run.
build_flags() {
    local dst_dir="$1" ts="$2" fstype
    fstype=$(findmnt -no FSTYPE -T "$dst_dir" 2>/dev/null || true)
    case "$fstype" in
        cifs|smb3|ntfs*|fuseblk|vfat|exfat|msdos|fuse.*)
            FS_MODE="$fstype (SMB/NTFS/FAT-safe flags)"
            RSYNC_FLAGS=(-rt --no-perms --no-owner --no-group --modify-window=2) ;;
        *)
            FS_MODE="${fstype:-unknown} (full -a)"
            RSYNC_FLAGS=(-a) ;;
    esac
    [ "$OPT_MIRROR" = on ] && RSYNC_FLAGS+=(--delete)
    # The exclude keeps --delete from wiping earlier .deleted/ folders.
    RSYNC_FLAGS+=(--exclude=/.deleted)
    # --backup alone would also save every OVERWRITTEN file, so the trash is
    # a separate first pass (see TRASH_FLAGS): --existing + --ignore-existing
    # make it transfer nothing, so it only moves --delete victims aside.
    TRASH_FLAGS=("${RSYNC_FLAGS[@]}" --existing --ignore-existing --backup "--backup-dir=@DST@/.deleted/$ts")
}

SRC_BROWSE="$HOME"
OPT_MIRROR=off
OPT_TRASH=on
SYNC_NAME=""

# ---------- Step-based flow, so [Back] can return to the previous screen ----------
# 1 sources -> 2 destination -> 3 subfolder name (single source only)
#   -> 4 options -> 5 confirm (dry run) -> 6 run
STEP=1
while true; do
case $STEP in

1)  # SELECT SOURCE DIRECTORY(IES)
    select_sources "$SRC_BROWSE" || { echo "Aborted."; exit 0; }
    NDIRS=${#SRC_DIRS[@]}
    SYNC_NAME=""
    STEP=2
    ;;

2)  # SELECT DESTINATION
    mapfile -t DESTS < <(
        { find /media/jlc -mindepth 1 -maxdepth 1 -type d -printf '%p (auto)\n' 2>/dev/null
          find /mnt/wdnas_public -mindepth 1 -maxdepth 1 -type d -printf '%p (fstab)\n' 2>/dev/null
        } | sort
    )

    if [ ${#DESTS[@]} -eq 0 ]; then
        ask --title "Destination" --extra-button --extra-label "Back" --msgbox "No mounted destinations found under /media/jlc/ or /mnt/wdnas_public/.\n\nYou'll be shown a directory browser next." 10 78
        case $RC in
            3) STEP=1; continue ;;
            0) : ;;
            *) echo "Aborted."; exit 0 ;;
        esac
        DEST_DIR=$(browse_dir "${DEST_DIR:-/mnt}") || { STEP=2; continue; }
    else
        MENU_ITEMS=()
        declare -A SEEN_MOUNTS=()
        idx=1
        for d in "${DESTS[@]}"; do
            path="${d% (*}"
            read -r mnt avail < <(df -h --output=target,avail "$path" 2>/dev/null | tail -n 1)
            if [ -n "$mnt" ] && [ -z "${SEEN_MOUNTS[$mnt]:-}" ]; then
                SEEN_MOUNTS[$mnt]=1
                MENU_ITEMS+=("$idx" "$d  (free: $avail)")
            else
                MENU_ITEMS+=("$idx" "$d")
            fi
            idx=$((idx+1))
        done
        manual_idx=$idx
        MENU_ITEMS+=("$manual_idx" "Browse for a path...")

        ask --title "Select destination" --extra-button --extra-label "Back" --menu "Choose a NAS/media destination to sync to:" 20 78 10 "${MENU_ITEMS[@]}"
        case $RC in
            3) STEP=1; continue ;;
            0) : ;;
            *) echo "Aborted."; exit 0 ;;
        esac

        if [ "$ANS" -eq "$manual_idx" ]; then
            DEST_DIR=$(browse_dir "${DEST_DIR:-/mnt}") || { STEP=2; continue; }
        else
            DEST_DIR="${DESTS[$((ANS-1))]% (*}"
        fi
    fi

    if [ ! -d "$DEST_DIR" ]; then
        dialog --title "Error" --msgbox "Destination directory does not exist: $DEST_DIR" 8 70
        clear >/dev/tty
        exit 1
    fi
    if [ "$NDIRS" -eq 1 ]; then STEP=3; else STEP=4; fi
    ;;

3)  # DESTINATION SUBFOLDER NAME (single source; batch syncs use each
    # source's own basename). Fixed name, no timestamp: re-runs must hit
    # the same folder for the sync to be incremental.
    DEFAULT_NAME="${SYNC_NAME:-$(basename "${SRC_DIRS[0]}")}"
    ask --title "Destination folder" --extra-button --extra-label "Back" --inputbox "Folder name to sync into, under:\n$DEST_DIR" 11 78 "$DEFAULT_NAME"
    case $RC in
        3) STEP=2; continue ;;
        0) : ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    SYNC_NAME="${ANS//\//}"
    SYNC_NAME="${SYNC_NAME:-$DEFAULT_NAME}"
    STEP=4
    ;;

4)  # OPTIONS
    ask --title "Sync options" --extra-button --extra-label "Back" --checklist "Toggle with SPACE:" 12 78 2 \
        mirror "Mirror: delete files at destination that are not in source" "$OPT_MIRROR" \
        trash  "Mirror only: move deleted files to <dest>/.deleted/<timestamp>/" "$OPT_TRASH"
    case $RC in
        3) if [ "$NDIRS" -eq 1 ]; then STEP=3; else STEP=2; fi; continue ;;
        0) : ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    OPT_MIRROR=off; OPT_TRASH=off
    [[ $ANS == *mirror* ]] && OPT_MIRROR=on
    [[ $ANS == *trash* ]] && OPT_TRASH=on
    STEP=5
    ;;

5)  # DRY RUN + CONFIRM
    RUN_TS=$(date +%Y%m%d_%H%M%S)
    build_flags "$DEST_DIR" "$RUN_TS"

    OUT_DIRS=()
    for d in "${SRC_DIRS[@]}"; do
        if [ "$NDIRS" -eq 1 ]; then OUT_DIRS+=("$DEST_DIR/$SYNC_NAME"); else OUT_DIRS+=("$DEST_DIR/$(basename "$d")"); fi
    done

    dialog --title "Directory Sync" --infobox "Comparing source and destination (dry run)..." 6 60
    : >"$WORK/dry.log"
    i=0
    for d in "${SRC_DIRS[@]}"; do
        dst="${OUT_DIRS[$i]}"
        flags=("${RSYNC_FLAGS[@]/@DST@/$dst}")
        echo "### $d" >>"$WORK/dry.log"
        rsync "${flags[@]}" --dry-run --itemize-changes --stats "$d/" "$dst/" >>"$WORK/dry.log" 2>"$WORK/dry.err" || true
        i=$((i+1))
    done
    clear >/dev/tty

    N_COPY=$(grep -c '^>f' "$WORK/dry.log" || true)
    N_DEL=$(grep -c '^\*deleting' "$WORK/dry.log" || true)
    BYTES=$(grep '^Total transferred file size' "$WORK/dry.log" | awk '{gsub(",","",$5); s+=$5} END{print s+0}')
    BYTES_H=$(numfmt --to=iec "$BYTES")

    CONFIRM_MSG="Sources ($NDIRS):\n"
    i=0
    for d in "${SRC_DIRS[@]}"; do
        CONFIRM_MSG+="  $d\n    -> ${OUT_DIRS[$i]}/\n"
        i=$((i+1))
    done
    CONFIRM_MSG+="\nDestination fs: $FS_MODE\n"
    CONFIRM_MSG+="Mode: $([ "$OPT_MIRROR" = on ] && echo 'MIRROR (deletes extras at destination)' || echo 'update only (never deletes)')\n"
    [ "$OPT_MIRROR" = on ] && CONFIRM_MSG+="Deleted files moved to .deleted/ (trash): $OPT_TRASH\n"
    CONFIRM_MSG+="\nDry run: $N_COPY file(s) to copy/update ($BYTES_H), $N_DEL to delete.\n"
    if [ -s "$WORK/dry.err" ]; then
        CONFIRM_MSG+="(rsync reported warnings in the dry run: see Details)\n"
    fi
    CONFIRM_MSG+="\nProceed?"
    ask --title "Confirm sync" --extra-button --extra-label "Back" --help-button --help-label "Details" --yesno "$CONFIRM_MSG" $((19+2*NDIRS)) 78
    case $RC in
        0) STEP=6 ;;
        3) STEP=4; continue ;;
        2) cat "$WORK/dry.err" >>"$WORK/dry.log" 2>/dev/null || true
           dialog --title "Dry run details (itemized)" --textbox "$WORK/dry.log" 22 78
           clear >/dev/tty
           continue ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    ;;

6)  # RUN SYNC
    START_TIME=$(date +%s)
    ALL_OK=1
    TOTAL_FILES=0
    TOTAL_BYTES=0
    TOTAL_DEL=0
    ERR_TEXT=""
    i=0
    for d in "${SRC_DIRS[@]}"; do
        dst="${OUT_DIRS[$i]}"
        flags=("${RSYNC_FLAGS[@]/@DST@/$dst}")
        LABEL="[$((i+1))/$NDIRS] $(basename "$d")"
        LOG="$WORK/run_$i.log"; ERR="$WORK/err_$i.log"; RCF="$WORK/rc_$i"
        : >"$ERR"

        # pass 1 (trash): move files the mirror would delete into .deleted/<ts>/
        if [ "$OPT_MIRROR" = on ] && [ "$OPT_TRASH" = on ]; then
            tflags=("${TRASH_FLAGS[@]/@DST@/$dst}")
            dialog --title "Directory Sync" --infobox "Moving deleted files to .deleted/ for $LABEL..." 6 70
            T_RC=0
            rsync "${tflags[@]}" --stats "$d/" "$dst/" >"$WORK/trash_$i.log" 2>>"$ERR" || T_RC=$?
            if [ "$T_RC" -ne 0 ]; then
                ALL_OK=0
                ERR_TEXT+="  $(basename "$d"): trash pass rsync exit $T_RC\n"
            fi
            TOTAL_DEL=$((TOTAL_DEL + $(grep '^Number of deleted files' "$WORK/trash_$i.log" | awk '{gsub(",","",$5); print $5+0}')))
        fi

        # rsync's own exit status is parked in a file: it's buried in the
        # middle of a pipe feeding the gauge, so $? / PIPESTATUS won't survive.
        { SRC_RC=0
          rsync "${flags[@]}" --info=progress2 --no-inc-recursive --stats "$d/" "$dst/" 2>>"$ERR" || SRC_RC=$?
          echo "$SRC_RC" >"$RCF"
        } | tee "$LOG" | stdbuf -oL tr '\r' '\n' \
          | awk '/^ *[0-9,.A-Za-z]+ +[0-9]+% / { for (k=1;k<=NF;k++) if ($k ~ /%$/) { sub("%","",$k); print $k; fflush(); break } }' \
          | dialog --title "Syncing" --gauge "Syncing $LABEL..." 8 70 0 || true
        clear >/dev/tty

        SRC_RC=$(cat "$RCF" 2>/dev/null || echo 99)
        if [ "$SRC_RC" -ne 0 ]; then
            ALL_OK=0
            ERR_TEXT+="  $(basename "$d"): rsync exit $SRC_RC\n$(head -n 5 "$ERR" | sed 's/^/    /')\n"
        fi
        TOTAL_FILES=$((TOTAL_FILES + $(grep '^Number of regular files transferred' "$LOG" | awk '{gsub(",","",$NF); print $NF+0}')))
        TOTAL_BYTES=$((TOTAL_BYTES + $(grep '^Total transferred file size' "$LOG" | awk '{gsub(",","",$5); print $5+0}')))
        TOTAL_DEL=$((TOTAL_DEL + $(grep '^Number of deleted files' "$LOG" | awk '{gsub(",","",$5); print $5+0}')))

        # drop the empty .deleted/<ts> (and .deleted) when nothing was moved aside
        rmdir "$dst/.deleted/$RUN_TS" "$dst/.deleted" 2>/dev/null || true
        i=$((i+1))
    done

    ELAPSED=$(( $(date +%s) - START_TIME ))
    beep
    SUMMARY="$TOTAL_FILES file(s) copied/updated ($(numfmt --to=iec "$TOTAL_BYTES")), $TOTAL_DEL deleted, in $((ELAPSED/60))m $((ELAPSED%60))s."
    if [ "$ALL_OK" -eq 1 ]; then
        dialog --title "Sync complete" --msgbox "$SUMMARY\n\nRe-run any time: only changes are transferred." 10 78
    else
        dialog --title "Sync finished with errors" --msgbox "$SUMMARY\n\n$ERR_TEXT" $((12+NDIRS*7)) 78
    fi
    clear >/dev/tty
    exit 0
    ;;

esac
done
