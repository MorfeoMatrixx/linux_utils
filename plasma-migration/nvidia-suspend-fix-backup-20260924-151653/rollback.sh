#!/bin/bash
# Rollback for the 2026-09-24 NVIDIA suspend fix: remove the 60-plasma-vt-switch.conf
# drop-ins, returning to Pop!_OS's unconditional Cosmic VT-switch bypass (50-*.conf,
# which was never modified). Then verifies against the pre-change snapshot.
set -euo pipefail
B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for s in suspend hibernate suspend-then-hibernate; do
    sudo rm -fv /etc/systemd/system/nvidia-$s.service.d/60-plasma-vt-switch.conf
done
sudo systemctl daemon-reload
ok=1
for s in suspend hibernate suspend-then-hibernate resume; do
    if diff -q <(systemctl cat nvidia-$s.service) "$B/nvidia-$s.effective-before.txt" >/dev/null; then
        echo "nvidia-$s.service: matches pre-change state"
    else
        echo "nvidia-$s.service: DIFFERS from pre-change state:"; diff <(systemctl cat nvidia-$s.service) "$B/nvidia-$s.effective-before.txt" || true; ok=0
    fi
done
# The 50-*.conf files were never touched; restore them only if something removed them.
for s in suspend hibernate suspend-then-hibernate; do
    f=/etc/systemd/system/nvidia-$s.service.d/50-cosmic-no-vt-switch.conf
    [[ -f $f ]] || { echo "Restoring missing $f"; sudo install -m 644 "$B/nvidia-$s.service.d/50-cosmic-no-vt-switch.conf" "$f"; sudo systemctl daemon-reload; }
done
(( ok )) && echo "Rollback complete." || echo "Rollback done, but review the differences above."
