#!/usr/bin/env bash
# Backs up ~/Linux_RPi/ to the WD NAS share, tuned for a fast LAN.
# Additive backup: files are copied/updated on the NAS but never removed
# there, even if they're deleted locally (no --delete).
set -euo pipefail

SRC_DIR="$HOME/Linux_RPi"
NAS_MOUNT="/mnt/wdnas_public"
NAS_SUBDIR="rpi-shared/Linux_RPi"
NAS_DEST="${NAS_MOUNT}/${NAS_SUBDIR}"
LOG_FILE="$HOME/.local/share/linux-sync.log"
LOCK_FILE="$HOME/.local/share/linux-sync.lock"

mkdir -p "$(dirname "$LOG_FILE")"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }

# Prevent two syncs (e.g. a manual run and a cron catch-up firing at the same
# time) from racing against the same NAS destination at once.
exec 200>>"$LOCK_FILE"
if ! flock -n 200; then
    other_pid="$(tr -d '[:space:]' < "$LOCK_FILE" 2>/dev/null)"
    log "Another linux-sync is already running (PID ${other_pid:-unknown}) — exiting immediately"
    exit 1
fi
printf '%s\n' "$$" > "$LOCK_FILE"

log "=== Starting linux-sync ==="

if [ ! -d "$SRC_DIR" ]; then
    log "ERROR: $SRC_DIR does not exist"
    exit 1
fi

# Make sure the NAS share is mounted (triggers the systemd automount unit
# configured in /etc/fstab if it isn't mounted yet)
if ! mountpoint -q "$NAS_MOUNT"; then
    log "NAS share not mounted; touching $NAS_MOUNT to trigger automount"
    ls "$NAS_MOUNT" >/dev/null 2>&1 || true
    sleep 1
fi

if ! mountpoint -q "$NAS_MOUNT"; then
    log "ERROR: $NAS_MOUNT did not mount. Is wdmycloudex2.local reachable?"
    exit 1
fi

mkdir -p "$NAS_DEST"

# rsync local -> NAS, tuned for a fast LAN:
#   -a             archive mode: preserves perms, times, symlinks, etc.
#   --whole-file   skip the delta-transfer algorithm (its checksumming costs
#                  more CPU than just resending the file over a fast LAN)
#   --no-compress  skip zlib compression (LAN bandwidth is cheap; compressing
#                  just burns CPU for no size benefit)
#   --partial      keep partial transfers so a big interrupted file can resume
#   --bwlimit      cap throughput; this NAS is old enough that unthrottled
#                  writes can make it stall/time out mid-transfer
#   --exclude      skip files and directories whose name starts with "#"
#                  (e.g. scratch/staging dirs like "#Other_OS_Images")
# No --delete: this is an additive backup, files removed locally stay on the NAS.
log "Syncing $SRC_DIR -> $NAS_DEST"
rsync -a \
    --whole-file \
    --no-compress \
    --partial \
    --bwlimit=15m \
    --human-readable \
    --info=progress2 \
    --stats \
    --exclude='#*' \
    "${SRC_DIR}/" "${NAS_DEST}/" 2>&1 | tee -a "$LOG_FILE"

log "=== linux-sync complete ==="
