# crontab-ui launcher

A desktop launcher and app icon for [crontab-ui](https://github.com/alseambusher/crontab-ui),
a web UI for managing cron jobs, opened as a chromeless app window instead of
a normal browser tab.

## Requirements

`crontab-ui` is a Node.js application, so Node.js and npm must be installed
first:

```bash
sudo apt install nodejs npm
```

## Install crontab-ui

```bash
sudo npm install -g crontab-ui
```

Point it at a persistent database location (defaults to the current
directory otherwise) by adding this to `~/.bashrc`:

```bash
echo 'export CRON_DB_PATH=~/.crontab-ui' >> ~/.bashrc
source ~/.bashrc
```

Start it with:

```bash
crontab-ui
```

By default it listens on `http://localhost:8000`.

## Run as a systemd user service (autostart on login)

Rather than starting `crontab-ui` manually or relying on the desktop
launcher to spawn it, run it as a systemd **user** service so it starts
automatically on login and restarts itself if it ever crashes.

Create the service file:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/crontab-ui.service << EOF
[Unit]
Description=crontab-ui - web based crontab editor
After=network.target

[Service]
Environment=CRON_DB_PATH=%h/.crontab-ui
ExecStart=/usr/local/bin/crontab-ui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
```

Note: use systemd's `%h` (home directory) instead of `~` in the unit file —
`~` doesn't reliably expand there. Adjust `ExecStart=` if `which crontab-ui`
reports a different path on your system.

Enable and start it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now crontab-ui.service
```

Enable lingering so the service starts even without an active login session
(e.g. before logging into the desktop, or for headless/remote access):

```bash
sudo loginctl enable-linger $USER
```

Verify it's up:

```bash
curl -I http://localhost:8000
```

**Manage the service:**

```bash
systemctl --user status crontab-ui.service     # check status
systemctl --user restart crontab-ui.service    # restart manually
systemctl --user stop crontab-ui.service       # stop
journalctl --user -u crontab-ui.service -f     # live logs
```

With this in place, the desktop launcher below just opens a window pointed
at the already-running service — it no longer needs to start the process
itself.

## Desktop launcher

`crontab-ui.desktop` opens Chrome in app mode (`--app=http://localhost:8000`)
pointed at the running instance — no address bar, tabs, or menus, just the
page in its own window.

Install it:

```bash
cp crontab-ui.desktop ~/.local/share/applications/
```

Then update the desktop database so it shows up in the app launcher
immediately:

```bash
update-desktop-database ~/.local/share/applications/
```

If `crontab-ui`'s port ever changes (set via `PORT` env var or
`~/.crontab-ui/config.json`), update the `Exec=` line's URL accordingly.

## Icon

`crontab-ui-icon.svg` is the source icon — green-on-black terminal style
(rounded dark square, faint scanlines, glowing circle with an hourglass
glyph, title + subtitle), matching the other utility icons (`linux-sync`,
`grok-sync`, `gpu-mode`).

Rebuild the PNG and install it with:

```bash
rsvg-convert -w 256 -h 256 crontab-ui-icon.svg -o crontab-ui.png
cp crontab-ui.png ~/.local/share/icons/crontab-ui.png
gtk-update-icon-cache ~/.local/share/icons/
```

## Files

| File | Purpose |
|------|---------|
| `crontab-ui.desktop` | App-mode launcher entry, installed to `~/.local/share/applications/` |
| `crontab-ui-icon.svg` | Source icon (edit this, not the PNG) |
| `crontab-ui-preview.png` | Rendered 256x256 icon, installed to `~/.local/share/icons/crontab-ui.png` |
