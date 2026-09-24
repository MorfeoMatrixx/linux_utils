# plasma-migration

Backups and rollback scripts from moving the Lenovo LOQ (Pop!_OS 24.04, RTX 4050 +
Intel hybrid) from Cosmic to KDE Plasma 5.27 on X11, on 2026-09-24. Cosmic is still
installed and selectable at the sddm login screen. These are snapshots of this
specific machine, not general-purpose tools.

Each folder has everything its `rollback.sh` needs. The script finds its files
relative to its own location, so it runs the same from this repo or from the
original copy in `~/`.

## `plasma-migration-backup-20260924-151121/`

Finishing steps of the migration (Plasma, sddm, and the X11 session were already
installed on 2026-09-23):
- installed `dolphin-plugins` (`apt-would-install.txt`: the only package, no extra dependencies)
- set Dolphin as the default for `inode/directory`, replacing `nemo.desktop`

`rollback.sh` restores the original `mimeapps.list`, then shows a dry run and asks
before purging `dolphin-plugins`. It does not remove Plasma or sddm. To go back to
Cosmic, pick it at the login screen.

`mimeapps.list` is shared by all desktops, so this change also makes Dolphin the
default in Cosmic.

## `nvidia-suspend-fix-backup-20260924-151653/`

Fix for an external HDMI monitor (PRIME output) staying dark after suspend/resume
under Plasma X11. Pop's `50-cosmic-no-vt-switch.conf` drop-ins always skip the
`chvt 63` in `nvidia-sleep.sh`: Cosmic needs that, but KWin/X11 relies on the VT
switch. The `60-plasma-vt-switch.conf` drop-ins (copies in `new/`) skip it only
when `cosmic-comp` is running.

- `*.service.d/50-cosmic-no-vt-switch.conf`: Pop's original drop-ins, never modified
- `*.effective-before.txt`: `systemctl cat` output for each unit before the change
- `rollback.sh`: removes the `60-` drop-ins, reloads systemd, compares each unit
  against its before-change snapshot, and reinstalls any `50-` file that has gone
  missing

To **reapply** the fix after an OS or driver upgrade, don't use these files. Use
[`../plasma-suspend-fix/plasma-suspend-fix-redo.sh`](../plasma-suspend-fix/plasma-suspend-fix-redo.sh),
which checks first and only rewrites what's missing or changed.

Hibernate is intentionally not configured (swap is encrypted with a new random key
each boot and is too small). This machine uses suspend only.

Left out of the repo: `packages-before.txt` (full `dpkg --get-selections` list),
which neither script uses. It remains in the `~/` copy of the backup.
