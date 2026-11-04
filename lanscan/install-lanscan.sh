#!/bin/bash
# Links lanscan into ~/bin (extension-less command, symlink to the source here)
# and into /usr/local/bin so sudo can find it. No copies, no code duplication.

SRC="$HOME/claude/utils/lanscan/lanscan.sh"
DEST="$HOME/bin/lanscan"
LINK="/usr/local/bin/lanscan"

if [ ! -f "$SRC" ]; then
    echo "Source not found: $SRC"
    exit 1
fi

mkdir -p "$HOME/bin"
chmod +x "$SRC"

# Retire the old extension-ful names (real file or stale link) from earlier installs
if [ -e /usr/local/bin/lanscan.sh ] || [ -L /usr/local/bin/lanscan.sh ]; then
    echo "Removing old /usr/local/bin/lanscan.sh"
    sudo rm -f /usr/local/bin/lanscan.sh
fi
[ -L "$HOME/bin/lanscan.sh" ] && rm -f "$HOME/bin/lanscan.sh"

# ~/bin -> source
ln -sfn "$SRC" "$DEST"
echo "Linked: $DEST -> $SRC"

# /usr/local/bin -> ~/bin (create or refresh)
sudo ln -sfn "$DEST" "$LINK"
echo "Linked: $LINK -> $DEST"

# Ensure ~/bin is in PATH for normal (non-sudo) use
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    echo "Added ~/bin to PATH in ~/.bashrc (run: source ~/.bashrc)"
fi
