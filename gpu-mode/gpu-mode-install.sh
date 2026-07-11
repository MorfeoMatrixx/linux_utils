#!/usr/bin/env bash
# gpu-mode-install.sh
# Installs gpu-mode.py to ~/.local/bin and sets up the sudoers rule so the TUI
# can call system76-power without a password prompt.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
APP_SRC="$SCRIPT_DIR/gpu-mode.py"
APP_DEST="$BIN_DIR/gpu-mode"

echo "==> Creating $BIN_DIR if needed..."
mkdir -p "$BIN_DIR"

echo "==> Installing gpu-mode → $APP_DEST"
cp "$APP_SRC" "$APP_DEST"
chmod +x "$APP_DEST"

# Make sure ~/.local/bin is on PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "  NOTE: Add this line to your ~/.bashrc or ~/.zshrc:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "==> Setting up sudoers rule for system76-power..."
echo "    (This allows gpu-mode to switch modes without a password prompt)"
echo ""

SUDOERS_LINE="%sudo ALL=(ALL) NOPASSWD: /usr/bin/system76-power"
SUDOERS_FILE="/etc/sudoers.d/system76-power-nopasswd"

if sudo test -f "$SUDOERS_FILE" 2>/dev/null; then
    echo "    Sudoers rule already exists at $SUDOERS_FILE — skipping."
else
    echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    echo "    Sudoers rule written to $SUDOERS_FILE"
fi

echo ""
echo "==> Done! Launch with:"
echo "    gpu-mode"
echo ""
