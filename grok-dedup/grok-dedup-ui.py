#!/usr/bin/env python3
"""Duplicate image/video deduplicator UI — reads NUL-delimited file paths from stdin."""
import sys
import os
import io
import hashlib
import datetime
import subprocess
from collections import defaultdict
from pathlib import Path
import tkinter as tk

try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

THUMB_W, THUMB_H = 300, 300
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'}
VIDEO_EXTS = {'.mp4', '.mov', '.webm', '.mkv', '.avi'}

# Initial window size pre-sized for 3 cards side by side (covers the common 2-3 duplicate case)
# card width = thumbnail + internal padding (8px each side) + grid gap (10px each side)
_CARD_SLOT  = THUMB_W + 8 * 2 + 10 * 2   # 336px per card
_WIN_W      = 3 * _CARD_SLOT + 10 * 2     # outer frame padx on both sides → 1028px
_WIN_H      = THUMB_H + 120 + 40 + 140    # canvas + header + button rows + msg + margins → 600px


def file_hash(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


def find_duplicate_groups(paths):
    buckets = defaultdict(list)
    total = len(paths)
    for i, p in enumerate(paths, 1):
        print(f'\rHashing… {i} / {total}', end='', flush=True, file=sys.stderr)
        try:
            buckets[file_hash(p)].append(p)
        except OSError as e:
            print(f'\nWarning: skipping {p}: {e}', file=sys.stderr)
    print(file=sys.stderr)   # newline to close the progress line
    # sort each group oldest-first; keep only groups with more than one file
    return [
        sorted(group, key=lambda p: os.stat(p).st_mtime)
        for group in buckets.values()
        if len(group) > 1
    ]


def try_trash(path):
    """Return True if trashed successfully, False if no trash bin available."""
    return subprocess.run(['gio', 'trash', path], capture_output=True).returncode == 0


def make_thumbnail(path):
    """Return an ImageTk.PhotoImage thumbnail, or None on failure."""
    if not HAS_PIL:
        return None
    ext = Path(path).suffix.lower()
    try:
        if ext in IMAGE_EXTS:
            img = Image.open(path)
        elif ext in VIDEO_EXTS:
            # Ask ffmpeg to decode only the very first frame and pipe it as PNG.
            # -ss before -i = fast keyframe seek; approximates frame #90 at ~30fps.
            # Fall back to frame #1 for videos shorter than 3 seconds.
            for seek in ('00:00:03', None):
                cmd = ['ffmpeg']
                if seek:
                    cmd += ['-ss', seek]
                cmd += ['-i', path, '-vframes', '1', '-f', 'image2pipe', '-vcodec', 'png', '-']
                result = subprocess.run(cmd, capture_output=True)
                if result.returncode == 0 and result.stdout:
                    break
            else:
                return None
            img = Image.open(io.BytesIO(result.stdout))
        else:
            return None
        img.thumbnail((THUMB_W, THUMB_H))
        return ImageTk.PhotoImage(img)
    except Exception:
        return None


class DeduplicatorApp(tk.Tk):
    def __init__(self, groups):
        super().__init__()
        self.title("Image Deduplicator")
        self.geometry(f"{_WIN_W}x{_WIN_H}")
        self.resizable(True, True)
        self.groups = groups
        self.idx = 0
        self._photo_refs = []
        self._no_trash_confirmed = False   # True after user OKs first permanent delete
        self._stats = {'deleted': 0, 'skipped': 0, 'errors': 0}
        self._build_chrome()
        self._show_group()

    def _build_chrome(self):
        self.header = tk.Label(self, font=('sans', 13, 'bold'), pady=6)
        self.header.pack()

        # scrollable canvas for the image row
        outer = tk.Frame(self)
        outer.pack(fill='both', expand=True, padx=10)

        self._canvas = tk.Canvas(outer, height=THUMB_H + 120)
        sb = tk.Scrollbar(outer, orient='horizontal', command=self._canvas.xview)
        self._canvas.configure(xscrollcommand=sb.set)
        sb.pack(side='bottom', fill='x')
        self._canvas.pack(side='top', fill='both', expand=True)

        self._images_frame = tk.Frame(self._canvas)
        self._canvas_window = self._canvas.create_window((0, 0), window=self._images_frame, anchor='nw')
        self._images_frame.bind('<Configure>', self._on_frame_resize)

        # message bar — sits between canvas and buttons
        self._msg = tk.Label(self, text='', font=('sans', 10), pady=4,
                             anchor='w', justify='left', height=2, wraplength=_WIN_W - 32)
        self._msg.pack(fill='x', padx=16)

        # main action buttons
        self._btn_frame = tk.Frame(self)
        self._btn_frame.pack(pady=8)
        self._btn_delete = tk.Button(self._btn_frame, text='Delete duplicates  (keep oldest)',
                  bg='#c0392b', fg='white', font=('sans', 11, 'bold'),
                  padx=10, command=self._delete)
        self._btn_delete.pack(side='left', padx=10)
        tk.Button(self._btn_frame, text='Skip',
                  bg='#a0a0a0', fg='white', font=('sans', 11), padx=10, command=self._skip).pack(side='left', padx=10)
        tk.Button(self._btn_frame, text='Delete All Remaining',
                  bg='#6c3483', fg='white', font=('sans', 11, 'bold'),
                  padx=10, command=self._delete_all_remaining).pack(side='left', padx=10)
        tk.Button(self._btn_frame, text='Quit',
                  bg='#a0a0a0', fg='white', font=('sans', 11), padx=10, command=self.destroy).pack(side='left', padx=10)

        # inline confirmation row (hidden until needed — reused for no-trash and delete-all)
        self._confirm_frame = tk.Frame(self)
        self._confirm_label = tk.Label(self._confirm_frame, text='', font=('sans', 10))
        self._confirm_label.pack(side='left', padx=(0, 10))
        tk.Button(self._confirm_frame, text='Yes', bg='#c0392b', fg='white',
                  font=('sans', 11, 'bold'), padx=10,
                  command=self._confirm_yes).pack(side='left', padx=6)
        tk.Button(self._confirm_frame, text='No',
                  bg='#a0a0a0', fg='white', font=('sans', 11), padx=10,
                  command=self._confirm_no).pack(side='left', padx=6)
        self._confirm_action = None   # callable set before showing confirm row

    def _on_frame_resize(self, _event):
        self._canvas.configure(scrollregion=self._canvas.bbox('all'))

    def _show_group(self):
        self._photo_refs = []          # clear refs BEFORE destroying old widgets
        for w in self._images_frame.winfo_children():
            w.destroy()
        self.update_idletasks()        # flush pending geometry so canvas resets cleanly

        if self.idx >= len(self.groups):
            s = self._stats
            total_groups = len(self.groups)
            print(
                f"\nAll {total_groups} group(s) reviewed — "
                f"deleted: {s['deleted']}  skipped: {s['skipped']}  errors: {s['errors']}",
                file=sys.stderr
            )
            self.destroy()
            return

        group = self.groups[self.idx]
        self.header.config(
            text=f"Group {self.idx + 1} of {len(self.groups)}  —  {len(group)} identical files"
        )

        for i, path in enumerate(group):
            keep = (i == 0)
            card = tk.Frame(self._images_frame, bd=2,
                            relief='solid', padx=8, pady=8,
                            bg='#eafaf1' if keep else '#fdedec')
            card.grid(row=0, column=i, padx=10, pady=8, sticky='n')

            # thumbnail or placeholder
            photo = make_thumbnail(path)
            if photo:
                self._photo_refs.append(photo)
                tk.Label(card, image=photo, bg=card['bg']).pack()
            else:
                ext = Path(path).suffix.upper()
                tk.Label(card, text=f"[{ext or 'FILE'}]",
                         width=28, height=12, bg='#dfe6e9',
                         font=('mono', 11)).pack()

            tk.Label(card, text=Path(path).name,
                     wraplength=THUMB_W, font=('mono', 9, 'bold'),
                     height=2, justify='center', anchor='n',
                     bg=card['bg']).pack(pady=(6, 0), fill='x')
            tk.Label(card, text=str(Path(path).parent),
                     wraplength=THUMB_W, font=('sans', 8),
                     fg='#636e72', bg=card['bg']).pack()

            mtime = datetime.datetime.fromtimestamp(os.stat(path).st_mtime)
            badge_text = f"★ KEEP  (oldest)\n{mtime:%Y-%m-%d  %H:%M}"
            badge_bg   = '#27ae60' if keep else '#c0392b'
            badge_fg   = 'white'
            tk.Label(card, text=badge_text if keep else f"✕ DELETE\n{mtime:%Y-%m-%d  %H:%M}",
                     bg=badge_bg, fg=badge_fg,
                     font=('sans', 9, 'bold'), padx=6, pady=4).pack(pady=6)

        self.update_idletasks()
        self._canvas.xview_moveto(0)   # scroll back to left for each new group

    def _set_msg(self, text, color='#2c3e50', font=('sans', 10)):
        self._msg.config(text=text, fg=color, font=font)

    def _show_confirm_row(self, label_text, on_yes, on_no):
        self._confirm_label.config(text=label_text)
        self._confirm_action = (on_yes, on_no)
        self._btn_frame.pack_forget()
        self._confirm_frame.pack(pady=8)

    def _hide_confirm_row(self):
        self._confirm_frame.pack_forget()
        self._btn_frame.pack(pady=8)

    def _confirm_yes(self):
        self._hide_confirm_row()
        self._confirm_action[0]()

    def _confirm_no(self):
        self._hide_confirm_row()
        self._confirm_action[1]()

    def _do_permanent_delete(self, paths):
        errors = []
        for path in paths:
            try:
                os.remove(path)
            except PermissionError:
                errors.append(f"Permission denied: {Path(path).name}")
            except Exception as e:
                errors.append(f"{Path(path).name}: {e}")
        self._finish_delete(paths, errors)

    def _finish_delete(self, to_delete, errors):
        if errors:
            self._stats['errors'] += len(errors)
            self._set_msg(
                "  ".join(errors),
                color='#c0392b',
                font=('sans', 12, 'bold'),
            )
        else:
            self._stats['deleted'] += len(to_delete)
            self._set_msg(f"Deleted {len(to_delete)} file(s).", '#27ae60')
        self.idx += 1
        self._show_group()

    def _delete(self):
        group = self.groups[self.idx]
        to_delete = group[1:]   # group[0] is oldest — keep it

        no_trash = []
        errors   = []
        for path in to_delete:
            try:
                if not try_trash(path):
                    no_trash.append(path)
            except Exception as e:
                errors.append(f"{Path(path).name}: {e}")

        trashed = len(to_delete) - len(no_trash) - len(errors)
        self._stats['deleted'] += trashed

        if no_trash and not self._no_trash_confirmed:
            self._set_msg(
                f'No trash bin — {len(no_trash)} file(s) will be permanently deleted.',
                '#cc44cc', font=('sans', 12, 'bold'),
            )
            self._show_confirm_row(
                'Permanently delete?',
                on_yes=lambda: (setattr(self, '_no_trash_confirmed', True),
                                self._do_permanent_delete(no_trash)),
                on_no=lambda: (self._set_msg('Group skipped.'),
                               self._stats.update({'skipped': self._stats['skipped'] + 1}),
                               setattr(self, 'idx', self.idx + 1),
                               self._show_group()),
            )
            return

        if no_trash:
            self._do_permanent_delete(no_trash)
            return

        self._finish_delete(to_delete, errors)

    def _skip(self):
        self._set_msg('Skipped.')
        self._stats['skipped'] += 1
        self.idx += 1
        self._show_group()

    def _delete_all_remaining(self):
        remaining = len(self.groups) - self.idx
        self._set_msg(
            f'Delete duplicates in all {remaining} remaining group(s)?',
            '#6c3483', font=('sans', 12, 'bold'),
        )
        self._show_confirm_row(
            f'All {remaining} groups',
            on_yes=self._do_delete_all_remaining,
            on_no=lambda: self._set_msg(''),
        )

    def _do_delete_all_remaining(self):
        while self.idx < len(self.groups):
            group = self.groups[self.idx]
            to_delete = group[1:]
            for path in to_delete:
                self._set_msg(f'Processing group {self.idx + 1} / {len(self.groups)}…')
                self.update_idletasks()
                try:
                    if not try_trash(path):
                        if not self._no_trash_confirmed:
                            self._no_trash_confirmed = True
                        os.remove(path)
                    self._stats['deleted'] += 1
                except PermissionError:
                    self._stats['errors'] += 1
                except Exception:
                    self._stats['errors'] += 1
            self.idx += 1
        self._show_group()   # triggers auto-close + stats print



def main():
    raw = sys.stdin.buffer.read()
    paths = [p.decode() for p in raw.split(b'\0') if p]
    if not paths:
        print("No image or video files found in the selected directory.", file=sys.stderr)
        return

    groups = find_duplicate_groups(paths)

    if not groups:
        print("No duplicate files found.", file=sys.stderr)
        return

    total_dupes = sum(len(g) - 1 for g in groups)
    print(f"Found {len(groups)} duplicate group(s) ({total_dupes} files to review).", file=sys.stderr)
    DeduplicatorApp(groups).mainloop()


if __name__ == '__main__':
    main()
