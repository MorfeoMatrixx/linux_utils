#!/bin/bash
# set-default-apps.sh
# Reapplies default application (mimetype) associations for Pop!_OS with KDE Plasma
# (Cosmic still installed). mimeapps.list is shared by all desktops, so these apply
# in both sessions. Use after a fresh install or if a desktop's settings UI loses them.
#
# Location convention: ~/claude/utils/default-apps/set-default-apps.sh
# Install: ~/claude/utils/default-apps/install-default-apps.sh

set -e

echo "Setting default application associations..."

# --- Text / code (KWrite; Geany stays available under Open With) ---
# Set each type explicitly: KWrite only declares text/plain, so apps that declare
# the specific subtypes (e.g. Geany) would otherwise win.
for t in text/plain application/x-shellscript text/x-python text/x-python3 \
         text/x-csrc text/x-chdr text/x-c++src text/x-c++hdr text/x-makefile text/x-cmake \
         text/x-patch text/x-log text/x-readme application/json application/x-yaml \
         application/toml application/xml; do
    xdg-mime default org.kde.kwrite.desktop "$t"
done

# --- Markdown (MarkText flatpak, WYSIWYG) ---
xdg-mime default com.github.marktext.marktext.desktop text/markdown
xdg-mime default com.github.marktext.marktext.desktop text/x-markdown

# --- Images ---
xdg-mime default org.gnome.gThumb.desktop image/png
xdg-mime default org.gnome.gThumb.desktop image/jpeg

# --- Video (mpv for quick preview; VLC stays manual for full movies) ---
xdg-mime default mpv.desktop video/mp4

# --- Audio ---
xdg-mime default com.system76.CosmicPlayer.desktop audio/vnd.wave

# --- Documents ---
xdg-mime default okularApplication_pdf.desktop application/pdf

# --- File manager ---
xdg-mime default org.kde.dolphin.desktop inode/directory

# --- Browser / web / mail ---
xdg-mime default google-chrome.desktop text/html
xdg-mime default google-chrome.desktop x-scheme-handler/http
xdg-mime default google-chrome.desktop x-scheme-handler/https
xdg-mime default google-chrome.desktop x-scheme-handler/about
xdg-mime default google-chrome.desktop x-scheme-handler/unknown
xdg-mime default google-chrome.desktop x-scheme-handler/mailto

# --- Claude app / CLI handlers ---
xdg-mime default claude-code-url-handler.desktop x-scheme-handler/claude-cli
xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude

echo ""
echo "Done. Current mimeapps.list:"
echo "-----------------------------------"
cat ~/.config/mimeapps.list
