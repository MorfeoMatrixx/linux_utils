# PiDP-11 (RPi3) — Backup and restore scripts for full node upgrade

Node: `pidp-11` (`pidp-11.local`, `192.168.1.131`), Raspberry Pi 3 Model B
Plus, Raspbian GNU/Linux 9 (Stretch) — EOL, being reinstalled fresh.

Two scripts, both installed at `~/bin/` on the node:

- `pidp11-node-backup.sh` — run **before** the reinstall
- `pidp11-node-restore.sh` — run **after** the reinstall

Both live in [`utils/pidp11-node-backup/`](.) in the `linux_utils` repo.
Depends on the [`smb-user-mount`](../smb-user-mount) setup for
`/home/pi/wdnas1`, and on `pi` having passwordless `sudo` on this node.

## Why not just image the whole SD card

The point of this reinstall is a *fresh* Raspberry Pi OS Desktop image and
an updated PiDP-11 simulator — not a clone of the current Stretch install.
So the backup only needs to capture what a fresh image + fresh simulator
install wouldn't already bring back on their own.

## What gets backed up

| Archive / file | Contents | Size (2026-09-01 run) |
|---|---|---|
| `pidp-11_userdata_<ts>.tar.gz` | `home/pi` (minus the `wdnas1` mount point itself and a few transient logs) + `usr/local` | 1.05 GB |
| `pidp-11_etc-boot_reference_<ts>.tar.gz` | `etc/`, `boot/config.txt`, `boot/cmdline.txt` — **reference only**, see below | 903 KB |
| `pidp-11_packages_<ts>.txt` | `apt-mark showmanual` output (plain text) | 6 KB |
| `pidp-11_dpkg-selections_<ts>.txt` | Full `dpkg --get-selections`, for reference/completeness | 45 KB |
| `MANIFEST_<ts>.txt` | Human-readable summary of the above, restore commands inline | 1 KB |

Written to `/home/pi/wdnas1/backup/pidp-11_backup/<timestamp>/` on the NAS.

### What's deliberately excluded

- **Stock Raspberry Pi OS Desktop content** — `/opt/sonic-pi`,
  `/opt/minecraft-pi`, `/opt/Wolfram`, `/opt/vc`. These ship by default in
  every Desktop image install, so reinstalling the same image variant
  brings them back automatically; backing them up would just waste space
  and time (~250 MB).
- **`/opt/pidp11`** (the simulator itself, ~3.8 GB) — being reinstalled and
  updated fresh as part of this upgrade, not restored from backup. No
  significant local customizations there were worth preserving.

### Tool choice: `tar` + `gzip`, one archive per concern

Raspbian Stretch is EOL — its `apt` mirror has dropped the old package
files, so `zstd` (used elsewhere in this repo, e.g.
[`dir-backup.sh`](../backup2nas/dir-backup.sh)) isn't reliably installable
here. `gzip` ships by default on every Debian-based system and needs no
network access, so that's what this uses instead.

Content is split into a few purpose-scoped archives rather than one giant
tarball, specifically so `/etc` — which needs special handling on restore
(see below) — is never mixed in with the plain user data that's safe to
restore outright.

## How to restore (after the fresh RPiOS Desktop install)

1. Redo the [`smb-user-mount`](../smb-user-mount) one-time setup so
   `/home/pi/wdnas1` is mounted again.
2. Copy `pidp11-node-restore.sh` back to `~/bin/` (`scp` from this repo, or
   re-clone `linux_utils`).
3. Run it:
   ```bash
   ~/bin/pidp11-node-restore.sh          # picks the most recent backup
   ~/bin/pidp11-node-restore.sh 20260901_2040   # or a specific timestamp
   ```

It prints the backup's manifest and asks for confirmation before doing
anything, then works through four steps:

### 1. `home/pi` + `usr/local`

Restored directly and wholesale (`sudo tar -C / -xzf ...`) — pure user
content, nothing security-sensitive, safe to overlay outright.

### 2. Packages

Reinstalls every package from `pidp-11_packages_<ts>.txt`, **one at a
time** rather than in a single batch — a single missing/renamed package
in an `apt install pkg1 pkg2 pkg3 ...` batch call aborts the whole
install, which is likely on hardware this old moving to a current OS
release. Failures are logged to
`~/pidp11_restore_staging/failed_packages_<ts>.txt` for manual review
instead of blocking the rest.

### 3. `/etc` and `/boot` — handled specially, not blanket-restored

Blanket-restoring `/etc` would bring the *old* install's SSH host keys,
`shadow`/`passwd`, `sudoers`, and other identity/credential files back on
top of a fresh install that already generated its own. So:

- The `etc-boot_reference` archive is extracted to a **staging directory
  only** (`~/pidp11_restore_staging/etc-boot_<ts>/`) — never applied to
  the live `/etc` directly.
- **`/boot/config.txt` is auto-applied.** It's pure hardware config for
  the PiDP-11 front panel (`spi=off`, `hdmi_force_mode`, `gpu_mem=256`,
  etc.) with no security content, so it's safe to overwrite outright. The
  fresh install's original is saved first as `/boot/config.txt.fresh-orig`
  in case anything needs to be cross-checked.
- **`/boot/cmdline.txt` is deliberately left alone**, even though it's in
  the archive. It contains `root=PARTUUID=...` pointing at the *old*
  install's partition table. Copying it verbatim onto a fresh install
  would point the kernel's root filesystem at a partition that no longer
  exists — the node would fail to boot. Only copy specific settings out of
  it by hand if needed; never the `root=` line.
- **Everything else under `/etc`**: the script prints a diff summary of
  files that actually differ from the fresh install's `/etc`, with known
  security-sensitive paths hard-excluded from that list entirely — never
  shown, never auto-applied:
  ```
  shadow, shadow-, gshadow, gshadow-, passwd-, group-, sudoers,
  sudoers.d/*, ssh/ssh_host_*, ssl/private, .pwd.lock, dhcpcd.secret,
  security/opasswd, polkit-1/localauthority
  ```
  Review what's left in the diff and copy over only what you recognize as
  a genuine customization (a custom udev rule, a service config, etc.),
  by hand — the fresh install keeps its own identity/credential files
  throughout.

### 4. Reboot

Recommended once the above completes, especially since `/boot/config.txt`
changed.

## History / notes

- 2026-08-27: `smb-user-mount` set up on this node (passwordless `sudo`
  instead of an `/etc/fstab` entry — the user already has full,
  passwordless `sudo` here, so a scoped sudoers rule or fstab `user`
  option would have been redundant).
- 2026-09-01: First real backup run (`20260901_2040`) — caught and fixed a
  bug where the `/etc` archive step needed `sudo` (it contains root-only
  files) and was silently producing a truncated archive without it; both
  archives verified with `gzip -t` and spot-checked for the expected
  files (`shadow`, `sudoers`, SSH host keys present in the etc archive).
  Restore script's staging/diff/security-filter logic verified against
  this same backup (extraction, diff, and sensitive-pattern exclusion all
  confirmed working) — the actual restore steps (package reinstall,
  `/boot/config.txt` overwrite) were not run for real, since this node
  hasn't been reinstalled yet.
