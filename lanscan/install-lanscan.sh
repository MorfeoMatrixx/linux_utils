#!/bin/bash
# Installs lanscan.sh from ~/claude/utils/lanscan source into ~/bin,
# and symlinks /usr/local/bin so sudo can find it, no code duplication.

SRC="$HOME/claude/utils/lanscan/lanscan.sh"
DEST="$HOME/bin/lanscan.sh"
LINK="/usr/local/bin/lanscan.sh"

if [ ! -f "$SRC" ]; then
    echo "Source not found: $SRC"
    exit 1
fi

mkdir -p "$HOME/bin"

# Remove any stale real file in /usr/local/bin (old duplicate copy)
if [ -f "$LINK" ] && [ ! -L "$LINK" ]; then
    echo "Removing old duplicate at $LINK"
    sudo rm -f "$LINK"
fi

# Copy source -> ~/bin
cp -f "$SRC" "$DEST"
chmod +x "$DEST"
echo "Installed: $DEST"

# Symlink /usr/local/bin -> ~/bin (create or refresh)
sudo ln -sf "$DEST" "$LINK"
echo "Linked: $LINK -> $DEST"

# Ensure ~/bin is in PATH for normal (non-sudo) use
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/bin to PATH in ~/.bashrc (run: source ~/.bashrc)"
fi
