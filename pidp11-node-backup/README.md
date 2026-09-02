# pidp11-node-backup

Backs up everything on the `pidp-11` RPi (Raspbian Stretch) that isn't part
of a stock Raspberry Pi OS Desktop install, ahead of a clean reinstall.

Run directly on the node (`ssh pidp-11 ~/bin/pidp11-node-backup.sh`) — it
writes into `/home/pi/wdnas1/backup/pidp-11_backup/<timestamp>/` on the NAS.

## What's included / excluded

- `home/pi` + `usr/local` — real user content, minus the `wdnas1` mount
  itself and a few transient log files.
- `etc/`, `boot/config.txt`, `boot/cmdline.txt` — captured with `sudo` (real
  `/etc` contains root-only files: `shadow`, SSH host keys, `sudoers`), but
  kept as a **reference-only** archive. Don't blanket-restore this over a
  fresh install — diff it by hand instead, since a fresh install's own
  `/etc` defaults (new SSH host keys, `/etc/passwd`, etc.) matter.
- `apt-mark showmanual` + `dpkg --get-selections` as plain text, for
  `apt install $(cat pidp-11_packages_<ts>.txt)` after reinstalling.
- **Excluded as stock Desktop content** (comes back automatically with the
  same image variant): `/opt/sonic-pi`, `/opt/minecraft-pi`, `/opt/Wolfram`,
  `/opt/vc`.
- **Excluded by choice**: `/opt/pidp11` (the simulator itself, ~3.8GB) — it's
  being reinstalled/updated fresh rather than restored from backup.

## Restore (after a fresh RPiOS Desktop install)

Redo the [smb-user-mount](../smb-user-mount) setup first so
`/home/pi/wdnas1` is mounted, then:

```bash
~/bin/pidp11-node-restore.sh          # picks the most recent backup
~/bin/pidp11-node-restore.sh 20260901_2040   # or a specific one
```

It handles `home/pi` + `usr/local` directly (safe, pure user content), and
reinstalls the manually-tracked packages one at a time (failures — renamed/
removed packages on the new OS version — are logged, not fatal).

`/etc` gets special handling, since blanket-restoring it would bring back
the *old* install's SSH host keys, `shadow`/`passwd`, `sudoers`, etc. on top
of a fresh install that already generated its own:

- Extracted to a staging dir only, never applied directly.
- `/boot/config.txt` is auto-applied — it's pure hardware config (the
  PiDP-11 front panel's `spi=off`/`hdmi_force_mode`/`gpu_mem=256` overlay
  settings), no security content. The fresh install's original is saved
  as `/boot/config.txt.fresh-orig` first.
- `/boot/cmdline.txt` is deliberately **not** auto-applied even though it's
  in the archive — it contains `root=PARTUUID=...` pointing at the *old*
  install's partition. Copying it verbatim onto a fresh install would
  point root at a partition that no longer exists and the node would fail
  to boot. Only pull specific settings from it by hand, never the `root=`
  line.
- Everything else in `/etc`: prints a diff summary of files that actually
  differ from the fresh install, with known security-sensitive paths
  (`shadow`, `sudoers`, SSH host keys, `ssl/private`, ...) excluded from
  the list entirely — review what's left and copy over only what you
  recognize as a real customization, by hand.

## Notes

- This node runs Raspbian Stretch, which is EOL — its apt mirror has
  dropped the old package files, so `zstd` isn't reliably installable.
  Uses plain `gzip` instead (ships by default, no network needed).
- Requires the `smb-user-mount` setup (`/home/pi/wdnas1`) to already be
  mounted; aborts if it isn't.
