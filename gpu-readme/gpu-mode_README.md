# gpu-mode

A terminal control panel (curses TUI) for switching GPU graphics mode and CPU
power profile on Lenovo LOQ laptops running Pop!_OS, via `system76-power`.

## Purpose

`system76-power` exposes graphics-mode and CPU-profile switching only through
shell commands (`system76-power graphics <mode>`, `system76-power profile
<profile>`), each requiring `sudo`. `gpu-mode` wraps those commands in a
green-on-black, keyboard-driven panel so switching modes doesn't require
remembering command syntax or typing a password each time.

## Usage

### Install

```bash
./gpu-mode-install.sh
```

This:
1. Copies `gpu-mode.py` to `~/.local/bin/gpu-mode` and makes it executable.
2. Warns if `~/.local/bin` isn't on `PATH`.
3. Writes a passwordless sudo rule for `system76-power` to
   `/etc/sudoers.d/system76-power-nopasswd` (`%sudo ALL=(ALL) NOPASSWD:
   /usr/bin/system76-power`), so the TUI can switch modes without prompting
   for a password on every action.

Optionally, install the app icon and a COSMIC desktop launcher entry:

```bash
cd gpu-mode-icons
./gpu-mode-icon-install.sh
```

This installs PNG icons under `~/.local/share/icons/hicolor/<size>/apps/`,
a canonical copy at `~/.local/share/icons/gpu-mode.png`, and a `.desktop`
file at `~/.local/share/applications/gpu-mode.desktop` so "GPU Mode" shows
up in the application menu.

### Run

```bash
gpu-mode
```

Requires a terminal at least 40x16 characters.

**Keys:**

| Key       | Action                                  |
|-----------|------------------------------------------|
| `↑` / `↓` | Move selection within the current tab    |
| `Enter`   | Apply the selected mode/profile           |
| `G`       | Switch to the Graphics tab                |
| `P`       | Switch to the Power tab                   |
| `Tab`     | Toggle between tabs                       |
| `R`       | Re-query current state from the system    |
| `Q` / `Esc` | Quit                                    |

**Graphics modes** (each requires a reboot to take effect):
- `INTEGRATED` — NVIDIA fully off, CPU graphics only, max battery
- `HYBRID` — default; NVIDIA sleeps at 0W, wakes on demand
- `NVIDIA` — NVIDIA full-time, max performance, shortest battery
- `COMPUTE` — CPU renders the desktop; NVIDIA stays awake for AI/compute jobs

**CPU power profiles** (apply instantly, no reboot):
- `BATTERY` — throttled, max powersaving
- `BALANCED` — default, scales with load
- `PERFORMANCE` — max clocks/turbo, more heat

## How it works

`gpu-mode.py` is a single-file Python `curses` application (`GPUMode` class):

- **State model**: `GRAPHICS_MODES` and `POWER_PROFILES` are static lists of
  dicts (id, label, short/long description, whether a reboot is required).
  These drive both the selectable list and the description panel — there's
  no separate config file.
- **Talking to `system76-power`**: all interaction goes through
  `run_cmd()`, a thin `subprocess.run` wrapper.
  - Read-only queries (`system76-power graphics` / `profile`) run with an
    8s timeout and no `sudo`.
  - Mode switches run with `sudo -n` (non-interactive — relies on the
    passwordless sudoers rule from install) and a 30s timeout, since
    switching graphics modes can reload kernel modules and take a while.
  - `_extract_value()` parses the `"Graphics mode: hybrid"` / `"Profile:
    balanced"` style output down to just the lowercase value.
- **Layout**: a fixed 40x16 panel is centered in the terminal
  (`_layout()`), redrawn on every loop tick and on `KEY_RESIZE`. The panel
  is split into a header (title + live `GPU:<mode> CPU:<profile>` state
  badge), a tab bar, a two-column body (mode list on the left, description
  + reboot/instant badge on the right), a status line, and a help line.
  Box-drawing is done by hand with Unicode double-line characters
  (`dbl_frame`, `dbl_hline`, `inner_vline`).
- **Colors**: defined once in `_setup_colors()` using only the 8 standard
  ANSI colors (avoids `curses.init_color()`, which Pop!_OS's default VTE
  terminal doesn't honor reliably).
- **Main loop** (`run()`): blocks on `getch()` with a 1s timeout (so status
  messages can expire), dispatches arrow keys to move the cursor, `G`/`P`/
  `Tab` to switch tabs, `R` to re-query system state, and `Enter` to call
  `apply_current()`, which invokes `set_graphics()`/`set_profile()`,
  updates in-memory state on success, and sets a status message (shown for
  8s) reporting success/failure and whether a reboot is needed.

## Files

| File | Purpose |
|------|---------|
| `gpu-mode.py` | The TUI application itself |
| `gpu-mode-install.sh` | Installs the binary + passwordless sudoers rule |
| `gpu-mode-icons/gpu-mode-icon-install.sh` | Installs app icons + `.desktop` launcher entry |
| `gpu-mode-icons/gpu-mode-icon-*.png` | Icon assets at standard sizes (16–512px) |
