#!/bin/bash
# Re-apply the Plasma X11 HDMI-after-resume fix if an OS/driver upgrade removed or changed it.
#
# Pop!_OS ships 50-cosmic-no-vt-switch.conf drop-ins that unconditionally skip the
# "chvt 63" in nvidia-sleep.sh (cosmic-comp crashes on it). KWin/X11 needs that VT
# switch, otherwise PRIME outputs (HDMI-1-0) resume connected but dark. Our
# 60-plasma-vt-switch.conf drop-ins make the bypass conditional on cosmic-comp running.
#
# Usage: plasma-suspend-fix-redo.sh           summary, check, then ask before fixing any drift
#        plasma-suspend-fix-redo.sh --check   check only (exit 1 if a fix is needed)
#        plasma-suspend-fix-redo.sh -y        check, then fix without asking
#        plasma-suspend-fix-redo.sh -h        summary of purpose and how it works
set -euo pipefail

UNITDIR=/etc/systemd/system
DROPIN=60-plasma-vt-switch.conf
SERVICES=(suspend hibernate suspend-then-hibernate)

t() { tput "$@" 2>/dev/null || true; }   # no colors (not fatal) when $TERM is unset
GREEN=$(t setaf 2); YELLOW=$(t setaf 3); RED=$(t setaf 1); BOLD=$(t bold); RESET=$(t sgr0)
ok()   { echo "  ${RESET}${GREEN}${BOLD}OK${RESET}    $*"; }
warn() { echo "  ${RESET}${YELLOW}${BOLD}FIX${RESET}   $*"; }
die()  { echo "${RESET}${RED}${BOLD}ERROR:${RESET} $*" >&2; exit 2; }
hdr()  { echo; echo "${RESET}${GREEN}${BOLD}$*${RESET}"; }

summary() {
    cat <<EOF
${RESET}${GREEN}${BOLD}plasma-suspend-fix-redo.sh${RESET} - keep the Plasma X11 HDMI-after-resume fix in place

${BOLD}Purpose${RESET}
  On Plasma X11, an external HDMI monitor (PRIME output from the NVIDIA GPU) came back
  dark after suspend. Cause: Pop!_OS's 50-cosmic-no-vt-switch.conf drop-ins always skip
  the VT switch that nvidia-sleep.sh does before suspend - needed by Cosmic, but KWin/X11
  relies on it to re-sync the GPU outputs. The fix is a set of 60-plasma-vt-switch.conf
  drop-ins that skip the VT switch only when cosmic-comp is running. An OS or NVIDIA
  driver upgrade can remove or overwrite them; this script puts them back.

${BOLD}How it works${RESET}
  1. Check (always first, read-only): verifies nvidia-sleep.sh still works the way the fix
     assumes, then compares each installed 60- drop-in against the expected content.
     If everything matches, it stops here - nothing is changed.
  2. Reapply (only if needed, asks first): backs up the current drop-ins to
     ~/plasma-suspend-fix-backup-<timestamp>/, rewrites only the missing/changed ones,
     reloads systemd, and verifies the fix is the active ExecStart.
  Pop's 50- files and Cosmic's suspend behavior are never touched.

${BOLD}Options${RESET}
  (none)     summary, check, then ask before reapplying
  --check    check only, no changes (exit 0 = OK, 1 = fix needed, 2 = can't safely fix)
  -y         check, then reapply without asking (for scripts)
  -h         this summary
EOF
}

MODE=ask
case "${1:-}" in
    --check) MODE=check ;;
    -y|--yes) MODE=yes ;;
    -h|--help) summary; exit 0 ;;
    "") summary ;;
    *) echo "Usage: $(basename "$0") [--check | -y | -h]"; exit 2 ;;
esac

# Canonical drop-in content for one service. $1=service suffix, $2=word written to
# /proc/driver/nvidia/suspend in the Cosmic branch, $3=command for the non-Cosmic branch.
expected() {
    cat <<EOF
# Make 50-cosmic-no-vt-switch.conf's VT-switch bypass session-aware.
# cosmic-comp (Wayland) crashes if nvidia-sleep.sh does "chvt 63" before suspend,
# but KWin/X11 (Plasma) relies on it to release/re-acquire the GPU - without it,
# PRIME outputs (HDMI-1-0) come back connected but dark after resume.
# The resume side (nvidia-sleep.sh resume -> RestoreVT) is untouched; it switches
# back to the VT recorded here, or does nothing if the Cosmic branch ran.
# Installed by plasma-suspend-fix-redo.sh
[Service]
ExecStart=
ExecStart=/bin/sh -c 'if pgrep -x cosmic-comp >/dev/null 2>&1; then /usr/bin/logger -t suspend -s "nvidia-$1.service (COSMIC: VT switch bypassed)"; if [ -f /proc/driver/nvidia/suspend ]; then echo $2 > /proc/driver/nvidia/suspend; fi; else /usr/bin/logger -t suspend -s "nvidia-$1.service (non-COSMIC: normal VT switch)"; $3; fi'
EOF
}
expected_for() {
    case $1 in
        suspend)   expected suspend suspend 'exec /usr/bin/nvidia-sleep.sh suspend' ;;
        hibernate) expected hibernate hibernate 'exec /usr/bin/nvidia-sleep.sh hibernate' ;;
        suspend-then-hibernate)
                   expected suspend-then-hibernate suspend '/usr/bin/nvidia-sleep.sh is-suspend-then-hibernate-supported && exec /usr/bin/nvidia-sleep.sh suspend' ;;
    esac
}
service_section() { sed -n '/^\[Service\]/,$p'; }

hdr "[1/2] Checking (read-only)"
# Preconditions: the fix only makes sense if NVIDIA's sleep mechanism is still the old one.
systemctl cat nvidia-suspend.service >/dev/null 2>&1 || die "nvidia-suspend.service not found (NVIDIA driver not installed?)."
[[ -x /usr/bin/nvidia-sleep.sh ]] || die "/usr/bin/nvidia-sleep.sh is gone - NVIDIA changed its suspend mechanism. Don't reapply blindly; investigate first."
grep -q 'chvt 63' /usr/bin/nvidia-sleep.sh || die "nvidia-sleep.sh no longer does 'chvt 63' - the fix may be obsolete. Investigate first."
ok "nvidia-sleep.sh present and still does the VT switch the fix relies on"
NEED=()
for s in "${SERVICES[@]}"; do
    f=$UNITDIR/nvidia-$s.service.d/$DROPIN
    if [[ ! -f $f ]]; then
        warn "nvidia-$s: $DROPIN missing"; NEED+=("$s")
    elif ! diff -q <(service_section < "$f") <(expected_for "$s" | service_section) >/dev/null; then
        warn "nvidia-$s: $DROPIN differs from the expected content"; NEED+=("$s")
    else
        ok "nvidia-$s: $DROPIN in place"
    fi
    [[ -f $UNITDIR/nvidia-$s.service.d/50-cosmic-no-vt-switch.conf ]] \
        || echo "        (note: Pop's 50-cosmic-no-vt-switch.conf is gone here - harmless, 60- works without it)"
done

LAST=$(journalctl -t suspend --no-pager -q -n 50 2>/dev/null | grep -E 'nvidia-suspend\.service \(' | tail -1 || true)
[[ -n $LAST ]] && echo "  Last suspend branch: ${LAST#* suspend\[*\]: }"

if (( ${#NEED[@]} == 0 )); then
    hdr "Fix is in place - nothing to do."; exit 0
fi
[[ $MODE == check ]] && { hdr "Fix needed for: ${NEED[*]} - run without --check to reapply."; exit 1; }

hdr "[2/2] Reapplying"
echo "  Will back up the current drop-ins, rewrite $DROPIN for: ${NEED[*]},"
echo "  and reload systemd (needs sudo). Pop's 50- files are left untouched."
if [[ $MODE == ask ]]; then
    read -rp "  Proceed? [y/N] " a
    [[ $a == [yY] ]] || { echo "  Aborted - nothing changed."; exit 0; }
fi

# --- Back up current drop-in dirs, then install.
B=~/plasma-suspend-fix-backup-$(date +%Y%m%d-%H%M%S)
for s in "${SERVICES[@]}"; do
    d=$UNITDIR/nvidia-$s.service.d
    [[ -d $d ]] && mkdir -p "$B/nvidia-$s.service.d" && cp -a "$d/." "$B/nvidia-$s.service.d/"
done
ok "backed up current drop-ins to $B"

for s in "${NEED[@]}"; do
    sudo mkdir -p "$UNITDIR/nvidia-$s.service.d"
    expected_for "$s" | sudo tee "$UNITDIR/nvidia-$s.service.d/$DROPIN" >/dev/null
    sudo chmod 644 "$UNITDIR/nvidia-$s.service.d/$DROPIN"
done
sudo systemctl daemon-reload

# --- Verify the conditional is now the one effective ExecStart.
fail=0
for s in "${SERVICES[@]}"; do
    n=$(systemctl show -p ExecStart --value "nvidia-$s.service" | grep -c 'argv\[\]=' || true)
    if systemctl show -p ExecStart --value "nvidia-$s.service" | grep -q 'pgrep -x cosmic-comp' && (( n == 1 )); then
        ok "nvidia-$s: conditional ExecStart active"
    else
        warn "nvidia-$s: effective ExecStart is not the conditional one ($n commands) - check 'systemctl cat nvidia-$s.service'"; fail=1
    fi
done
(( fail )) && exit 1
hdr "Fix reapplied."
echo "Test: suspend/resume with HDMI, then: journalctl -b -t suspend | tail -3"
echo "Undo: sudo rm $UNITDIR/nvidia-{suspend,hibernate,suspend-then-hibernate}.service.d/$DROPIN && sudo systemctl daemon-reload"
