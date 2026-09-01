#!/usr/bin/env bash
# mount-wdnas1.sh - Mount the wdnas1 SMB share. Runs as root (via a scoped
# sudoers NOPASSWD rule, see README.md) so no /etc/fstab entry is needed.
# Meant to be called from ~/.profile as: sudo ~/bin/mount-wdnas1.sh &

set -uo pipefail

MOUNT_POINT="/home/pi/wdnas1"
SOURCE="//wdmycloudex2.local/public_2/pidp11-share/cpmshare"
CREDENTIALS="/home/pi/.smbcredentials_wdnas"
LOG_TAG="mount-wdnas1"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    exit 0
fi

opts="credentials=$CREDENTIALS,uid=pi,gid=pi,iocharset=utf8,vers=3.0,soft"

if err=$(timeout 15 mount -t cifs "$SOURCE" "$MOUNT_POINT" -o "$opts" 2>&1); then
    logger -t "$LOG_TAG" "Mounted $MOUNT_POINT"
else
    logger -t "$LOG_TAG" "Failed to mount $MOUNT_POINT: $err"
fi
