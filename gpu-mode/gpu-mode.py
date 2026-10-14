#!/usr/bin/env python3
"""
gpu-mode — system76-power TUI for Lenovo LOQ on Pop!_OS
Green-on-black terminal control panel for GPU mode & CPU profile switching.
"""

import curses
import os
import shlex
import shutil
import subprocess
import sys
import time
import textwrap

# ─── palette constants (curses color pair ids) ────────────────────────────────
P_NORMAL    = 1   # bright green on black            — frame, chrome, body text
P_DIM       = 2   # dim green on black                — secondary text
P_SELECTED  = 3   # black on bright yellow, bold      — cursor row (inverse yellow)
P_ACTIVE    = 4   # bright green on black, bold       — generic "good" emphasis
P_WARN      = 5   # amber on black                    — reboot warning
P_BORDER    = 6   # mid green on black                — box-drawing lines
P_HEADER    = 7   # bright green on black             — titles
P_ERR       = 8   # red on black                      — error messages
P_ACCENT    = 9   # magenta on black, bold            — ACTIVE mode (system state)
P_MODE      = 10  # white on black                    — available (non-active, non-selected) modes
P_HELP      = 11  # white on black                    — bottom key-hint line
P_PENDING   = 12  # red on black                      — pending-reboot mode

# ─── fixed panel dimensions (do not stretch to fill terminal) ─────────────────
PANEL_W = 40
PANEL_H = 16

# ─── data model ───────────────────────────────────────────────────────────────
GRAPHICS_MODES = [
    {
        "id":    "integrated",
        "label": "INTEGRATED",
        "short": "CPU only  — NVIDIA fully off",
        "desc": (
            "NVIDIA GPU fully off. CPU graphics only. Max battery life."
        ),
        "reboot": True,
    },
    {
        "id":    "hybrid",
        "label": "HYBRID",
        "short": "Default   — NVIDIA sleeps until needed",
        "desc": (
            "Default mode. NVIDIA sleeps at 0W, wakes on demand or HDMI."
        ),
        "reboot": True,
    },
    {
        "id":    "nvidia",
        "label": "NVIDIA",
        "short": "NVIDIA only — max performance, max draw",
        "desc": (
            "NVIDIA only, full time. Max performance, shortest battery."
        ),
        "reboot": True,
    },
    {
        "id":    "compute",
        "label": "COMPUTE",
        "short": "AI/ML     — NVIDIA awake for compute only",
        "desc": (
            "CPU renders desktop. NVIDIA stays awake for AI/compute jobs."
        ),
        "reboot": True,
    },
]

POWER_PROFILES = [
    {
        "id":    "battery",
        "label": "BATTERY",
        "short": "Low power — max battery life",
        "desc": (
            "Throttles CPU boost. Max powersaving for longest battery life."
        ),
        "reboot": False,
    },
    {
        "id":    "balanced",
        "label": "BALANCED",
        "short": "Default   — scales with system load",
        "desc": (
            "Default. Scales CPU with load: low when idle, high when busy."
        ),
        "reboot": False,
    },
    {
        "id":    "performance",
        "label": "PERFORMANCE",
        "short": "Unlocked  — max clocks, max turbo",
        "desc": (
            "Max CPU clocks and turbo. Lowest latency, more heat."
        ),
        "reboot": False,
    },
]

# ─── system76-power helpers ────────────────────────────────────────────────────

# Query commands (no args, e.g. `system76-power graphics`) return almost
# instantly. Mode-switch commands (e.g. `system76-power graphics nvidia`)
# can take ~10s or more — they go through D-Bus and may reload kernel
# modules — so they get a much longer timeout.
QUERY_TIMEOUT  = 8
SWITCH_TIMEOUT = 30

def run_cmd(args, sudo=False, timeout=QUERY_TIMEOUT):
    """Run a command, return (stdout, stderr, returncode)."""
    if sudo:
        args = ["sudo", "-n"] + args   # -n = non-interactive (no password prompt)
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip(), r.stderr.strip(), r.returncode
    except FileNotFoundError:
        return "", f"Command not found: {args[0]}", 1
    except subprocess.TimeoutExpired:
        return "", f"Command timed out after {timeout}s", 1

def _extract_value(out, prefixes):
    """system76-power profile output looks like:

        Power Profile: Balanced
        Backlight
          gmux_backlight: 35048/82311 = 42%
        Keyboard Backlight
          smc::kbd_backlight: 0/255 = 0%

    The value we want is on the FIRST matching line (one of `prefixes`),
    never the last line — trailing lines are unrelated backlight/extra
    info and must not be parsed as the profile value.
    """
    if not out:
        return None
    for line in out.strip().splitlines():
        line = line.strip()
        lower = line.lower()
        for prefix in prefixes:
            if lower.startswith(prefix):
                value = line.split(":", 1)[1] if ":" in line else ""
                value = value.strip().lower()
                if value:
                    return value
    return None

def get_current_graphics():
    # Per system76-power's own source (src/client.rs), `system76-power
    # graphics` with no arguments prints ONLY the bare mode name on its
    # own line — e.g. just "hybrid" — with no "Graphics mode:" label at
    # all. So just take the first non-empty line verbatim.
    out, err, rc = run_cmd(["system76-power", "graphics"], timeout=QUERY_TIMEOUT)
    if rc == 0 and out:
        first_line = out.strip().splitlines()[0].strip().lower()
        return first_line or None
    return None

def get_current_profile():
    out, err, rc = run_cmd(["system76-power", "profile"], timeout=QUERY_TIMEOUT)
    if rc == 0 and out:
        return _extract_value(out, ("power profile", "profile"))
    return None

def set_graphics(mode):
    out, err, rc = run_cmd(["system76-power", "graphics", mode],
                            sudo=True, timeout=SWITCH_TIMEOUT)
    return rc == 0, out or err

def set_profile(profile):
    out, err, rc = run_cmd(["system76-power", "profile", profile],
                            sudo=True, timeout=SWITCH_TIMEOUT)
    return rc == 0, out or err

# ─── drawing helpers ───────────────────────────────────────────────────────────

def addstr_clipped(win, y, x, text, attr=0):
    """Write text clipped to window width. Never raises curses.error."""
    h, w = win.getmaxyx()
    if y < 0 or y >= h or x < 0 or x >= w:
        return
    max_len = max(0, w - x - 1)   # leave last column untouched (avoids ERR on bottom-right cell)
    if max_len <= 0:
        return
    try:
        win.addstr(y, x, text[:max_len], attr)
    except curses.error:
        pass

# Double-line box-drawing characters (Unicode)
DBL_H  = "═"
DBL_V  = "║"
DBL_TL = "╔"
DBL_TR = "╗"
DBL_BL = "╚"
DBL_BR = "╝"
DBL_LT = "╠"   # left T  (├ double)
DBL_RT = "╣"   # right T (┤ double)
DBL_TT = "╦"   # top T
DBL_BT = "╩"   # bottom T
DBL_CR = "╬"   # cross
SGL_V  = "│"   # single vertical (inner divider)
SGL_LT = "╞"   # single-horiz / double-vert left junction
SGL_RT = "╡"   # single-horiz / double-vert right junction

def _ch(win, y, x, ch, attr):
    """Write a single Unicode box-drawing character safely."""
    try:
        win.addstr(y, x, ch, attr)
    except curses.error:
        pass

def dbl_hline(win, y, x, w, pair, left=None, right=None):
    """Draw a full-width double horizontal rule with optional T-junction caps."""
    attr = curses.color_pair(pair)
    _ch(win, y, x,       left  or DBL_LT, attr)
    _ch(win, y, x + w-1, right or DBL_RT, attr)
    try:
        win.addstr(y, x+1, DBL_H * (w - 2), attr)
    except curses.error:
        pass

def dbl_hline_inner(win, y, x, w, pair):
    """Draw a plain double rule (no caps) — for sub-panel dividers."""
    attr = curses.color_pair(pair)
    try:
        win.addstr(y, x, DBL_H * w, attr)
    except curses.error:
        pass

def dbl_frame(win, y, x, h, w, pair):
    """Draw a full double-line rectangle."""
    attr = curses.color_pair(pair)
    _ch(win, y,     x,     DBL_TL, attr)
    _ch(win, y,     x+w-1, DBL_TR, attr)
    _ch(win, y+h-1, x,     DBL_BL, attr)
    _ch(win, y+h-1, x+w-1, DBL_BR, attr)
    try:
        win.addstr(y,     x+1, DBL_H * (w-2), attr)
        win.addstr(y+h-1, x+1, DBL_H * (w-2), attr)
    except curses.error:
        pass
    for i in range(1, h-1):
        _ch(win, y+i, x,     DBL_V, attr)
        _ch(win, y+i, x+w-1, DBL_V, attr)

def inner_vline(win, top, bottom, x, pair, top_t=None, bot_t=None):
    """Draw a single vertical divider with T-junction connectors."""
    attr = curses.color_pair(pair)
    _ch(win, top,    x, top_t or "╥", attr)
    _ch(win, bottom, x, bot_t or "╨", attr)
    for row in range(top+1, bottom):
        _ch(win, row, x, SGL_V, attr)

# ─── main TUI class ────────────────────────────────────────────────────────────

class GPUMode:
    TAB_GRAPHICS = 0
    TAB_PROFILE  = 1

    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.scr        = None      # the fixed 40x16 panel window (created in _layout)
        self.tab        = self.TAB_GRAPHICS
        self.g_cursor   = 0
        self.p_cursor   = 0
        self.status_msg = ""
        self.status_ok  = True
        self.status_ts  = 0
        self.cur_graphics     = None   # what is CURRENTLY RUNNING (from re-query)
        self.pending_graphics = None   # what was requested but needs a reboot
        self.cur_profile      = None
        self._setup_colors()
        self._refresh_state()
        self._layout()

    def _layout(self):
        """(Re)create the fixed-size panel window, centered on the terminal."""
        H, W = self.stdscr.getmaxyx()
        y0 = max(0, (H - PANEL_H) // 2)
        x0 = max(0, (W - PANEL_W) // 2)
        # Clamp in case terminal is smaller than the panel
        h = min(PANEL_H, H)
        w = min(PANEL_W, W)
        self.scr = curses.newwin(h, w, y0, x0)
        self.scr.keypad(True)
        # Clear the full terminal ONLY here — at startup and on resize —
        # so any stale content outside the panel's new position is wiped.
        # Doing this on every draw() call (instead of just here) was the
        # cause of the visible flicker, since it blanks then redraws the
        # whole screen on every refresh tick.
        self.stdscr.erase()
        self.stdscr.refresh()

    def _setup_colors(self):
        """
        ╔══════════════════════════════════════════════════════════════════╗
        ║  COLOR TABLE — edit the right-hand side to change a color.        ║
        ║  Each row: PAIR NAME = (foreground, background, bold?)            ║
        ║  Use ONLY curses.COLOR_BLACK/RED/GREEN/YELLOW/BLUE/MAGENTA/        ║
        ║  CYAN/WHITE here. These are the 8 standard ANSI colors every      ║
        ║  terminal renders correctly without any special setup.            ║
        ╚══════════════════════════════════════════════════════════════════╝

            PAIR          MEANS                       FG       BG      BOLD
            ------------- --------------------------- -------- ------- -----
            P_NORMAL      frame / body text           GREEN    BLACK   yes
            P_DIM         secondary / less-important  GREEN    BLACK   no
            P_SELECTED    cursor row (inverse)         BLACK    YELLOW  no
            P_ACTIVE      "instant" badge, ready text  GREEN    BLACK   yes
            P_WARN        "reboot required" badge      YELLOW   BLACK   yes
            P_BORDER      box-drawing lines            GREEN    BLACK   no
            P_HEADER      title text                  GREEN    BLACK   yes
            P_ERR         error messages               RED      BLACK   yes
            P_ACCENT      ACTIVE mode highlight        MAGENTA  BLACK   yes
            P_MODE        available (non-active) modes WHITE    BLACK   no
            P_HELP        bottom key-hint line         WHITE    BLACK   no

            NOTE 1: To change a color, just swap the curses.COLOR_* constant
            on the matching init_pair() line below — no other code needs
            to change.
            NOTE 2: Never combine curses.A_BOLD with COLOR_BLACK foreground
            — on most terminals "bold black" renders as grey, not black.
            NOTE 3: This deliberately avoids curses.init_color() — many
            terminals (including Pop!_OS's default VTE-based terminal)
            silently ignore custom palette redefinition, which causes
            "phosphor green" slots to fall back to the *default* color of
            that palette index (often an unrelated blue). Sticking to the
            8 standard ANSI colors below renders correctly everywhere.
        """
        curses.start_color()
        curses.use_default_colors()

        BLACK   = curses.COLOR_BLACK
        RED     = curses.COLOR_RED
        GREEN   = curses.COLOR_GREEN
        YELLOW  = curses.COLOR_YELLOW
        MAGENTA = curses.COLOR_MAGENTA
        WHITE   = curses.COLOR_WHITE

        curses.init_pair(P_NORMAL,   GREEN,   BLACK)
        curses.init_pair(P_DIM,      GREEN,   BLACK)
        curses.init_pair(P_SELECTED, BLACK,   YELLOW)   # black text on yellow — readable
        curses.init_pair(P_ACTIVE,   GREEN,   BLACK)
        curses.init_pair(P_WARN,     YELLOW,  BLACK)
        curses.init_pair(P_BORDER,   GREEN,   BLACK)
        curses.init_pair(P_HEADER,   GREEN,   BLACK)
        curses.init_pair(P_ERR,      RED,     BLACK)
        curses.init_pair(P_ACCENT,   MAGENTA, BLACK)
        curses.init_pair(P_MODE,     WHITE,      BLACK)
        curses.init_pair(P_HELP,     WHITE,      BLACK)
        curses.init_pair(P_PENDING,  RED,        BLACK)

    def _refresh_state(self):
        self.cur_graphics     = get_current_graphics()
        self.cur_profile      = get_current_profile()
        self.pending_graphics = None   # clear any pending-reboot state on refresh

    def set_status(self, msg, ok=True):
        self.status_msg = msg
        self.status_ok  = ok
        self.status_ts  = time.time()

    def draw(self):
        H, W = self.stdscr.getmaxyx()
        if H < PANEL_H or W < PANEL_W:
            self.stdscr.erase()
            try:
                self.stdscr.addstr(0, 0, f"Terminal too small — need at least {PANEL_W}x{PANEL_H}")
            except curses.error:
                pass
            self.stdscr.refresh()
            return

        win = self.scr
        win.erase()
        h, w = win.getmaxyx()

        # Outer double-line frame around the fixed panel
        dbl_frame(win, 0, 0, h, w, P_BORDER)

        self._draw_header(w)
        self._draw_tabs(w)

        if self.tab == self.TAB_GRAPHICS:
            self._draw_graphics_panel(h, w)
        else:
            self._draw_profile_panel(h, w)

        self._draw_status_bar(h, w)
        self._draw_help(h, w)

        # noutrefresh (no physical screen write yet) + a single doupdate()
        # batches the actual terminal write into one pass, avoiding the
        # visible blank-then-redraw flash that erase()+refresh() causes.
        win.noutrefresh()
        curses.doupdate()

    def _draw_header(self, w):
        # Row 1: title only
        title = "GPU-MODE"
        addstr_clipped(self.scr, 1, 2, "*", curses.color_pair(P_DIM))
        addstr_clipped(self.scr, 1, w - len(title) - 2, title,
                       curses.color_pair(P_HEADER) | curses.A_BOLD)

        # Row 2: live state badge.
        # GPU shows the currently RUNNING mode (magenta), plus pending
        # mode in red if a reboot-required switch has been requested.
        g = (self.cur_graphics or "?").upper()
        p = (self.cur_profile  or "?").upper()
        x = 2
        addstr_clipped(self.scr, 2, x, f"GPU:{g}",
                       curses.color_pair(P_ACCENT) | curses.A_BOLD)
        x += len(f"GPU:{g}")
        if self.pending_graphics:
            pg = self.pending_graphics.upper()
            pending_txt = f"->{pg}"
            addstr_clipped(self.scr, 2, x, pending_txt,
                           curses.color_pair(P_ERR) | curses.A_BOLD)
            x += len(pending_txt)
        addstr_clipped(self.scr, 2, x, f" CPU:{p}",
                       curses.color_pair(P_ACCENT) | curses.A_BOLD)

        dbl_hline(self.scr, 3, 0, w, P_BORDER)

    def _draw_tabs(self, w):
        tabs = [
            ("[G]GFX", self.TAB_GRAPHICS),
            ("[P]PWR", self.TAB_PROFILE),
        ]
        x = 2
        for label, idx in tabs:
            if idx == self.tab:
                attr = curses.color_pair(P_SELECTED)
            else:
                attr = curses.color_pair(P_DIM)
            addstr_clipped(self.scr, 4, x, f" {label} ", attr)
            x += len(label) + 3

        dbl_hline(self.scr, 5, 0, w, P_BORDER)

    def _draw_graphics_panel(self, h, w):
        items      = GRAPHICS_MODES
        cursor     = self.g_cursor
        current_id = self.cur_graphics

        self._draw_item_list(items, cursor, current_id, h, w)

    def _draw_profile_panel(self, h, w):
        items      = POWER_PROFILES
        cursor     = self.p_cursor
        current_id = self.cur_profile

        self._draw_item_list(items, cursor, current_id, h, w)

    def _draw_item_list(self, items, cursor, current_id, h, w):
        """Compact left-list / right-description split for the 40x16 panel.

        Fixed row map (h=16):
          0  ╔══frame top══╗
          1  title
          2  badge
          3  ╠══════╣
          4  tabs
          5  ╠══════╣
          6..9   item rows (left) / desc title+sub (right)      -> 4 rows
          10     ╠══════╣ (status sep) — divider ends right here, no blank row
          11     status text
          12     ╠══════╣ (help sep)
          13     help text
          14     (unused — kept for breathing room above bottom frame)
          15     ╚══frame bottom══╝
        """
        LIST_W   = 13             # left column width (inside frame) — fits "PERFORMANCE"
        DESC_X   = LIST_W + 3     # description column start
        DESC_W   = w - DESC_X - 1
        TOP      = 6              # first content row (mode list / desc title)
        DIV_BOT  = 9              # last content row (4 rows: 6,7,8,9 — no trailing blank)

        # ── left column: mode list (one row per item) ──────────────────────
        for i, item in enumerate(items):
            y = TOP + i
            if y > DIV_BOT:
                break
            is_sel = (i == cursor)
            is_cur = (item["id"] == current_id)

            if is_sel:
                try:
                    self.scr.addstr(y, 1, " " * LIST_W, curses.color_pair(P_SELECTED))
                except curses.error:
                    pass
                attr_label = curses.color_pair(P_SELECTED)
            elif is_cur:
                attr_label = curses.color_pair(P_ACCENT) | curses.A_BOLD
            elif item["id"] == self.pending_graphics:
                attr_label = curses.color_pair(P_PENDING) | curses.A_BOLD
            else:
                attr_label = curses.color_pair(P_MODE)

            marker = "►" if is_cur else " "
            label = item["label"][:LIST_W - 2]
            addstr_clipped(self.scr, y, 1, f"{marker}{label}", attr_label)

        # vertical divider between list and description — ends exactly at
        # the last content row, with its bottom T-junction merging directly
        # into the status separator line below (no blank row in between).
        inner_vline(self.scr, TOP - 1, DIV_BOT + 1, LIST_W + 1, P_BORDER,
                    top_t="╥", bot_t="╨")

        # ── right column: description ───────────────────────────────────────
        sel = items[cursor]
        is_cur_sel = (sel["id"] == current_id)

        label_attr = (curses.color_pair(P_ACCENT) | curses.A_BOLD) if is_cur_sel \
                     else (curses.color_pair(P_HEADER) | curses.A_BOLD)
        title_text = f"[{sel['label']}]"
        addstr_clipped(self.scr, TOP, DESC_X, title_text, label_attr)
        if is_cur_sel:
            tag_x = DESC_X + len(title_text) + 1
            addstr_clipped(self.scr, TOP, tag_x, "ACTIVE",
                           curses.color_pair(P_ACCENT) | curses.A_BOLD)

        # reboot/instant badge — right-aligned on the same row as the title
        if sel["reboot"]:
            badge = "!REBOOT"
            badge_attr = curses.color_pair(P_PENDING) | curses.A_BOLD
        else:
            badge = "OK INSTANT"
            badge_attr = curses.color_pair(P_ACTIVE) | curses.A_BOLD
        badge_x = w - 1 - len(badge)
        if badge_x > DESC_X + len(title_text) + (8 if is_cur_sel else 0):
            addstr_clipped(self.scr, TOP, badge_x, badge, badge_attr)

        # word-wrapped description fills the remaining rows down to DIV_BOT
        lines = textwrap.wrap(sel["desc"], width=DESC_W)
        first_desc_row = TOP + 1
        max_lines = DIV_BOT - first_desc_row + 1
        for i, line in enumerate(lines[:max_lines]):
            addstr_clipped(self.scr, first_desc_row + i, DESC_X, line,
                           curses.color_pair(P_NORMAL))

    def _draw_status_bar(self, h, w):
        dbl_hline(self.scr, h - 5, 0, w, P_BORDER)   # row 11
        msg = self.status_msg
        age = time.time() - self.status_ts
        if msg and age < 8:
            attr = curses.color_pair(P_ACTIVE) | curses.A_BOLD if self.status_ok \
                   else curses.color_pair(P_ERR) | curses.A_BOLD
            addstr_clipped(self.scr, h - 4, 2, msg, attr)   # row 12
        else:
            addstr_clipped(self.scr, h - 4, 2, "Ready.", curses.color_pair(P_DIM))

    def _draw_help(self, h, w):
        dbl_hline(self.scr, h - 3, 0, w, P_BORDER)   # row 13
        keys = "↑↓ ENTER G P R Q"
        addstr_clipped(self.scr, h - 2, 2, keys, curses.color_pair(P_HELP))

    # ── input handling ─────────────────────────────────────────────────────────

    def apply_current(self):
        if self.tab == self.TAB_GRAPHICS:
            mode  = GRAPHICS_MODES[self.g_cursor]["id"]
            label = GRAPHICS_MODES[self.g_cursor]["label"]
            reboot= GRAPHICS_MODES[self.g_cursor]["reboot"]
            if mode == self.cur_graphics:
                self.set_status(f"{label} is already active.", ok=True)
                return
            self.set_status(f"Switching to {label}... (up to {SWITCH_TIMEOUT}s)", ok=True)
            self.draw()
            ok, msg = set_graphics(mode)
            if ok:
                # Graphics changes need a reboot — the running mode hasn't
                # changed yet. Track the requested mode as "pending" and
                # display it in red. Do NOT re-query: the daemon may be in
                # a transient state and return a misleading mode name.
                self.pending_graphics = mode
                self.set_status(f"Set to {label}. REBOOT to apply.", ok=True)
            else:
                # Re-query only on failure to get accurate current state
                self.cur_graphics = get_current_graphics()
                self.set_status(f"Error: {msg}", ok=False)
        else:
            prof  = POWER_PROFILES[self.p_cursor]["id"]
            label = POWER_PROFILES[self.p_cursor]["label"]
            if prof == self.cur_profile:
                self.set_status(f"{label} is already active.", ok=True)
                return
            self.set_status(f"Switching to {label}...", ok=True)
            self.draw()
            ok, msg = set_profile(prof)
            # Profile changes take effect immediately — re-query is safe
            # and handles the transient D-Bus error case correctly.
            self.cur_profile = get_current_profile()
            if self.cur_profile == prof:
                self.set_status(f"Profile set to {label}. Active immediately.", ok=True)
            elif ok:
                self.set_status(f"Profile set to {label}.", ok=True)
            else:
                self.set_status(f"Error: {msg}", ok=False)

    def run(self):
        curses.curs_set(0)
        self.stdscr.timeout(1000)   # 1 s tick, only used to expire the status message
        self.scr.timeout(1000)

        self.draw()   # initial paint
        status_was_showing = bool(self.status_msg)

        while True:
            key = self.scr.getch()

            items_len = len(GRAPHICS_MODES) if self.tab == self.TAB_GRAPHICS \
                        else len(POWER_PROFILES)

            needs_redraw = False

            if key == curses.KEY_RESIZE:
                self._layout()
                self.scr.timeout(1000)
                needs_redraw = True
            elif key in (ord('q'), ord('Q'), 27):
                break
            elif key in (ord('g'), ord('G')):
                self.tab = self.TAB_GRAPHICS
                needs_redraw = True
            elif key in (ord('p'), ord('P')):
                self.tab = self.TAB_PROFILE
                needs_redraw = True
            elif key in (ord('r'), ord('R')):
                self._refresh_state()
                self.set_status("State refreshed.", ok=True)
                needs_redraw = True
            elif key == curses.KEY_UP:
                if self.tab == self.TAB_GRAPHICS:
                    self.g_cursor = (self.g_cursor - 1) % items_len
                else:
                    self.p_cursor = (self.p_cursor - 1) % items_len
                needs_redraw = True
            elif key == curses.KEY_DOWN:
                if self.tab == self.TAB_GRAPHICS:
                    self.g_cursor = (self.g_cursor + 1) % items_len
                else:
                    self.p_cursor = (self.p_cursor + 1) % items_len
                needs_redraw = True
            elif key in (curses.KEY_ENTER, 10, 13):
                self.apply_current()
                needs_redraw = True
            elif key == ord('\t'):
                self.tab = 1 - self.tab
                needs_redraw = True
            elif key == -1:
                # Idle timeout tick — only redraw if the status message's
                # visible/expired state just changed (so it disappears
                # promptly after 8s), not on every single tick.
                status_showing_now = bool(self.status_msg) and \
                                      (time.time() - self.status_ts) < 8
                if status_showing_now != status_was_showing:
                    needs_redraw = True
                status_was_showing = status_showing_now

            if needs_redraw:
                self.draw()
                status_was_showing = bool(self.status_msg) and \
                                      (time.time() - self.status_ts) < 8


def main():
    def _run(stdscr):
        app = GPUMode(stdscr)
        app.run()

    curses.wrapper(_run)


# ─── self-spawning launcher ─────────────────────────────────────────────────
#
# When run normally from a shell, gpu-mode re-execs itself inside a freshly
# spawned terminal window sized to exactly fit the fixed PANEL_W x PANEL_H
# panel, then exits the original invocation immediately. The spawned
# terminal closes on its own once the app exits (q / Ctrl-C), since most
# terminal emulators close their window when the foreground process ends.
#
# Set GPU_MODE_SPAWNED=1 to skip spawning and just run the TUI directly in
# the current terminal (this is what the spawned window's command does).

_SPAWN_MARKER = "GPU_MODE_SPAWNED"

# (terminal binary, args-builder) — tried in this order. args-builder takes
# (cols, rows, exec_argv) and returns the full argv to launch that terminal.
# cols/rows are character-cell dimensions; exec_argv is this script's own
# re-exec command (python3 + this file path + the spawn marker is set via
# env, not argv).
def _build_shell_command_raw(inner_cmd):
    """Wrap a shell command string so that on failure it prints the exit
    code and waits for a keypress before the terminal closes — so a crash
    is visible instead of the window vanishing instantly.
    """
    return (
        f"{inner_cmd}; "
        f'ec=$?; '
        f'if [ "$ec" -ne 0 ]; then '
        f'  echo; echo "[gpu-mode] exited with code $ec"; '
        f'  echo "[gpu-mode] press Enter to close this window..."; '
        f'  read _; '
        f'fi'
    )

def _terminal_candidates(cols, rows, shell_cmd):
    geometry = f"{cols}x{rows}"
    return [
        # xterm: the most reliable for exact character-cell geometry.
        ("xterm", ["xterm", "-geometry", geometry, "-fa", "Monospace",
                   "-fs", "11", "-e", "sh", "-c", shell_cmd]),
        # GNOME Terminal (Pop!_OS pre-COSMIC default, still common).
        ("gnome-terminal", ["gnome-terminal", f"--geometry={geometry}",
                             "--", "sh", "-c", shell_cmd]),
        ("tilix", ["tilix", f"--geometry={geometry}", "-e",
                    f"sh -c {_sh_quote(shell_cmd)}"]),
        ("konsole", ["konsole", "--geometry", geometry, "-e",
                      "sh", "-c", shell_cmd]),
        ("alacritty", ["alacritty", "-o",
                        f"window.dimensions.columns={cols}",
                        "-o", f"window.dimensions.lines={rows}",
                        "-e", "sh", "-c", shell_cmd]),
        ("kitty", ["kitty", "-o", f"initial_window_width={cols}c",
                    "-o", f"initial_window_height={rows}c",
                    "sh", "-c", shell_cmd]),
        # COSMIC Terminal — last resort. No documented --geometry flag,
        # and has a confirmed crash in at least one build when given
        # multi-token -e arguments. Only used if nothing else is found.
        ("cosmic-term", ["cosmic-term", "-e", shell_cmd]),
        ("x-terminal-emulator", ["x-terminal-emulator", "-e",
                                   "sh", "-c", shell_cmd]),
    ]

def _sh_quote(s):
    return shlex.quote(s)

def _find_terminal(cols, rows, shell_cmd):
    """Return the first terminal launch argv to use.

    Preference order:
      1. $TERMINAL env var, if set and the binary exists on PATH.
      2. The system's configured default (`update-alternatives
         --query x-terminal-emulator`), if it resolves to a binary we
         know how to size.
      3. The static candidate list, first match wins.
    """
    candidates = _terminal_candidates(cols, rows, shell_cmd)
    by_name = {name: argv for name, argv in candidates}

    # 1. Explicit user preference via $TERMINAL.
    term_env = os.environ.get("TERMINAL", "").strip()
    if term_env:
        base = os.path.basename(term_env)
        if base in by_name and shutil.which(base):
            return by_name[base]
        elif shutil.which(term_env):
            return [term_env, "-e", "sh", "-c", shell_cmd]

    # 2. System-configured default terminal (Debian/Ubuntu alternatives).
    try:
        result = subprocess.run(
            ["update-alternatives", "--query", "x-terminal-emulator"],
            capture_output=True, text=True, timeout=3,
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                if line.startswith("Value:"):
                    default_path = line.split(":", 1)[1].strip()
                    base = os.path.basename(default_path)
                    # Debian/Ubuntu often registers a "*.wrapper" script
                    # (e.g. tilix.wrapper, gnome-terminal.wrapper) rather
                    # than the real binary name — strip that suffix so it
                    # still matches our candidate list.
                    if base.endswith(".wrapper"):
                        base = base[: -len(".wrapper")]
                    if base in by_name and shutil.which(base):
                        return by_name[base]
                    elif shutil.which(base):
                        return [base, "-e", "sh", "-c", shell_cmd]
                    break
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # 3. Static ordered list — first installed binary wins.
    for name, argv in candidates:
        if shutil.which(name):
            return argv
    return None

def _spawn_in_sized_terminal():
    """Spawn a new terminal window sized for PANEL_W x PANEL_H and exit."""
    script_path = os.path.abspath(__file__)
    cols = PANEL_W
    rows = PANEL_H

    # Build the inner command as a single shell string so every terminal's
    # -e flag handles it identically, regardless of how strictly each one
    # splits multi-token -e arguments (this was the actual cause of the
    # window opening then closing instantly with Tilix — see chat history).
    # The spawn marker is set inline in the command itself rather than
    # relying solely on env propagation, since not every terminal reliably
    # forwards a custom environment to the child process.
    inner_argv = [
        f"{_SPAWN_MARKER}=1",
        sys.executable,
        script_path,
    ]
    inner_cmd = " ".join(shlex.quote(a) for a in inner_argv)
    shell_cmd = _build_shell_command_raw(inner_cmd)

    argv = _find_terminal(cols, rows, shell_cmd)

    if argv is None:
        # No known terminal emulator found — just run in place instead of
        # silently failing.
        os.environ[_SPAWN_MARKER] = "1"
        main()
        return

    env = os.environ.copy()
    env[_SPAWN_MARKER] = "1"
    try:
        subprocess.Popen(argv, env=env)
    except OSError as e:
        # Spawn failed for some reason — fall back to running in place,
        # but tell the user why instead of failing silently.
        print(f"[gpu-mode] could not launch a terminal window ({e}); "
              f"running here instead.", file=sys.stderr)
        os.environ[_SPAWN_MARKER] = "1"
        main()
        return
    # Original invocation's job is done — the spawned terminal now owns
    # the app. Exit immediately so the launching shell gets its prompt
    # back right away instead of waiting.
    sys.exit(0)


if __name__ == "__main__":
    if os.environ.get(_SPAWN_MARKER) == "1":
        main()
    else:
        _spawn_in_sized_terminal()
