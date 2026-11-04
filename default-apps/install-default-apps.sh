#!/bin/bash
# install-default-apps.sh
# Links set-default-apps into ~/bin (extension-less symlink to the source here)
# and into /usr/local/bin. Nothing is copied, so edits to the source take effect at once.

set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p ~/bin

chmod +x "$SRC_DIR/set-default-apps.sh"
ln -sfn "$SRC_DIR/set-default-apps.sh" ~/bin/set-default-apps
rm -f ~/bin/set-default-apps.sh   # old copy from the previous install model, if any

sudo ln -sfn ~/bin/set-default-apps /usr/local/bin/set-default-apps
sudo rm -f /usr/local/bin/set-default-apps.sh

echo "Installed. Run it any time with:"
echo "  set-default-apps"
