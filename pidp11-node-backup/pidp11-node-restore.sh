#!/usr/bin/env bash
# pidp11-node-restore.sh - Restore a pidp11-node-backup.sh backup onto a
# freshly (re)installed pidp-11. Run on the node itself, after RPiOS Desktop
# is installed, the smb-user-mount setup is redone (see ../smb-user-mount),
# and /home/pi/wdnas1 is mounted.
#
# Usage: pidp11-node-restore.sh [timestamp]
#   timestamp - one of the dirs under the backup root, e.g. 20260901_2040.
#               Defaults to the most recent one found.
#
# --- /etc handling: read this before running ---
# home/pi and usr/local are restored directly - they're pure user content,
# safe to overlay wholesale. /etc is NOT: blanket-restoring it would bring
# back the OLD install's SSH host keys, shadow/passwd, sudoers, etc. on top
# of a fresh install that already generated its own. So this script:
#   1. Extracts the etc/boot archive to a staging dir only - never touches
#      the live /etc directly.
#   2. Auto-applies just /boot/config.txt - hardware-specific PiDP-11
#      overlay settings (spi=off, hdmi_force_mode, gpu_mem=256, ...), no
#      security content, safe to overwrite outright. The fresh one is
#      backed up first as config.txt.fresh-orig.
#   3. Deliberately does NOT touch /boot/cmdline.txt even though it's in
#      the archive: it contains root=PARTUUID=... pointing at the OLD
#      install's partition. Copying it verbatim onto a fresh install
#      would point root at a partition that no longer exists and the
#      node would fail to boot.
#   4. For the rest of /etc, prints a diff summary of files that differ
#      from the fresh install - excluding known security-sensitive paths
#      (shadow, sudoers, ssh host keys, ...) which are never shown or
#      auto-applied. Review the list and copy over only what you
#      recognize as a real customization, by hand.

set -uo pipefail

BACKUP_ROOT="/home/pi/wdnas1/backup/pidp-11_backup"
STAGING="/home/pi/pidp11_restore_staging"

# /etc paths never shown in the diff summary or auto-applied - anything
# tied to host identity or credentials.
SENSITIVE_PATTERN='^etc/(shadow|shadow-|gshadow|gshadow-|passwd-|group-|sudoers|sudoers\.d/|ssh/ssh_host_|ssl/private|\.pwd\.lock|dhcpcd\.secret|security/opasswd|polkit-1/localauthority)'

TS="${1:-}"
if [[ -z "$TS" ]]; then
    TS="$(ls -1 "$BACKUP_ROOT" 2>/dev/null | sort | tail -1)"
    [[ -n "$TS" ]] || { echo "No backups found under $BACKUP_ROOT"; exit 1; }
    echo "No timestamp given, using most recent: $TS"
fi

DIR="$BACKUP_ROOT/$TS"
[[ -d "$DIR" ]] || { echo "Backup dir not found: $DIR"; exit 1; }

mountpoint -q /home/pi/wdnas1 || { echo "NAS not mounted at /home/pi/wdnas1, aborting."; exit 1; }

echo "Restoring from: $DIR"
cat "$DIR/MANIFEST_$TS.txt" 2>/dev/null
echo

read -rp "Proceed? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy] ]] || { echo "Aborted."; exit 0; }

echo
echo "=== 1/4: Restoring home/pi + usr/local ==="
sudo tar -C / -xzf "$DIR/pidp-11_userdata_$TS.tar.gz"
echo "Done."

echo
echo "=== 2/4: Reinstalling manually-installed packages ==="
mkdir -p "$STAGING"
FAILED_PKGS="$STAGING/failed_packages_$TS.txt"
> "$FAILED_PKGS"
while read -r pkg; do
    [[ -z "$pkg" ]] && continue
    sudo apt-get install -y "$pkg" >/dev/null 2>&1 || echo "$pkg" >> "$FAILED_PKGS"
done < "$DIR/pidp-11_packages_$TS.txt"
FAILED_COUNT=$(wc -l < "$FAILED_PKGS")
if [[ "$FAILED_COUNT" -gt 0 ]]; then
    echo "$FAILED_COUNT package(s) failed to install (renamed/removed upstream, most likely)."
    echo "List saved to: $FAILED_PKGS - review by hand."
else
    echo "All packages installed."
    rm -f "$FAILED_PKGS"
fi

echo
echo "=== 3/4: /boot/config.txt (safe to auto-apply - hardware settings only) ==="
STAGE_ETC="$STAGING/etc-boot_$TS"
mkdir -p "$STAGE_ETC"
tar -C "$STAGE_ETC" -xzf "$DIR/pidp-11_etc-boot_reference_$TS.tar.gz"

if [[ -f "$STAGE_ETC/boot/config.txt" ]]; then
    sudo cp /boot/config.txt /boot/config.txt.fresh-orig
    sudo cp "$STAGE_ETC/boot/config.txt" /boot/config.txt
    echo "Applied. Fresh install's original saved as /boot/config.txt.fresh-orig."
else
    echo "No boot/config.txt found in this backup, skipping."
fi
echo
echo "NOT touching /boot/cmdline.txt - it has root=PARTUUID=... from the OLD"
echo "install's partition table. Copying it verbatim would point root at a"
echo "partition that no longer exists. Reference copy is at:"
echo "  $STAGE_ETC/boot/cmdline.txt"
echo "(only copy specific settings from it by hand, never the root= line)"

echo
echo "=== 4/4: /etc diff summary (security-sensitive paths excluded) ==="
if [[ -d "$STAGE_ETC/etc" ]]; then
    diff -rq "$STAGE_ETC/etc" /etc 2>/dev/null \
        | grep -vE "$SENSITIVE_PATTERN" \
        | grep -E '^(Only in|Files) ' \
        || echo "(no differences outside security-sensitive files)"
    echo
    echo "Full reference copy of the old /etc is at: $STAGE_ETC/etc"
    echo "Security-sensitive files (shadow, sudoers, ssh host keys, ...) exist"
    echo "there too but are intentionally excluded from the diff above - the"
    echo "fresh install's own versions of those should be kept, not the old"
    echo "node's. Copy over only specific files you recognize as real"
    echo "customizations (e.g. a custom udev rule, a service config)."
else
    echo "No etc/ found in this backup, skipping."
fi

echo
echo "Restore steps done. A reboot is recommended before using the machine."
