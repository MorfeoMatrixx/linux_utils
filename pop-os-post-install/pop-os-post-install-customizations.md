# Pop!_OS post-install customizations

`pop-os-post-install-customizations.sh` rebuilds my setup on a **fresh Pop!_OS 24.04 install** on the Lenovo LOQ (NVIDIA RTX 4050 + Intel hybrid graphics). It covers everything customized since the original install on 2026-06-10:

- apps and repositories
- KDE Plasma 5.27 installed **alongside** Cosmic
- the system fixes the laptop needs
- the utilities from this repo
- dotfiles
- the Plasma look and behaviour

It replaces redoing all of that by hand from old notes and sessions.

**How it behaves:**
- **Checks before it acts.** It checks every item first and only changes what's missing, so it's safe to re-run at any time.
- **Backs up before overwriting.** It copies every file it modifies to `~/pop-os-post-install-backup-<timestamp>/` first.
- **Keeps secrets out of the repo.** The NAS password and git email are asked for during the run and never stored here; this repo is public.

## ⚠ Mandatory: the NVIDIA suspend/wake fix

On this laptop, **Plasma X11 does not recover the HDMI monitor after suspend** unless the NVIDIA sleep hooks do their virtual-terminal (VT) switch. Pop's Cosmic setup (the `50-cosmic-no-vt-switch.conf` drop-ins) turns that switch off for every session, because Cosmic crashes with it. The `60-plasma-vt-switch.conf` drop-ins make it conditional: the switch is skipped only when Cosmic's compositor is running.

- The `system` section installs both drop-ins; the `60-` ones go in through [`plasma-suspend-fix-redo.sh`](../plasma-suspend-fix/plasma-suspend-fix-redo.sh).
- `utils` installs that script to `~/.local/bin/` for later use.
- **Every run ends with a mandatory check of the fix.** If it's missing or blocked, it prints `MISSING`/`BLOCKED` in red and exits with status 1, even in `--check` mode.
- After any future OS or NVIDIA driver upgrade, run `plasma-suspend-fix-redo.sh --check` (see [../plasma-migration/README.md](../plasma-migration/README.md) for the background).

## What it does

| Section | What it covers |
|---|---|
| `repos` | GitHub CLI and Claude Desktop apt repositories (the Claude signing key is in `assets/`) |
| `apt` | KDE Plasma 5.27 with **sddm** preselected as display manager (Cosmic stays installed and selectable), Google Chrome (Google's `.deb`), Claude Desktop, and all apt apps: Tilix, KWrite/Kate, Okular, gThumb, VLC/mpv, Geany, Thonny, NAS/network tools, dev tools, GPU tools, media codecs, OCR, and the tools our utilities need (`dialog`, `pv`, `xdotool` and so on) |
| `flatpak` | MarkText, OrcaSlicer, PhotoCollage, Decoder, Angry IP Scanner, qBittorrent, NetPeek (from Flathub), and cosmic-ext-connected (from the Cosmic Flatpak repo) |
| `extras` | fastfetch (latest `.deb`), yscan (`cargo`), crontab-ui (`npm` + user service), Claude Code (official installer). Reminds you about FlashForgeUI and Flash Studio, which have no stable download URL |
| `system` | **The NVIDIA suspend/wake fix** (above), the `spd5118` kernel-module blacklist (fixes a suspend crash on the LOQ), NAS CIFS automounts in `/etc/fstab` plus the credentials file (prompted), `/etc/hosts` pins for the NAS and pidp-11, a sudoers rule so `system76-power` runs without a password, and the `/etc/profile.d/vte.sh` link for Tilix. Passwordless sudo is **opt-in** (`--nopasswd-sudo`) |
| `utils` | Clones this repo if needed and installs our utilities: `dir-backup.sh`, `sd-backup.sh`, grok-sync, grok-dedup, linux-sync, `linux-nodes-status.sh`, `ssh-node-setup.sh`, lanscan, gpu-mode, `set-default-apps.sh`, `plasma-suspend-fix-redo.sh`, plus their icons and app-menu launchers |
| `dotfiles` | The `JLC CUSTOMIZATIONS` block in `~/.bashrc` (PATH, the Tilix fix, the hybrid-GPU video fix, crontab-ui's database path), git identity, `gh auth login` |
| `plasma` | **Only inside a Plasma session.** Tilix as the default terminal with Ctrl+Alt+T, Tilix using the normal window frame, double-click to open, Breeze window decoration with a 4 px border, the `cosmic-jlc` colour scheme (purple title bar and border on the focused window with black title text; dark on the others), default apps (KWrite for text and code, MarkText for `.md`, Okular for PDF, Dolphin for folders), and NAS bookmarks in Dolphin's sidebar |

**Assets** (`pop-os-post-install/assets/`):
- `cosmic-jlc.colors`: the colour scheme
- `nvidia/*-50-cosmic-no-vt-switch.conf`: the Cosmic drop-ins
- `claude-desktop-archive-keyring.asc`: the public signing key for the Claude Desktop apt repo

## Instructions for a fresh install

### 0. Before you wipe the old system

Back these up somewhere safe (NAS or USB). The script can't recreate them:
- `~/.ssh/`: SSH keys and `config`
- `~/.crontab-ui/`: crontab-ui job database, if you want your jobs back
- The FlashForgeUI `.deb` and `~/Apps/Flash_Studio*.AppImage`, if still used
- Your NAS SMB username and password (you'll be asked for them)

### 1. Install Pop!_OS

1. Install Pop!_OS 24.04 from the **NVIDIA** ISO, with the same username (`jlc`).
2. Log in (Cosmic), connect to the network, and update:
   ```bash
   sudo apt update && sudo apt full-upgrade -y
   ```
3. Reboot.

### 2. Get this repo

```bash
sudo apt install -y git
git clone https://github.com/MorfeoMatrixx/linux_utils.git ~/claude/utils
cd ~/claude/utils/pop-os-post-install
```

### 3. See what it will do (optional, changes nothing)

```bash
./pop-os-post-install-customizations.sh --check
```

On a fresh system almost everything shows as `TODO`. The final mandatory check will say `MISSING`; that's expected before the first real run.

### 4. Run it (phase 1, still in Cosmic)

```bash
./pop-os-post-install-customizations.sh
```

Add `--nopasswd-sudo` if you want sudo without a password.

The run goes like this:
- It shows the summary and asks for your sudo password once.
- For each section it prints `OK` for items already in place and `TODO` for missing ones, then asks **"Apply [section]? [y/N]"**.
- Answer `y` for each. The `plasma` section is skipped automatically, because you're not in Plasma yet.
- It asks for the NAS SMB username and password (written to `/etc/.smbcredentials_wdnas`, root-only), your git email, and runs the interactive `gh auth login`.
- It ends with the **mandatory NVIDIA fix check**, which should say `OK`.

To run without the questions, use `-y`. The secret prompts are then skipped; the script tells you what to do afterwards.

### 5. Reboot

The reboot activates the `spd5118` blacklist (built into the boot image by the script), the sddm login screen, and the NAS automounts.

### 6. Log into Plasma X11

At the **sddm** login screen, open the session menu and choose **"Plasma"**. **Not** "Plasma (Wayland)": the X11 session is the one this setup and OrcaSlicer are known to work with on this hardware. Then log in.

### 7. Run the Plasma part (phase 2)

1. **Open Dolphin once, then close it.** This creates its sidebar file, which the script adds the NAS bookmarks to.
2. Run:
   ```bash
   ~/claude/utils/pop-os-post-install/pop-os-post-install-customizations.sh --only plasma
   ```
3. Close all Tilix windows and reopen it (Ctrl+Alt+T) so it picks up the normal window frame. Logging out and back in once also refreshes everything.

### 8. Verify

- **Suspend/wake with the HDMI monitor connected** (mandatory). Suspend, wake, and confirm the external monitor comes back without needing a replug or `xrandr`. Then:
  ```bash
  journalctl -b -t suspend | tail -3            # expect: "non-COSMIC: normal VT switch"
  plasma-suspend-fix-redo.sh --check            # expect: "Fix is in place - nothing to do."
  ```
- **NAS:** open `wdnas_public` in Dolphin's sidebar. It should mount on first access.
- **Window focus:** click between two windows. The focused one has a purple title bar and border.
- **Default apps:** double-click a `.sh`, a `.md` and a `.pdf`. They should open in KWrite, MarkText and Okular.
- **Whole setup:** `./pop-os-post-install-customizations.sh --check` should show `OK` everywhere and exit 0.

### 9. Manual follow-ups

- Restore `~/.ssh/` from backup (`chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*`) and, if wanted, `~/.crontab-ui/`.
- Install FlashForgeUI (`sudo apt install ./FlashForgeUI_*.deb`) and put the Flash Studio AppImage in `~/Apps/`.
- In Chrome, turn on *Settings → Appearance → Use system title bar and borders* to get the purple focus frame on Chrome windows too.

## Options

| Option | Effect |
|---|---|
| *(none)* | Summary, then for each section: check (read-only) → ask → apply |
| `--check` | Report only; changes nothing. Exits 1 if the NVIDIA fix is missing |
| `-y` | Apply everything without asking (secret prompts are skipped) |
| `--only a,b` | Run only these sections: `repos apt flatpak extras system utils dotfiles plasma` |
| `--nopasswd-sudo` | Also create `/etc/sudoers.d/nopasswd-$USER` (sudo without password) |
| `-h` | Show the summary |

Exit codes: `0` success, `1` the mandatory NVIDIA fix isn't in place, `2` usage error or ran as root.

## Troubleshooting

- **No Plasma login screen after reboot (still Cosmic's greeter).** The display-manager preseed didn't take. Run `sudo dpkg-reconfigure sddm`, choose `sddm`, and reboot.
- **HDMI stays dark after resume.** Run `plasma-suspend-fix-redo.sh`. If it says the NVIDIA mechanism changed (`BLOCKED`), the driver's sleep script is different now; investigate before forcing anything.
- **Suspend itself crashes or hangs.** Check that `spd5118` isn't loaded: `lsmod | grep spd5118` should print nothing. The old system also had `mem_sleep_default=deep` on the kernel command line. It isn't set by this script because it's unclear whether Pop!_OS adds it itself. Compare `cat /proc/cmdline` and add it with `sudo kernelstub -a mem_sleep_default=deep` only if needed.
- **The purple border vanished but the title bar is still purple.** This happens after picking the colour scheme again in *System Settings → Colors*, which drops two lines from `~/.config/kdeglobals`. Re-run `--only plasma`.
- **A window has no border at all.** Apps that draw their own title bar (Claude desktop, GTK header-bar apps, Chrome by default) and maximized windows never get the KWin frame. That's expected.
- **Undo a change.** Every file the script changed is in `~/pop-os-post-install-backup-<timestamp>/`, with its full path, e.g. `.../etc/fstab`. Copy it back.

## Deliberately not included

- **Apps dropped:** ReText, Nemo, md-viewer, the wayback-machine gem, and the Claude Desktop terminal fix (the official app is used now).
- **GNOME/Cosmic-era leftovers:** gnome-tweaks, pcmanfm, smb4k, epiphany, webhttrack, cowsay.
- **The old NFS NAS setup** (`grok-sync/setup-nas-mount.sh`): the NAS is mounted over CIFS now.
- **Raspberry Pi utilities** (`pidp11-node-*`, `smb-user-mount`, `uconsole/`): they're for the Pis, not the laptop.
- **The Home Assistant mDNS announcement for the NAS:** it runs on the HA server. See `~/Downloads/handover-nas-smb-mdns-announce.md`.

## Related

- [`../plasma-suspend-fix/`](../plasma-suspend-fix/): the NVIDIA suspend fix reapply tool
- [`../plasma-migration/`](../plasma-migration/): backups and rollback scripts from the original Cosmic → Plasma migration
- [`../default-apps/set-default-apps.sh`](../default-apps/set-default-apps.sh): re-applies the default apps on its own
