#!/usr/bin/env bash
# pidp11-node-backup.sh - Back up everything on the pidp-11 RPi that isn't
# part of a stock Raspberry Pi OS (Desktop) install, to the NAS, ahead of a
# clean reinstall. Run directly on pidp-11 (as user pi, which has
# passwordless sudo there). /opt/pidp11 (the simulator install) is
# excluded on purpose - it's being reinstalled/updated fresh, not restored.
#
# Restore after a fresh RPiOS Desktop install:
#   sudo tar -C / -xzf pidp-11_userdata_<ts>.tar.gz
#   apt install $(cat pidp-11_packages_<ts>.txt)
#   Then diff pidp-11_etc-boot_reference_<ts>.tar.gz against the fresh
#   /etc and /boot/config.txt by hand - do NOT blanket-overlay it, the
#   fresh install's own defaults (ssh host keys, /etc/passwd, etc.) matter.

set -euo pipefail

DEST_ROOT="/home/pi/wdnas1/backup/pidp-11_backup"
TS="$(date +%Y%m%d_%H%M)"
DEST="$DEST_ROOT/$TS"

# This node runs Raspbian Stretch (EOL - its apt mirror has dropped the old
# package files), so zstd may not be installable. gzip ships on every
# Debian-based system by default and needs no network access.

mountpoint -q /home/pi/wdnas1 || { echo "NAS not mounted at /home/pi/wdnas1, aborting."; exit 1; }

mkdir -p "$DEST"

echo "=== User data (home/pi + usr/local) ==="
tar -C / \
    --exclude="home/pi/wdnas1" \
    --exclude="home/pi/wget-log" \
    --exclude="home/pi/minicom.log" \
    --exclude="home/pi/minicom.cap" \
    --exclude="home/pi/serial.cap" \
    --exclude="home/pi/mount-nas.log" \
    -czf "$DEST/pidp-11_userdata_$TS.tar.gz" home/pi usr/local

echo "=== /etc + /boot config (reference only - diff on restore, don't overlay) ==="
# sudo: /etc contains root-only files (shadow, ssh host keys, sudoers, ...)
sudo tar -C / -czf "$DEST/pidp-11_etc-boot_reference_$TS.tar.gz" etc boot/config.txt boot/cmdline.txt
sudo chown pi:pi "$DEST/pidp-11_etc-boot_reference_$TS.tar.gz" 2>/dev/null || true

echo "=== Package lists ==="
apt-mark showmanual | sort > "$DEST/pidp-11_packages_$TS.txt"
dpkg --get-selections > "$DEST/pidp-11_dpkg-selections_$TS.txt"

cat > "$DEST/MANIFEST_$TS.txt" <<EOF
pidp-11 backup - $TS

pidp-11_userdata_$TS.tar.gz
  home/pi (minus wdnas1 mount + transient logs), usr/local
  Restore: sudo tar -C / -xzf pidp-11_userdata_$TS.tar.gz

pidp-11_etc-boot_reference_$TS.tar.gz
  etc/, boot/config.txt, boot/cmdline.txt
  REFERENCE ONLY - diff against the fresh install's versions, don't
  blanket-restore (ssh host keys, /etc/passwd etc. differ per install).

pidp-11_packages_$TS.txt
  apt-mark showmanual output. Restore: apt install \$(cat pidp-11_packages_$TS.txt)

pidp-11_dpkg-selections_$TS.txt
  Full dpkg --get-selections, for reference/completeness.

Excluded as stock Raspberry Pi OS Desktop content (reinstalling the same
image variant brings these back automatically):
  /opt/sonic-pi /opt/minecraft-pi /opt/Wolfram /opt/vc

Excluded by choice: /opt/pidp11 (the simulator install) - being
reinstalled/updated fresh rather than restored; no significant local
customizations there worth preserving.
EOF

echo
echo "Done. Backup written to: $DEST"
du -sh "$DEST"/*
