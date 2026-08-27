#!/usr/bin/env bash
# dir-backup.sh - Interactive directory backup to compressed archive on NAS
# Usage: ./dir-backup.sh

set -euo pipefail

HAVE_PV=0
command -v pv >/dev/null 2>&1 && HAVE_PV=1

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$SCRIPT_DIR/dir-backup.dialogrc" ]; then
    export DIALOGRC="$SCRIPT_DIR/dir-backup.dialogrc"
fi

# dialog wrapper: runs a dialog widget, prints its answer on stdout,
# returns dialog's own exit status (0=OK, 1=Cancel, 3=Extra/Back, 255=Esc).
# NOTE: never call `exit` in here - this runs inside a subshell whenever
# it's invoked as VAR=$(dg ...), so `exit` would only kill the subshell.
# Audible completion feedback: a real chime if the desktop sound theme is
# available, else a plain terminal bell.
beep() {
    if command -v paplay >/dev/null 2>&1 && [ -f /usr/share/sounds/freedesktop/stereo/complete.oga ]; then
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 &
    else
        printf '\a' >/dev/tty
    fi
}

dg() {
    local rc
    dialog "$@" 3>&1 1>&2 2>&3
    rc=$?
    clear >/dev/tty
    return $rc
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
        choice=$(dg --title "Browse: $cur" --menu "Select a subdirectory, or choose an action:" 22 78 14 "${menu[@]}")
        rc=$?
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
# subdirectories). Sets the global array SRC_DIRS; returns 1 if cancelled.
# Called directly (not via $(...)) since it needs to set an array, not print
# a single string.
select_sources() {
    local cur="$1"
    local choice rc s
    while true; do
        mapfile -t subdirs < <(find "$cur" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
        local menu=("." "[Select this directory]" "+" "[Select multiple subdirectories here...]" ".." "[Up one level]")
        for s in "${subdirs[@]}"; do
            menu+=("$s" "")
        done
        choice=$(dg --title "Browse: $cur" --menu "Select a source directory, or choose an action:" 22 78 14 "${menu[@]}")
        rc=$?
        if [ $rc -ne 0 ]; then
            return 1
        fi
        case "$choice" in
            ".") SRC_DIRS=("$cur"); return 0 ;;
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
                selection=$(dg --title "Select multiple" --checklist "Select one or more subdirectories under:\n$cur" 22 78 14 "${checklist[@]}")
                rc=$?
                if [ $rc -ne 0 ]; then
                    continue
                fi
                if [ -z "$selection" ]; then
                    continue
                fi
                local sel_arr
                eval "sel_arr=($selection)"
                SRC_DIRS=()
                for s in "${sel_arr[@]}"; do
                    SRC_DIRS+=("$cur/$s")
                done
                return 0
                ;;
            "..") cur=$(dirname "$cur") ;;
            *) cur="$cur/$choice" ;;
        esac
    done
}

# ---------- Step-based flow, so [Back] can return to the previous screen ----------
STEP=1
while true; do
case $STEP in

1)  # SELECT SOURCE DIRECTORY(IES)
    select_sources "${SRC_DIRS[0]:-$HOME}" || { echo "Aborted."; exit 0; }

    NDIRS=${#SRC_DIRS[@]}
    dialog --title "Directory Backup" --infobox "Calculating size of $NDIRS source director$([ "$NDIRS" -eq 1 ] && echo y || echo ies)..." 8 70
    SRC_SIZES=()
    SRC_SIZES_H=()
    SRC_TOTAL=0
    for d in "${SRC_DIRS[@]}"; do
        sz=$(du -sb "$d" 2>/dev/null | cut -f1)
        SRC_SIZES+=("$sz")
        SRC_SIZES_H+=("$(numfmt --to=iec "$sz")")
        SRC_TOTAL=$((SRC_TOTAL + sz))
    done
    SRC_TOTAL_H=$(numfmt --to=iec "$SRC_TOTAL")
    STEP=2
    ;;

2)  # SELECT DESTINATION
    mapfile -t DESTS < <(
        { find /media/jlc -mindepth 1 -maxdepth 1 -type d -printf '%p (auto)\n' 2>/dev/null
          find /mnt/wdnas_public -mindepth 1 -maxdepth 1 -type d -printf '%p (fstab)\n' 2>/dev/null
        } | sort
    )

    if [ ${#DESTS[@]} -eq 0 ]; then
        dg --title "Destination" --extra-button --extra-label "Back" --msgbox "No mounted destinations found under /media/jlc/ or /mnt/wdnas_public/.\n\nYou'll be shown a directory browser next." 10 78
        rc=$?
        case $rc in
            3) STEP=1; continue ;;
            0) : ;;
            *) echo "Aborted."; exit 0 ;;
        esac
        DEST_DIR=$(browse_dir "${DEST_DIR:-/mnt}") || { STEP=2; continue; }
        STEP=3
    else
        MENU_ITEMS=()
        declare -A SEEN_MOUNTS=()
        idx=1
        for d in "${DESTS[@]}"; do
            path="${d% (*)}"
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

        CHOICE=$(dg --title "Select destination" --extra-button --extra-label "Back" --menu "Choose a NAS/media destination for the backup:" 20 78 10 "${MENU_ITEMS[@]}")
        rc=$?
        case $rc in
            3) STEP=1; continue ;;
            0) : ;;
            *) echo "Aborted."; exit 0 ;;
        esac

        if [ "$CHOICE" -eq "$manual_idx" ]; then
            DEST_DIR=$(browse_dir "${DEST_DIR:-/mnt}") || { STEP=2; continue; }
        else
            DEST_DIR="${DESTS[$((CHOICE-1))]% (*)}"
        fi
        STEP=3
    fi

    if [ ! -d "$DEST_DIR" ]; then
        dialog --title "Error" --msgbox "Destination directory does not exist: $DEST_DIR" 8 70
        clear >/dev/tty
        exit 1
    fi
    ;;

3)  # FILENAME (only when a single source directory was picked; batch
    # backups get auto-named per directory, sharing one run timestamp)
    if [ "$NDIRS" -eq 1 ]; then
        DEFAULT_NAME="${OUT_NAME:-backup_$(basename "${SRC_DIRS[0]}")_$(date +%Y%m%d_%H%M).tar.zst}"
        OUT_NAME=$(dg --title "Output filename" --extra-button --extra-label "Back" --inputbox "Output filename:" 10 78 "$DEFAULT_NAME")
        rc=$?
        case $rc in
            3) STEP=2; continue ;;
            0) : ;;
            *) echo "Aborted."; exit 0 ;;
        esac
        OUT_NAME="${OUT_NAME:-$DEFAULT_NAME}"
        OUT_PATHS=("$DEST_DIR/$OUT_NAME")
    else
        TS=$(date +%Y%m%d_%H%M)
        OUT_PATHS=()
        for d in "${SRC_DIRS[@]}"; do
            OUT_PATHS+=("$DEST_DIR/backup_$(basename "$d")_$TS.tar.zst")
        done
    fi
    STEP=4
    ;;

4)  # CONFIRM
    CONFIRM_MSG="Sources ($NDIRS):\n"
    i=0
    for d in "${SRC_DIRS[@]}"; do
        CONFIRM_MSG+="  - $d  (${SRC_SIZES_H[$i]})\n"
        i=$((i+1))
    done
    [ "$NDIRS" -gt 1 ] && CONFIRM_MSG+="  Total: $SRC_TOTAL_H\n"
    CONFIRM_MSG+="\nDestination:\n  $DEST_DIR\n"
    if [ "$NDIRS" -eq 1 ]; then
        CONFIRM_MSG+="\nOutput file:\n  ${OUT_PATHS[0]}\n"
    else
        CONFIRM_MSG+="\n${#OUT_PATHS[@]} archives will be created (auto-named).\n"
    fi
    CONFIRM_MSG+="\nProceed?"
    dialog --title "Confirm backup" --extra-button --extra-label "Back" --yesno "$CONFIRM_MSG" $((13+NDIRS)) 78
    rc=$?
    clear >/dev/tty
    case $rc in
        0) STEP=5 ;;
        3) STEP=3; continue ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    ;;

5)  # RUN BACKUP
    START_TIME=$(date +%s)
    OUT_INFO=""
    i=0
    for d in "${SRC_DIRS[@]}"; do
        SRC_PARENT=$(dirname "$d")
        SRC_BASE=$(basename "$d")
        OUT_PATH="${OUT_PATHS[$i]}"
        SRC_SIZE="${SRC_SIZES[$i]}"
        LABEL="[$((i+1))/$NDIRS] $SRC_BASE"

        if [ "$HAVE_PV" -eq 1 ]; then
            (tar -C "$SRC_PARENT" -cf - "$SRC_BASE" | pv -f -s "$SRC_SIZE" -n | zstd -T0 -q -o "$OUT_PATH") 2>&1 \
                | dialog --title "Backing up" --gauge "Backing up $LABEL..." 8 70 0
            clear >/dev/tty
        else
            dialog --title "Directory Backup" --infobox "Backing up $LABEL... (install pv for a progress gauge)" 8 70
            tar -C "$SRC_PARENT" -cf - "$SRC_BASE" | zstd -T0 -q -o "$OUT_PATH"
            clear >/dev/tty
        fi

        FINAL_SIZE=$(du -h "$OUT_PATH" | cut -f1)
        OUT_INFO+="  $OUT_PATH  ($FINAL_SIZE)\n"
        i=$((i+1))
    done

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    beep
    dialog --title "Backup complete" --msgbox "Backed up $NDIRS director$([ "$NDIRS" -eq 1 ] && echo y || echo ies) in $((ELAPSED/60))m $((ELAPSED%60))s:\n\n$OUT_INFO\nVerify with:\nzstd -t <file>" $((11+NDIRS)) 78
    clear >/dev/tty
    exit 0
    ;;

esac
done
