#!/usr/bin/env bash
# One-time setup: adds an fstab entry + systemd automount for the WD MyCloud
# EX2 NFS share, instead of mounting it from a per-user login script.
#
# Why fstab + systemd automount and not a login script:
#   - Runs as root via systemd, so jlc never needs a sudo password to mount it.
#   - Mounts on first access (not at boot), so a slow/offline NAS never delays
#     boot or login.
#   - x-systemd.idle-timeout auto-unmounts after inactivity, so a NAS that
#     later goes offline won't leave a stale/hung mount behind.
#   - nofail means a bad/unreachable entry can never break booting.
#   - A login script would need stored sudo rights for jlc, only fires once
#     at login (silently stays unmounted for the session if the NAS isn't up
#     yet), and has no retry/idle-unmount logic of its own.
set -euo pipefail

MOUNT_POINT="/mnt/wdnas_public"
NFS_SERVER="wdmycloudex2.local"
NFS_EXPORT="/mnt/HD/HD_a2/Public"
FSTAB_LINE="${NFS_SERVER}:${NFS_EXPORT} ${MOUNT_POINT} nfs _netdev,x-systemd.automount,x-systemd.idle-timeout=60,x-systemd.mount-timeout=10,noauto,nofail,soft,timeo=30,retrans=2,rw,vers=3 0 0"

echo "Installing nfs-common..."
sudo apt-get update -qq
sudo apt-get install -y nfs-common

echo "Creating mount point $MOUNT_POINT..."
sudo mkdir -p "$MOUNT_POINT"

if grep -qF "$MOUNT_POINT" /etc/fstab; then
    echo "An /etc/fstab entry for $MOUNT_POINT already exists — leaving it as-is."
    echo "Edit /etc/fstab manually if it needs to change."
else
    backup="/etc/fstab.bak.$(date +%s)"
    echo "Backing up /etc/fstab to $backup"
    sudo cp /etc/fstab "$backup"
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
    echo "Added fstab entry:"
    echo "  $FSTAB_LINE"
fi

sudo systemctl daemon-reload

echo "Triggering mount to verify it works..."
if sudo mount "$MOUNT_POINT" && mountpoint -q "$MOUNT_POINT"; then
    echo "Mounted successfully at $MOUNT_POINT"
else
    echo "Mount failed — check that $NFS_SERVER is reachable and that" >&2
    echo "$NFS_EXPORT is exported to this host (NFS, not just SMB)." >&2
    exit 1
fi
