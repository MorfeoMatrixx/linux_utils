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
- Launchers (`<name>.desktop` + `<name>-launch.sh` + icon): the `.desktop` always sets `StartupNotify=true`. Without it KWin's focus-stealing prevention opens the terminal *behind* a fullscreen app (Plasma X11 + Tilix); the launch script just `exec`s the terminal so the startup-notification environment passes through. Install copies to `~/.local/share/applications/` and `~/.local/share/icons/`, then `update-desktop-database`. New utilities with a launcher also go into `pop-os-post-install/pop-os-post-install-customizations.sh` (+ its `.md`).
- Any sidecar file the script depends on at runtime (e.g. a `.dialogrc`) gets copied to `~/bin/` alongside the script, and the script resolves it relative to its own location via `SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` (use `${BASH_SOURCE[0]}`, not `$0`, so it still works if ever sourced).

### Script basics
- `set -euo pipefail` at the top of every bash script.
- Quick-and-dirty over production quality: no error handling for scenarios that can't happen, no speculative abstraction, no backwards-compat shims.

### TUI: `whiptail` vs `dialog`
- `whiptail` ships by default on Debian/Ubuntu (no install needed) and is perfectly fine for the common case: menus, yes/no confirmations, simple text prompts, progress gauges. Keep using it for utilities that don't need path entry, file/directory browsing, or per-substring text coloring - it's the lighter dependency and there's no reason to drag in `dialog` just for its own sake.
- Reach for `dialog` specifically when a script needs one of the things `whiptail` can't do: `--fselect`/`--dselect` (file/directory browsers), or `--colors` (per-substring text attributes via embedded `\Z` codes). Also relevant: `whiptail --inputbox` has no readline integration, so free-text path entry gets no tab-completion in either tool - if tab-completion specifically (not just browsing) is the goal, a plain `read -e` prompt outside the TUI is the only way to get real shell completion; neither `whiptail` nor `dialog` can do it inside a widget. `dialog` needs `sudo apt install dialog` (ask first - it's a system package install).
- For picking a directory when using `dialog`, don't rely on `--dselect` (focus starts in its text field, not the list, and Enter-to-submit can silently accept the untouched default before the user navigates anywhere). Build a small custom browser instead: a `--menu` loop over `find -mindepth 1 -maxdepth 1 -type d`, with `.` = "[Select this directory]" and `..` = "[Up one level]" as menu entries. A `--menu`'s focus is inherently the list, so this sidesteps the whole problem. (This construct works identically in `whiptail`, which also has `--menu`, if `dialog`'s extra features aren't otherwise needed.)

### Plain ANSI report vs. `dialog`/`whiptail` TUI

Distilled from building `linux-nodes-status/linux-nodes-status.sh`. Before reaching for `dialog`/`whiptail` at all, decide whether the utility is actually an *interactive dialog* (menus, confirmations, multi-step wizards - the previous section) or a *one-shot report* (a status table, a summary dump, anything meant to be run, read, and exited). These want opposite rendering strategies.

**Use plain ANSI (hand-drawn box-drawing), not a curses widget, when the output is a one-shot report** - e.g. a fleet/status table you'd want to pipe, redirect to a log, `grep`, diff between runs, or run from cron.

- A curses widget (`dialog`/`whiptail`) forces the output through an interactive full-screen frame that can't be piped, redirected, or scrolled back through normal terminal scrollback - wrong shape for a report, and it adds a dependency (`dialog`) for zero benefit over plain text here.
- Curses apps are exactly the class of program that can leave a terminal's mouse-tracking/raw mode stuck on if killed or interrupted mid-render (see the parallel-SSH-background-jobs bug fixed in `linux-nodes-status.sh` - background jobs sharing the controlling tty's stdin left it in a state where mouse clicks/scroll emitted raw escape codes into the shell). Plain `printf`-based output never touches terminal modes, so this whole bug class doesn't exist for it.
- Plain ANSI box-drawing (`┌─┬─┐│├─┼─┤└─┴─┘`) gets you the same "Midnight Commander" look - including an offset drop-shadow using dim `▒` blocks - while staying pipeable, adding no curses state, and needing no new dependency. It still uses the same green-on-default vintage-phosphor palette as the `dialog`-based utilities (`tput setaf 2`/`tput bold`/`tput dim`/`tput sgr0` instead of a `.dialogrc`), so the whole fleet of utilities in this repo still *looks* like one family even though only some of them are built on `dialog`.

**Box-drawing + shadow recipe** (see `linux-nodes-status.sh` for the full implementation):
- Build a `hborder(left, mid, right)` helper that draws a horizontal rule from a per-column width array, without a trailing newline - the caller decides whether that row gets a shadow appended or a plain newline, so top border (no shadow) and every other border/content row (shadow) share one function.
- The shadow is a fixed-width strip of `▒` in `tput dim` immediately after the right border, applied to *every* row except the very top border (a real drop shadow starts one row below the top-left corner) - plus one extra shadow-only line, indented past the box's left edge, after the bottom border. Getting the shadow to look continuous instead of gappy/offset-by-one requires the border-drawing function and the shadow-appending call to share the same line (no premature newline in between) - this was the actual bug the first pass had.
- Reserve `dim` for exactly two things: the shadow, and rows/cells representing degraded or unavailable data (e.g. an unreachable host). Normal data stays plain/bold foreground so dim reads as a meaningful signal ("this is background/inactive") rather than decoration.
- **`tput dim`/`tput bold` are additive, not exclusive - always `tput sgr0` (full reset) before switching between them, not just before the first one.** SGR attributes accumulate in most terminals until an explicit reset: if a shadow line leaves `dim` active and the next border section then adds `bold` on top *without resetting first*, the terminal ends up rendering bold+dim simultaneously - which most terminals show as dim-dominant, not bright. This bit `linux-nodes-status.sh`'s header separator and bottom border (both immediately follow a dim shadow line): they looked dim instead of bright until every `$GREEN$BOLD` border section was changed to `$RESET$GREEN$BOLD`. Rule of thumb: any time a line's styling differs from the line before it, reset first, then apply the new attributes - never assume the previous line's `sgr0`/color codes fully expired on their own.

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

### `set -e` and the Back button (bug found in `dir-backup.sh`, fixed there and in `dir-sync.sh`)
- `X=$(dg ...); rc=$?` and a bare `dialog ...; rc=$?` **kill the whole script when the widget returns non-zero** (Back = 3, Cancel = 1), because `set -e` fires before `rc` is read. Symptom: Back drops you out to the shell/launcher instead of the previous screen. Always go through a helper: `ask() { RC=0; ANS=$(dg "$@") || RC=$?; }` (and `rc=0; dialog ... || rc=$?` inside `dg()` itself). `||` suspends `set -e` for everything on its left.
- A `STEP` state machine must only route Back to steps that actually show a screen: a step that is skipped for some inputs (e.g. the filename prompt with several sources) makes Back bounce straight forward again. Remember the browse location (`SRC_BROWSE`) so Back reopens the picker where the user was.
- Test Back flows by driving the real TUI in a pty and sending Tab/Enter; for `--menu`/`--checklist` one Tab reaches the extra (Back) button, for `--inputbox` two. Arrow keys must be sent as `\x1bOB` (application mode), not `\x1b[B`.

### rsync-based sync utilities (`backup2nas/dir-sync.sh`)
- NAS is SMB only: for cifs/smb3/ntfs/fat/exfat destinations use `-rt --no-perms --no-owner --no-group --modify-window=2` (plain `-a` errors on perms/owners and re-copies everything because of 2 s mtime rounding); otherwise `-a`. Detect with `findmnt -no FSTYPE -T <dest>`.
- Always `rsync src/ dest/<name>/` with explicit slashes; fixed destination folder name (no timestamp) so re-runs are incremental. Dry run (`--dry-run --itemize-changes --stats`) before the confirm screen, with a Details button (`--help-button`, rc 2) showing the list.
- Mirror modes (`--delete`) must say loudly what will be deleted, using the dry-run count. "Trash" for deleted files only (not overwritten ones) = a first pass with `--existing --ignore-existing --delete --backup --backup-dir=<dest>/.deleted/<ts>` (transfers nothing, only moves delete victims), then the normal pass; `--exclude=/.deleted` keeps `--delete` from wiping earlier trash.
- Progress over slow SMB: rsync is silent until its file lists are built (`--no-inc-recursive` makes this a full scan on both sides), so one `dialog --gauge` is fed with the `XXX` protocol (`XXX\n<pct>\n<one-line text with literal \n>\nXXX`): a background ticker shows "scanning... Elapsed mm:ss" until the first `--info=progress2,name1` line arrives (awk touches a flag file), then current file, size, rate and ETA. Background jobs and rsync get `</dev/null`; results from the pipeline subshell come back via files (rsync's exit status, stats logs), not variables.

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
