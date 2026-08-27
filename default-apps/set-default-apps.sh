#!/bin/bash
# set-default-apps.sh
# Reapplies default application (mimetype) associations for Pop!_OS / COSMIC.
# Use this after a fresh install, or whenever COSMIC Settings > Default Applications
# fails to persist a change (known COSMIC bug, esp. for video/*).
#
# Location convention: ~/claude/utils/default-apps/set-default-apps.sh
# Install: ~/claude/utils/default-apps/install-default-apps.sh

set -e

echo "Setting default application associations..."

# --- Text / code ---
xdg-mime default geany.desktop text/plain
xdg-mime default geany.desktop text/x-python
xdg-mime default geany.desktop application/x-shellscript
xdg-mime default md-viewer.desktop text/markdown

# --- Images ---
xdg-mime default org.gnome.gThumb.desktop image/png
xdg-mime default org.gnome.gThumb.desktop image/jpeg

# --- Video (mpv for quick preview; VLC stays manual for full movies) ---
xdg-mime default mpv.desktop video/mp4

# --- Audio ---
xdg-mime default com.system76.CosmicPlayer.desktop audio/vnd.wave

# --- Documents ---
xdg-mime default org.gnome.Evince.desktop application/pdf

# --- File manager ---
xdg-mime default nemo.desktop inode/directory
xdg-mime default nemo.desktop application/x-gnome-saved-search

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
