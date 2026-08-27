#!/usr/bin/env bash
# sd-backup.sh - Interactive removable media backup to compressed image
# Usage: ./sd-backup.sh

set -euo pipefail

echo "=================================================="
echo "  SD / USB Card Backup Utility"
echo "=================================================="
echo

# ---------- 1. SELECT SOURCE DEVICE ----------
echo "Available removable devices:"
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

# Warn and unmount any mounted partitions of this device
for part in $(lsblk -lnpo NAME "$SRC_DEV" | tail -n +2); do
    if mount | grep -q "^$part "; then
        echo "Unmounting $part ..."
        udisksctl unmount -b "$part" 2>/dev/null || sudo umount "$part" 2>/dev/null || true
    fi
done

# ---------- 2. SELECT DESTINATION ----------
echo
echo "Available destinations:"
echo

mapfile -t DESTS < <(
    { find /media/jlc -mindepth 1 -maxdepth 1 -type d -printf '%p (auto)\n' 2>/dev/null
      find /mnt/wdnas_public -mindepth 1 -maxdepth 1 -type d -printf '%p (fstab)\n' 2>/dev/null
    } | sort
)

if [ ${#DESTS[@]} -eq 0 ]; then
    echo "No mounted destinations found under /media/jlc/ or /mnt/wdnas_public/."
    read -e -i "/mnt/wdnas_public/" -rp "Enter destination path manually: " DEST_DIR
else
    i=1
    for d in "${DESTS[@]}"; do
        avail=$(df -h "${d% (*)}" | awk 'NR==2 {print $4}')
        echo "  [$i] $d  (free: $avail)"
        i=$((i+1))
    done
    echo "  [$i] Enter path manually"
    echo
    read -rp "Select destination number: " dest_choice

    if [ "$dest_choice" -eq "$i" ]; then
        read -e -i "/mnt/wdnas_public/" -rp "Enter destination path manually: " DEST_DIR
    else
        DEST_DIR="${DESTS[$((dest_choice-1))]% (*)}"
    fi
fi

if [ ! -d "$DEST_DIR" ]; then
    echo "Destination directory does not exist: $DEST_DIR"
    exit 1
fi

# ---------- 3. FILENAME + CONFIRM ----------
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

# ---------- 4. RUN BACKUP ----------
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
echo
