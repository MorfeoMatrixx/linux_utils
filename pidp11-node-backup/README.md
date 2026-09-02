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

```bash
sudo tar -C / -xzf pidp-11_userdata_<ts>.tar.gz
apt install $(cat pidp-11_packages_<ts>.txt)
```

Then extract `pidp-11_etc-boot_reference_<ts>.tar.gz` somewhere and diff it
against the fresh `/etc` and `/boot/config.txt` by hand, pulling over only
what's actually needed (e.g. the `spi=off`/`hdmi_force_mode`/`gpu_mem=256`
lines in `config.txt` for the PiDP-11 front panel hardware).

## Notes

- This node runs Raspbian Stretch, which is EOL — its apt mirror has
  dropped the old package files, so `zstd` isn't reliably installable.
  Uses plain `gzip` instead (ships by default, no network needed).
- Requires the `smb-user-mount` setup (`/home/pi/wdnas1`) to already be
  mounted; aborts if it isn't.
