# sd-backup.sh — Session Notes (for Claude Code handoff)

## Context
Interactive bash script to back up an SD/USB card to a compressed `.img.zst` image, saving to a NAS or local mount, on Pop!_OS (host `pop-os`, user `jlc`). Built/debugged in claude.ai chat; moving to Claude Code since file downloads aren't working reliably in Claude Desktop (Linux, no browser) this session, despite working in a previous session.

## Current status: WORKING
Script ran successfully end-to-end on a 32GB SanDisk Ultra A1 card via USB 3.0 reader. `dd | zstd -T0` completed cleanly (32GB read, ~22.6 MB/s, no I/O errors). A trailing summary section threw a bash syntax error *after* the backup itself had already completed — likely leftover/duplicated content from prior incremental `sed` edits, not a data-loss issue. Verify the resulting image with:
```bash
zstd -t /path/to/backup_sdX_*.img.zst
```

## Known-good reference version
- 159 lines, md5sum: `b4f4e941be0a118e49c82b98a186b7d8`
- Convention: `~/bin/sd-backup.sh`, run via `sd-backup.sh` (assumes `~/bin` in `$PATH`)

## Bugs found & fixed this session
1. **`RM` flag unreliable** on some USB card readers (reports `RM=0` despite being USB) — fixed by filtering on `TRAN=usb` via `lsblk -P` instead.
2. **`awk` field-splitting broke** on `MODEL` values with spaces (`"STORAGE DEVICE"`) — fixed by parsing `lsblk -P` (key="value") output via `eval` per line.
3. **Missing `-p` flag** — `lsblk` without it returned bare names (`sdb`) instead of full paths (`/dev/sdb`), which would've broken `dd if=$SRC_DEV`. Fixed: flags are `-Pdnpo`.
4. **Repeated file corruption from incremental `sed`/patch edits** — stale/duplicated code blocks accumulated (old `awk` block coexisting with new `eval` function; a duplicated `Proceed? (y/N)` fragment causing a syntax error post-backup). **Lesson: full-file `cat > file << 'EOF'` replacement is safer than incremental patching in a plain chat interface** — main reason for moving to Claude Code.
5. **File downloads not working in Claude Desktop (Linux, no browser)** this session, despite working previously. Root cause not identified from the chat side. Worked around via full-text paste + `bash -n` + `md5sum` verification.

## Full current script (known-good)

```bash
#!/usr/bin/env bash
# sd-backup.sh - Interactive removable media backup to compressed image
set -euo pipefail

echo "=================================================="
echo "  SD / USB Card Backup Utility"
echo "=================================================="
echo

get_usb_devices() {
    lsblk -Pdnpo NAME,SIZE,MODEL,TRAN | while IFS= read -r line; do
        eval "$line"
        if [ "$TRAN" = "usb" ]; then
            echo "${NAME}|${SIZE}|${MODEL}"
        fi
    done
}

get_all_disks() {
    lsblk -Pdnpo NAME,SIZE,MODEL,TYPE | while IFS= read -r line; do
        eval "$line"
        if [ "$TYPE" = "disk" ]; then
            echo "${NAME}|${SIZE}|${MODEL}"
        fi
    done
}

echo "Available removable devices:"
echo

mapfile -t DEVICES < <(get_usb_devices)

if [ ${#DEVICES[@]} -eq 0 ]; then
    echo "No USB devices found. Insert your SD/USB reader and try again."
    echo
    echo "Showing all disk devices as fallback (BE CAREFUL to pick the right one):"
    echo
    mapfile -t DEVICES < <(get_all_disks)
    if [ ${#DEVICES[@]} -eq 0 ]; then
        echo "No disk devices found at all. Exiting."
        exit 1
    fi
fi

i=1
for dev in "${DEVICES[@]}"; do
    IFS='|' read -r name size model <<< "$dev"
    echo "  [$i] $name  -  $size  -  $model"
    i=$((i+1))
done
echo

read -rp "Select source device number: " src_choice
SRC_DEV=$(echo "${DEVICES[$((src_choice-1))]}" | cut -d'|' -f1)

if [ -z "$SRC_DEV" ]; then
    echo "Invalid selection."
    exit 1
fi

echo
echo "Selected source: $SRC_DEV"
lsblk -f "$SRC_DEV"
echo

for part in $(lsblk -lnpo NAME "$SRC_DEV" | tail -n +2); do
    if mount | grep -q "^$part "; then
        echo "Unmounting $part ..."
        udisksctl unmount -b "$part" 2>/dev/null || sudo umount "$part" 2>/dev/null || true
    fi
done

echo
echo "Available destinations:"
echo

mapfile -t DESTS < <(
    { find /media/jlc -mindepth 1 -maxdepth 1 -type d -printf '%p (auto)\n' 2>/dev/null
      find /mnt -mindepth 1 -maxdepth 1 -type d -printf '%p (fstab)\n' 2>/dev/null
    } | sort
)

if [ ${#DESTS[@]} -eq 0 ]; then
    echo "No mounted destinations found under /media/jlc/ or /mnt/."
    read -rp "Enter destination path manually: " DEST_DIR
else
    i=1
    for d in "${DESTS[@]}"; do
        avail=$(df -h "$d" | awk 'NR==2 {print $4}')
        echo "  [$i] $d  (free: $avail)"
        i=$((i+1))
    done
    echo "  [$i] Enter path manually"
    echo
    read -rp "Select destination number: " dest_choice

    if [ "$dest_choice" -eq "$i" ]; then
        read -rp "Enter destination path manually: " DEST_DIR
    else
        DEST_DIR="${DESTS[$((dest_choice-1))]% (*)}"
    fi
fi

if [ ! -d "$DEST_DIR" ]; then
    echo "Destination directory does not exist: $DEST_DIR"
    exit 1
fi

DEFAULT_NAME="backup_$(basename "$SRC_DEV")_$(date +%Y%m%d_%H%M).img.zst"
read -rp "Output filename [$DEFAULT_NAME]: " OUT_NAME
OUT_NAME="${OUT_NAME:-$DEFAULT_NAME}"
OUT_PATH="$DEST_DIR/$OUT_NAME"

SRC_SIZE=$(lsblk -dnbo SIZE "$SRC_DEV")
SRC_SIZE_H=$(numfmt --to=iec "$SRC_SIZE")

echo
echo "=================================================="
echo "  Ready to backup"
echo "=================================================="
echo "  Source:      $SRC_DEV  ($SRC_SIZE_H)"
echo "  Destination: $OUT_PATH"
echo "=================================================="
echo
read -rp "Proceed? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo
echo "Starting backup... (this reads the full device, then compresses)"
echo

START_TIME=$(date +%s)

sudo dd if="$SRC_DEV" bs=4M status=progress conv=sync,noerror | \
    zstd -T0 -q -o "$OUT_PATH"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

FINAL_SIZE=$(du -h "$OUT_PATH" | cut -f1)

echo
echo "=================================================="
echo "  Backup complete"
echo "=================================================="
echo "  File:    $OUT_PATH"
echo "  Size:    $FINAL_SIZE (from $SRC_SIZE_H source)"
echo "  Time:    $((ELAPSED/60))m $((ELAPSED%60))s"
echo "=================================================="
```

## Open items for Claude Code
1. Overwrite `~/bin/sd-backup.sh` wholesale with the version above (don't patch the existing possibly-corrupted copy).
2. Confirm the already-completed 32GB backup image passes `zstd -t`.
3. Possible next step: a `sd-restore.sh` counterpart using `zstd -d -c file.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync`.

## Relevant preferences
- Concise fix summaries + copy-paste commands, no deep drill-downs.
- Quick-and-dirty over production quality.
- `/mnt/*` = persistent fstab shares (NAS); `/media/jlc/*` = temp auto-mounted media — check both by default.

## Updates

**File:** [~/bin/sd-backup.sh](/home/jlc/bin/sd-backup.sh) (no repo copy exists; this is the only copy)

**Changes made this session:**
1. Fixed a bug where the destination free-space lookup (`df -h "$d"`) passed the full display string (e.g. `/mnt/rpi5_share (fstab)`) instead of the bare path, causing `df: '...': No such file or directory`. Fixed by stripping the ` (auto)`/` (fstab)` suffix with `${d% (*)}` before calling `df` — matches the pattern already used later in the script when the destination is actually selected.
2. Scoped the "fstab" destination listing from all of `/mnt/*` down to just subdirectories of `/mnt/wdnas_public` (the `/media/jlc` auto-mount listing was left unchanged).
3. Both manual-path prompts (`Enter destination path manually`) now use `read -e -i "/mnt/wdnas_public/" ...`, which pre-fills the prompt with that path and enables readline so Tab-completion works.

**Status:** All changes applied and reviewed; not yet re-run/tested live by the user in this session — worth a live run to confirm the `df` fix and tab-completion behave as expected.

**Other notes:**
- User was locating this script's original authoring session and found it lived in a different Claude surface (desktop app "Home" tab) than this CLI session — a known gap since session history/search doesn't span surfaces. No action taken, no roadmap info available.
- Per standing convention ([Sync bin after edit](~/.claude/projects/-home-jlc-claude/memory/feedback_sync_bin_after_edit.md)): normally edits get copied back to the installed bin location — not needed here since `~/bin/sd-backup.sh` *is* the installed location already.
