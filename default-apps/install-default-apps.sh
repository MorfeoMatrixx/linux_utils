#!/bin/bash
# install-default-apps.sh
# Copies set-default-apps.sh into ~/bin and symlinks it into /usr/local/bin.
# Run this from ~/claude/utils/default-apps/ after editing the source script.

set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p ~/bin

cp "$SRC_DIR/set-default-apps.sh" ~/bin/set-default-apps.sh
chmod +x ~/bin/set-default-apps.sh

sudo ln -sf ~/bin/set-default-apps.sh /usr/local/bin/set-default-apps.sh

echo "Installed. Run it any time with:"
echo "  set-default-apps.sh"
