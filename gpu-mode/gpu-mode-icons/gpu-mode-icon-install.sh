#!/usr/bin/env bash
# gpu-mode-icon-install.sh
# Installs the gpu-mode icon (as properly-sized PNGs, the most reliable
# format across desktop environments) and creates/updates the .desktop
# launcher entry so the app shows up in COSMIC's application menu.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ICONS_DIR="$HOME/.local/share/icons/hicolor"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/gpu-mode.desktop"
GPU_MODE_BIN="$HOME/.local/bin/gpu-mode"

# The single canonical copy used directly by the .desktop file's Icon=
# line (an absolute path always works, regardless of whether the
# desktop's icon theme cache resolves theme-name lookups correctly —
# this was the actual cause of the icon not showing up before).
CANONICAL_ICON="$HOME/.local/share/icons/gpu-mode.png"

echo "==> Installing icon (PNG set, all standard sizes)..."
for size in 16 22 24 32 48 64 128 256 512; do
    src="$SCRIPT_DIR/gpu-mode-icon-${size}.png"
    if [ -f "$src" ]; then
        dest_dir="$ICONS_DIR/${size}x${size}/apps"
        mkdir -p "$dest_dir"
        cp "$src" "$dest_dir/gpu-mode.png"
    fi
done

# Also install the scalable SVG, for desktops that DO resolve it correctly.
if [ -f "$SCRIPT_DIR/gpu-mode-icon.svg" ]; then
    dest_dir="$ICONS_DIR/scalable/apps"
    mkdir -p "$dest_dir"
    cp "$SCRIPT_DIR/gpu-mode-icon.svg" "$dest_dir/gpu-mode.svg"
fi

# Canonical 256px copy at a fixed, predictable absolute path.
mkdir -p "$(dirname "$CANONICAL_ICON")"
if [ -f "$SCRIPT_DIR/gpu-mode-icon-256.png" ]; then
    cp "$SCRIPT_DIR/gpu-mode-icon-256.png" "$CANONICAL_ICON"
elif [ -f "$SCRIPT_DIR/gpu-mode-icon-48.png" ]; then
    cp "$SCRIPT_DIR/gpu-mode-icon-48.png" "$CANONICAL_ICON"
fi

echo "==> Writing desktop entry..."
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Type=Application
Name=GPU Mode
Comment=Switch GPU graphics mode and CPU power profile
Exec=$GPU_MODE_BIN
Icon=$CANONICAL_ICON
Terminal=false
Categories=System;Settings;Utility;
StartupNotify=true
EOF

echo "==> Refreshing icon cache and desktop database..."
gtk-update-icon-cache -f -t "$ICONS_DIR" 2>/dev/null || true
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

echo ""
echo "==> Done! 'GPU Mode' should now appear in the COSMIC app launcher"
echo "    with its icon. If it still doesn't show up, log out and back in"
echo "    once (icon/desktop caches are sometimes only refreshed then)."
echo ""
