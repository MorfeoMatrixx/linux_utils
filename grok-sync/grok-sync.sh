#!/usr/bin/env bash
# Moves Grok downloads into ~/Pictures/Grok, then rsyncs them to the WD NAS share.
# Requires the NAS automount to be set up first — see setup-nas-mount.sh.
set -euo pipefail

DOWNLOADS_DIR="$HOME/Downloads"
LOCAL_GROK_DIR="$HOME/Pictures/Grok"
NAS_MOUNT="/mnt/wdnas_public"
NAS_SUBDIR="Shared Pictures/EE/Grok3"
NAS_DEST="${NAS_MOUNT}/${NAS_SUBDIR}"
LOG_FILE="$HOME/.local/share/grok-sync.log"

mkdir -p "$LOCAL_GROK_DIR" "$(dirname "$LOG_FILE")"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }

log "=== Starting grok-sync ==="

# 1. Move grok-image*/grok-video* files out of Downloads
moved=0
skipped=()
for f in "$DOWNLOADS_DIR"/grok-image* "$DOWNLOADS_DIR"/grok-video*; do
    [ -f "$f" ] || continue
    dest="$LOCAL_GROK_DIR/$(basename "$f")"
    if [ -e "$dest" ]; then
        skipped+=("$f")
    else
        mv -- "$f" "$LOCAL_GROK_DIR"/
        moved=$((moved + 1))
    fi
done

log "Moved $moved file(s) to $LOCAL_GROK_DIR"

if [ ${#skipped[@]} -gt 0 ]; then
    if [ ${#skipped[@]} -le 20 ]; then
        log "Skipped ${#skipped[@]} file(s) already in $LOCAL_GROK_DIR:"
        for f in "${skipped[@]}"; do log "  $(basename "$f")"; done
    else
        log "Skipped ${#skipped[@]} files already in $LOCAL_GROK_DIR (too many to list)"
    fi

    printf '\nDelete %d skipped file(s) from Downloads? [y/N] ' "${#skipped[@]}"
    read -r answer </dev/tty
    if [[ "${answer,,}" == "y" ]]; then
        for f in "${skipped[@]}"; do
            rm -- "$f" && log "Deleted: $(basename "$f")"
        done
    else
        log "Skipped files left in Downloads"
    fi
fi

# 2. Make sure the NAS share is mounted (triggers the systemd automount unit
#    configured in /etc/fstab if it isn't mounted yet)
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

# 3. rsync local -> NAS, tuned for a fast LAN moving already-compressed media:
#    --whole-file   skip the delta-transfer algorithm (its checksumming costs
#                   more CPU than just resending the file over a fast LAN)
#    --no-compress  skip zlib compression (images/video are already compressed;
#                   compressing them again just burns CPU for no size benefit)
#    --partial      keep partial transfers so a big interrupted video can resume
log "Syncing $LOCAL_GROK_DIR -> $NAS_DEST"
# Add --min-size=100k below if you also want to skip tiny/incomplete files.
rsync -rt \
    --omit-dir-times \
    --whole-file \
    --no-compress \
    --partial \
    --human-readable \
    --info=progress2 \
    --stats \
    "${LOCAL_GROK_DIR}/" "${NAS_DEST}/" 2>&1 | tee -a "$LOG_FILE"

log "=== grok-sync complete ==="
