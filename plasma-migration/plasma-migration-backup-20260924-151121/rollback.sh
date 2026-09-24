#!/bin/bash
# Rollback for the 2026-09-24 Plasma migration finish-up (steps 4-5 of the guide).
# Undoes: dolphin-plugins install, Dolphin as default for inode/directory.
# Does NOT remove Plasma/sddm itself - see the guide's "To uninstall Plasma later" section.
set -euo pipefail
B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Restoring ~/.config/mimeapps.list (default file manager -> $(cat "$B/inode-directory-default-before.txt"))"
cp -a "$B/mimeapps.list" ~/.config/mimeapps.list

echo "Dry run of package removal:"
sudo apt-get purge --dry-run dolphin-plugins | grep -E '^(Purg|Remv)' || true
read -rp "Purge dolphin-plugins? [y/N] " a
[[ $a == [yY] ]] && sudo apt-get purge -y dolphin-plugins

command -v kbuildsycoca5 >/dev/null && kbuildsycoca5 >/dev/null 2>&1 || true
echo "Now: $(xdg-mime query default inode/directory)"
