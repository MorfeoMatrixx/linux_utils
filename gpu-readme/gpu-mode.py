#!/usr/bin/env python3
"""
gpu-mode — system76-power TUI for Lenovo LOQ on Pop!_OS
Green-on-black terminal control panel for GPU mode & CPU profile switching.
"""

import curses
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

def _extract_value(out):
    """system76-power prints lines like 'Graphics mode: hybrid' or
    'Profile: balanced' — pull out just the trailing value, lowercased."""
    if not out:
        return None
    line = out.strip().splitlines()[-1]
    if ":" in line:
        line = line.split(":", 1)[1]
    return line.strip().lower()

def get_current_graphics():
    out, err, rc = run_cmd(["system76-power", "graphics"], timeout=QUERY_TIMEOUT)
    if rc == 0 and out:
        return _extract_value(out)
    return None

def get_current_profile():
    out, err, rc = run_cmd(["system76-power", "profile"], timeout=QUERY_TIMEOUT)
    if rc == 0 and out:
        return _extract_value(out)
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
        self.cur_graphics = None
        self.cur_profile  = None
        self.pending_reboot = False
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

    def _refresh_state(self):
        self.cur_graphics = get_current_graphics()
        self.cur_profile  = get_current_profile()

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

        self.stdscr.erase()
        self.stdscr.refresh()

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
        win.refresh()

    def _draw_header(self, w):
        # Row 1: title only (compact — no subtitle row to save vertical space)
        title = "GPU-MODE"
        addstr_clipped(self.scr, 1, 2, "*", curses.color_pair(P_DIM))
        addstr_clipped(self.scr, 1, w - len(title) - 2, title,
                       curses.color_pair(P_HEADER) | curses.A_BOLD)

        # Row 2: live state badge
        g = (self.cur_graphics or "?").upper()
        p = (self.cur_profile  or "?").upper()
        badge = f"GPU:{g} CPU:{p}"
        addstr_clipped(self.scr, 2, 2, badge,
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
          10     ╨ divider bottom / blank
          11     ╠══════╣ (status sep)
          12     status text
          13     ╠══════╣ (help sep)
          14     help text
          15     ╚══frame bottom══╝
        """
        LIST_W   = 13             # left column width (inside frame) — fits "PERFORMANCE"
        DESC_X   = LIST_W + 3     # description column start
        DESC_W   = w - DESC_X - 1
        TOP      = 6              # first content row (mode list / desc title)
        DIV_BOT  = 10             # row where the inner vertical divider ends

        # ── left column: mode list (one row per item) ──────────────────────
        for i, item in enumerate(items):
            y = TOP + i
            if y >= DIV_BOT:
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
            else:
                attr_label = curses.color_pair(P_MODE)

            marker = "►" if is_cur else " "
            label = item["label"][:LIST_W - 2]
            addstr_clipped(self.scr, y, 1, f"{marker}{label}", attr_label)

        # vertical divider between list and description
        inner_vline(self.scr, TOP - 1, DIV_BOT, LIST_W + 1, P_BORDER,
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
            badge_attr = curses.color_pair(P_WARN) | curses.A_BOLD
        else:
            badge = "OK INSTANT"
            badge_attr = curses.color_pair(P_ACTIVE) | curses.A_BOLD
        badge_x = w - 1 - len(badge)
        if badge_x > DESC_X + len(title_text) + (8 if is_cur_sel else 0):
            addstr_clipped(self.scr, TOP, badge_x, badge, badge_attr)

        # word-wrapped description fills the remaining rows down to DIV_BOT-1
        lines = textwrap.wrap(sel["desc"], width=DESC_W)
        first_desc_row = TOP + 1
        max_lines = DIV_BOT - first_desc_row
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
            self.draw()   # paint the "working" message before the blocking call
            ok, msg = set_graphics(mode)
            if ok:
                self.cur_graphics = mode
                suffix = "  — REBOOT required to apply." if reboot else ""
                self.set_status(f"Graphics set to {label}.{suffix}", ok=True)
            else:
                self.set_status(f"Error: {msg}", ok=False)
        else:
            prof  = POWER_PROFILES[self.p_cursor]["id"]
            label = POWER_PROFILES[self.p_cursor]["label"]
            if prof == self.cur_profile:
                self.set_status(f"{label} is already active.", ok=True)
                return
            self.set_status(f"Switching to {label}...", ok=True)
            self.draw()   # paint the "working" message before the blocking call
            ok, msg = set_profile(prof)
            if ok:
                self.cur_profile = prof
                self.set_status(f"Profile set to {label}. Active immediately.", ok=True)
            else:
                self.set_status(f"Error: {msg}", ok=False)

    def run(self):
        curses.curs_set(0)
        self.stdscr.timeout(1000)   # 1 s refresh for status message expiry
        self.scr.timeout(1000)

        while True:
            self.draw()
            key = self.scr.getch()

            items_len = len(GRAPHICS_MODES) if self.tab == self.TAB_GRAPHICS \
                        else len(POWER_PROFILES)

            if key == curses.KEY_RESIZE:
                self._layout()
                self.scr.timeout(1000)
                continue
            elif key in (ord('q'), ord('Q'), 27):
                break
            elif key in (ord('g'), ord('G')):
                self.tab = self.TAB_GRAPHICS
            elif key in (ord('p'), ord('P')):
                self.tab = self.TAB_PROFILE
            elif key in (ord('r'), ord('R')):
                self._refresh_state()
                self.set_status("State refreshed.", ok=True)
            elif key == curses.KEY_UP:
                if self.tab == self.TAB_GRAPHICS:
                    self.g_cursor = (self.g_cursor - 1) % items_len
                else:
                    self.p_cursor = (self.p_cursor - 1) % items_len
            elif key == curses.KEY_DOWN:
                if self.tab == self.TAB_GRAPHICS:
                    self.g_cursor = (self.g_cursor + 1) % items_len
                else:
                    self.p_cursor = (self.p_cursor + 1) % items_len
            elif key in (curses.KEY_ENTER, 10, 13):
                self.apply_current()
            elif key == ord('\t'):
                self.tab = 1 - self.tab


def main():
    def _run(stdscr):
        app = GPUMode(stdscr)
        app.run()

    curses.wrapper(_run)


if __name__ == "__main__":
    main()
