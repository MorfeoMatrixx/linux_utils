Using Linux distros, mainly Pop_OS or other Debian/Ubuntu based, on Lenovo LOQ laptop with nvidia GPU as the default dev platform and workstation.

Also RPi OS and KDE/Plasma on RPi hardware when related to Home Assistant platform.

Work on desining and coding Python and CLI apps and utilities on Intel (x86) linux platforms.

Network infra with multiplatform resource sharing, NAS, uPNP, media centers, remote access, etc.

## Conventions for simple bash/python CLI/TUI utilities

Distilled from building `backup2nas/dir-backup.sh` and `sd-backup.sh`. Apply these to future single-file interactive utilities of similar scope (not full applications).

### Project layout
- Source of truth lives in a repo subdirectory under `~/claude/utils/<name>/` (e.g. `backup2nas/`).
- The installed, runnable copy lives in `~/bin/<script>.sh` (plain user scripts) or `~/.local/bin/` (system/hardware wrappers) - see script-bin-location convention in memory.
- After every edit, copy the repo source back to the installed bin location and `chmod +x` it - don't edit the installed copy directly.
- Any sidecar file the script depends on at runtime (e.g. a `.dialogrc`) gets copied to `~/bin/` alongside the script, and the script resolves it relative to its own location via `SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` (use `${BASH_SOURCE[0]}`, not `$0`, so it still works if ever sourced).

### Script basics
- `set -euo pipefail` at the top of every bash script.
- Quick-and-dirty over production quality: no error handling for scenarios that can't happen, no speculative abstraction, no backwards-compat shims.

### TUI: `whiptail` vs `dialog`
- `whiptail` ships by default on Debian/Ubuntu (no install needed) and is perfectly fine for the common case: menus, yes/no confirmations, simple text prompts, progress gauges. Keep using it for utilities that don't need path entry, file/directory browsing, or per-substring text coloring - it's the lighter dependency and there's no reason to drag in `dialog` just for its own sake.
- Reach for `dialog` specifically when a script needs one of the things `whiptail` can't do: `--fselect`/`--dselect` (file/directory browsers), or `--colors` (per-substring text attributes via embedded `\Z` codes). Also relevant: `whiptail --inputbox` has no readline integration, so free-text path entry gets no tab-completion in either tool - if tab-completion specifically (not just browsing) is the goal, a plain `read -e` prompt outside the TUI is the only way to get real shell completion; neither `whiptail` nor `dialog` can do it inside a widget. `dialog` needs `sudo apt install dialog` (ask first - it's a system package install).
- For picking a directory when using `dialog`, don't rely on `--dselect` (focus starts in its text field, not the list, and Enter-to-submit can silently accept the untouched default before the user navigates anywhere). Build a small custom browser instead: a `--menu` loop over `find -mindepth 1 -maxdepth 1 -type d`, with `.` = "[Select this directory]" and `..` = "[Up one level]" as menu entries. A `--menu`'s focus is inherently the list, so this sidesteps the whole problem. (This construct works identically in `whiptail`, which also has `--menu`, if `dialog`'s extra features aren't otherwise needed.)

### The `dg()` wrapper and the subshell/`exit` trap
Every script needs one wrapper function to run a dialog widget, capture its answer, and know which button was pressed:
```bash
dg() {
    local rc
    dialog "$@" 3>&1 1>&2 2>&3
    rc=$?
    clear >/dev/tty
    return $rc
}
```
- **Never call `exit` inside a function that might run as `VAR=$(fn ...)`.** Command substitution runs the function in a subshell; `exit` there only kills the subshell, and anything the function echoed before that (e.g. an "Aborted." message) gets captured into `VAR` instead of being displayed - corrupting the next comparison/use of that variable. Always `return $rc` and let the caller, sitting outside any subshell, check `$?` (or use `VAR=$(fn ...) || { echo "Aborted."; exit 0; }`) and `exit` from there.
- `clear` must go to `/dev/tty` explicitly (`clear >/dev/tty`), never to plain stdout, inside anything that might be captured via `$(...)` - otherwise `clear`'s escape codes leak into the captured string as literal garbage text.
- For multi-step flows where the user should be able to go back (not just cancel), use `dialog --extra-button --extra-label "Back"` on the relevant widgets (exit code `3`, distinct from OK=`0`/Cancel=`1`/Esc=`255`), and drive the whole flow as a `STEP` state machine (`while true; do case $STEP in 1) ...;; 2) ...;; esac; done`) since bash has no `goto`. Each step should default its prompt to whatever was chosen last time, so backing up doesn't discard prior input.

### Progress bars with `pv`
- Don't feed `pv -n`'s percentage output into a gauge via `2> >(dialog --gauge ...)` (process substitution) - it's unreliable for curses apps needing real terminal access and can silently draw nothing. Use a plain subshell group instead: `(producer | pv -f -s "$SIZE" -n | consumer) 2>&1 | dialog --gauge "..." height width 0`. Append `|| true` after it since `set -e`/`pipefail` will otherwise abort the script on any hiccup in that pipeline.
- Know the limitation before promising a "natural" bar: `dialog --gauge`'s completed segment is hardcoded to strip the reverse-video attribute while the *remaining* segment keeps it - so with a bold+reverse `gauge_color`, the bar reads bright-shrinking-to-dim as it completes, not the other way round. This isn't configurable via `dialogrc`. If a true bright-growing bar is required, it has to be hand-built with `dialog --colors` and `\Z` escape codes (`\Zb`/`\ZB` bold on/off, `\Z0`-`\Z7` color, `\Zn` reset - cumulative until reset), redrawn via repeated `dialog --colors --infobox "..."` calls as each new percentage arrives - more code, and a visibly different (per-tick redraw, not continuously live) feel. Confirm which tradeoff is wanted before building it.

### `dialogrc` theming
- Colors are set via `export DIALOGRC=/path/to/file` before any `dialog` call; generate a starting template with `dialog --create-rc <file>` and edit the color lines.
- Attribute syntax is `(foreground,background,highlight?,underline?,reverse?)` - 5 fields, last three optional booleans. Most examples online only show 3 fields (fg,bg,highlight) and omit that a 5th `reverse` field exists.
- **`highlight` (bold) only intensifies the foreground slot, never the background** - curses has no "bright background" concept from this flag alone. So `(BLACK,GREEN,ON)` for a "selected item" pair boosts black (invisible) and leaves the green background at standard intensity - it looks dim, not bright. To get a genuinely bright reversed block: put the color that should be bright as the *foreground* (`fg=GREEN`), set `highlight=ON` (bold boosts it), and add `reverse=ON` as a 5th field to swap fg/bg at render time - e.g. `(GREEN,BLACK,ON,OFF,ON)`. This renders as a bright green fill with black text, which plain `(BLACK,GREEN,ON)` does not achieve.
- A terminal's ANSI "black" is a palette slot, not necessarily `#000000` - Tilix (and most terminal color schemes) remaps it to a dark grey by default. If a background looks "dark grey instead of pure black," that's the terminal profile's palette, not something `dialogrc` controls.

### Verifying TUI behavior without a live terminal
When a `dialog`/`whiptail` widget's exact rendering matters and there's no interactive terminal available to eyeball it, capture the raw bytes instead of guessing:
```python
import pty, os, time, select
pid, fd = pty.fork()
if pid == 0:
    os.execvpe('dialog', ['dialog', ...], env)
else:
    os.write(fd, b'50\n')   # simulate stdin input, e.g. a gauge percentage
    time.sleep(1.0)
    # select.select([fd], [], [], 0.3) in a loop, os.read(fd, 65536), accumulate
```
Then inspect the captured bytes for the SGR escape sequences (`\x1b[...m`) surrounding the text of interest to see exactly which color pair/attributes were actually applied where - this caught two real bugs in this session (a test string that didn't match what the script actually generated, and confirming dialog's gauge fill/remaining color split) that would otherwise have taken several more rounds of "run it and see."
