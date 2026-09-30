#!/bin/bash
# pop-os-post-install-customizations.sh
# Rebuilds JLC's customizations on a FRESH Pop!_OS 24.04 install (Lenovo LOQ, NVIDIA
# hybrid): apps, KDE Plasma 5.27 alongside Cosmic, system fixes, our utilities from
# github.com/MorfeoMatrixx/linux_utils, dotfiles, and the Plasma look/behaviour.
#
# Every step checks first and only changes what's missing (safe to re-run).
# Run as your normal user (not root); it calls sudo where needed.
#
# Usage: pop-os-post-install-customizations.sh              summary, then per section: check + ask
#        pop-os-post-install-customizations.sh --check      report only, change nothing
#        pop-os-post-install-customizations.sh -y           apply everything without asking
#        pop-os-post-install-customizations.sh --only apt,flatpak
#        pop-os-post-install-customizations.sh --nopasswd-sudo   (opt-in, see summary)
#        pop-os-post-install-customizations.sh -h
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS=$HERE/assets
# Use the linux_utils checkout this script runs from; else clone it to ~/claude/utils
if [[ -d $HERE/../.git ]]; then REPO=$(cd "$HERE/.." && pwd); else REPO=$HOME/claude/utils; fi
REPO_URL=https://github.com/MorfeoMatrixx/linux_utils.git
SECTIONS=(repos apt flatpak extras system utils dotfiles plasma)
BK=$HOME/pop-os-post-install-backup-$(date +%Y%m%d-%H%M%S)

t() { tput "$@" 2>/dev/null || true; }   # no colors (not fatal) when $TERM is unset
GREEN=$(t setaf 2); YELLOW=$(t setaf 3); RED=$(t setaf 1); BOLD=$(t bold); RESET=$(t sgr0)
ok()   { echo "  ${RESET}${GREEN}${BOLD}OK${RESET}    $*"; }
note() { echo "  ${RESET}${BOLD}NOTE${RESET}  $*"; }
hdr()  { echo; echo "${RESET}${GREEN}${BOLD}$*${RESET}"; }
die()  { echo "${RESET}${RED}${BOLD}ERROR:${RESET} $*" >&2; exit 2; }

# act "description" cmd...  -> check pass: report as TODO; apply pass: run it.
act() {
    local desc=$1; shift
    NEEDED=1
    if (( CHECK )); then echo "  ${RESET}${YELLOW}${BOLD}TODO${RESET}  $desc"; return 0; fi
    echo "  ${RESET}${YELLOW}${BOLD}DO${RESET}    $desc"
    "$@"
}
bk() {   # back up a file (keeping its path) before changing it
    [[ -e $1 ]] || return 0
    mkdir -p "$BK"; sudo cp -a --parents "$1" "$BK/"
}
inst() {   # inst SRC DEST [MODE] [sudo] - copy if different
    local src=$1 dest=$2 mode=${3:-644} s=${4:-}
    if $s cmp -s "$src" "$dest" 2>/dev/null; then ok "$dest"; return; fi
    act "install $dest" bash -c "$s mkdir -p \"$(dirname "$dest")\" && $s install -m $mode \"$src\" \"$dest\""
}
kset() {   # kset FILE GROUP KEY VALUE - kwriteconfig5 if different
    [[ $(kreadconfig5 --file "$1" --group "$2" --key "$3") == "$4" ]] && { ok "$1 [$2] $3=$4"; return; }
    act "$1 [$2] $3=$4" kwriteconfig5 --file "$1" --group "$2" --key "$3" "$4"
}
ask() { [[ $MODE == yes ]] && return 1; read -rp "  $1 " REPLY; }   # returns 1 in -y mode (can't prompt)

summary() {
    cat <<EOF
${RESET}${GREEN}${BOLD}pop-os-post-install-customizations.sh${RESET} - JLC's setup on top of a fresh Pop!_OS 24.04

${BOLD}Sections${RESET} (run in this order)
  repos     GitHub CLI and Claude Desktop apt repositories
  apt       KDE Plasma 5.27 (sddm chosen as display manager, Cosmic kept) and all apt apps
  flatpak   MarkText, OrcaSlicer, PhotoCollage, Decoder, Angry IP Scanner, qBittorrent,
            NetPeek, cosmic-ext-connected
  extras    fastfetch (.deb), yscan (cargo), crontab-ui (npm + user service), Claude Code
  system    ${BOLD}MANDATORY NVIDIA suspend/wake fix${RESET} (50- Cosmic + 60- Plasma drop-ins via
            plasma-suspend-fix-redo.sh; verified at the end of every run), spd5118 blacklist,
            NAS CIFS automounts + credentials (prompted), /etc/hosts pins, sudoers rule
            for system76-power, Tilix vte.sh link. With --nopasswd-sudo: passwordless sudo
  utils     clone linux_utils to ~/claude/utils and install our utilities + launchers
  dotfiles  ~/.bashrc block, git identity, gh login
  plasma    ${BOLD}run from inside a Plasma (X11) session${RESET}: Tilix default + Ctrl+Alt+T,
            double-click, Breeze + cosmic-jlc purple focus frame, default apps, NAS bookmarks

${BOLD}Fresh-install order${RESET}
  1. From Cosmic: run all sections (plasma is skipped outside Plasma), then reboot.
  2. At the sddm login pick "Plasma" (not Wayland), log in, open Dolphin once, then run:
       pop-os-post-install-customizations.sh --only plasma

${BOLD}Options${RESET}
  (none)           summary, then per section: check (read-only), ask, apply
  --check          check only, change nothing
  -y               apply without asking (prompts for secrets are skipped)
  --only a,b       run only these sections
  --nopasswd-sudo  also allow sudo without password for $USER (convenient, less safe)
  -h               this summary
Backups of changed files go to ~/pop-os-post-install-backup-<timestamp>/.
EOF
}

# ---------------------------------------------------------------- sections
sec_repos() {
    hdr "[repos] Third-party apt repositories"
    local changed=0
    if [[ -f /etc/apt/sources.list.d/github-cli.list ]]; then ok "GitHub CLI repo"; else
        act "add GitHub CLI repo" bash -c '
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null'
        changed=1
    fi
    if [[ -f /etc/apt/sources.list.d/claude-desktop.list ]]; then ok "Claude Desktop repo"; else
        act "add Claude Desktop repo" bash -c "
            sudo install -m 644 '$ASSETS/claude-desktop-archive-keyring.asc' /usr/share/keyrings/claude-desktop-archive-keyring.asc
            echo 'deb [signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main' | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null"
        changed=1
    fi
    (( changed && !CHECK )) && sudo apt-get update
    return 0
}

APT_PKGS=(
    # Desktop: Plasma alongside Cosmic
    kde-plasma-desktop sddm dolphin dolphin-plugins kio-extras breeze-gtk-theme
    kate kwrite okular okular-extra-backends kdeconnect kcalc
    # KDE utilities (Spectacle registers PrtScr itself at the next Plasma login)
    kde-spectacle ark filelight krename kcolorchooser kcharselect ksystemlog kdiff3 krdc
    print-manager plasma-widgets-addons gwenview skanlite kio-gdrive
    # Terminal, editors, viewers
    tilix geany geany-plugins thonny gthumb vlc mpv
    # NAS / network
    cifs-utils smbclient gvfs-backends gvfs-fuse nfs-common nmap iw wavemon horst ethtool
    openssh-server sshpass
    # Dev / build
    build-essential git gh cargo npm python3-tk python3-pil.imagetk
    # Hardware / GPU
    system76-power nvidia-prime vainfo mesa-utils dfu-util rpi-imager
    # Media
    ffmpeg gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav
    sox libsox-fmt-all libportaudio2
    # OCR
    gimagereader tesseract-ocr tesseract-ocr-eng tesseract-ocr-spa tesseract-ocr-deu
    tesseract-ocr-fra tesseract-ocr-ita tesseract-ocr-por
    # Used by our utilities
    dialog pv xdotool librsvg2-bin mc htop
    # Apps from third-party repos
    claude-desktop
)
sec_apt() {
    hdr "[apt] Packages"
    local missing=() p
    for p in "${APT_PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if (( ${#missing[@]} == 0 )); then ok "all ${#APT_PKGS[@]} packages installed"; else
        # Preseed the display-manager question so kde-plasma-desktop picks sddm, not cosmic-greeter
        act "install ${#missing[@]} packages: ${missing[*]}" bash -c "
            echo 'sddm shared/default-x-display-manager select sddm' | sudo debconf-set-selections
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${missing[*]}"
    fi
    if (( !CHECK )) || dpkg -s sddm >/dev/null 2>&1; then
        if grep -q sddm /etc/X11/default-display-manager 2>/dev/null; then ok "display manager: sddm"; else
            act "make sddm the display manager" bash -c "
                echo 'sddm shared/default-x-display-manager select sddm' | sudo debconf-set-selections
                sudo dpkg-reconfigure -f noninteractive sddm"
        fi
    fi
    if dpkg -s google-chrome-stable >/dev/null 2>&1; then ok "google-chrome-stable"; else
        # Google's .deb adds and maintains its own apt repo
        act "install Google Chrome (.deb from dl.google.com)" bash -c '
            d=$(mktemp -d); curl -fsSL -o "$d/chrome.deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
            sudo apt-get install -y "$d/chrome.deb"; rm -rf "$d"'
    fi
}

FLATHUB_APPS=(com.github.marktext.marktext com.orcaslicer.OrcaSlicer io.github.adrienverge.PhotoCollage
              com.belmoussaoui.Decoder org.angryip.ipscan org.qbittorrent.qBittorrent io.github.zingytomato.netpeek)
COSMIC_APPS=(io.github.nwxnw.cosmic-ext-connected)
sec_flatpak() {
    hdr "[flatpak] Apps (user installation)"
    if ! command -v flatpak >/dev/null; then
        act "install flatpak" sudo apt-get install -y flatpak
        if (( CHECK )); then return 0; fi
    fi
    flatpak remotes --user --columns=name | grep -qx flathub && ok "remote flathub" || \
        act "add flathub remote" flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak remotes --user --columns=name | grep -qx cosmic && ok "remote cosmic" || \
        act "add cosmic remote" flatpak remote-add --user --if-not-exists cosmic https://apt.pop-os.org/cosmic/cosmic.flatpakrepo
    local a
    for a in "${FLATHUB_APPS[@]}"; do flatpak info "$a" >/dev/null 2>&1 && ok "$a" || act "install $a" flatpak install --user -y --noninteractive flathub "$a"; done
    for a in "${COSMIC_APPS[@]}";  do flatpak info "$a" >/dev/null 2>&1 && ok "$a" || act "install $a" flatpak install --user -y --noninteractive cosmic "$a"; done
}

sec_extras() {
    hdr "[extras] Software outside apt/flatpak"
    dpkg -s fastfetch >/dev/null 2>&1 && ok "fastfetch" || act "install fastfetch (latest .deb from GitHub)" bash -c '
        d=$(mktemp -d); curl -fsSL -o "$d/ff.deb" https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb
        sudo apt-get install -y "$d/ff.deb"; rm -rf "$d"'
    [[ -x $HOME/.cargo/bin/yscan ]] && ok "yscan" || act "cargo install yscan (+ /usr/local/bin link for sudo)" bash -c \
        'cargo install yscan && sudo ln -sf "$HOME/.cargo/bin/yscan" /usr/local/bin/yscan'
    [[ -x /usr/local/bin/crontab-ui ]] && ok "crontab-ui" || act "npm install -g crontab-ui" sudo npm install -g crontab-ui
    local unit=$HOME/.config/systemd/user/crontab-ui.service tmp
    tmp=$(mktemp); cat > "$tmp" <<'EOF'
[Unit]
Description=crontab-ui - web based crontab editor
After=network.target

[Service]
Environment=CRON_DB_PATH=%h/.crontab-ui
ExecStart=/usr/local/bin/crontab-ui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    inst "$tmp" "$unit"; rm -f "$tmp"
    systemctl --user is-enabled crontab-ui.service >/dev/null 2>&1 && ok "crontab-ui.service enabled" || \
        act "enable crontab-ui user service" bash -c 'systemctl --user daemon-reload && systemctl --user enable --now crontab-ui.service'
    command -v claude >/dev/null || [[ -x $HOME/.local/bin/claude ]] && ok "Claude Code" || \
        act "install Claude Code (official installer)" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    dpkg -s flashforgeui >/dev/null 2>&1 && ok "FlashForgeUI" || note "FlashForgeUI: install its .deb manually (no stable download URL)"
    ls "$HOME"/Apps/Flash_Studio*.AppImage >/dev/null 2>&1 && ok "Flash Studio AppImage" || note "Flash Studio: put its AppImage in ~/Apps manually"
}

ensure_repo() {
    [[ -d $REPO/.git ]] && return 0
    act "clone $REPO_URL -> $REPO" git clone "$REPO_URL" "$REPO"
}

sec_system() {
    hdr "[system] System fixes and config (/etc)"
    local tmp
    # spd5118 (DDR5 temp sensor) crashes suspend/resume on the LOQ 15IAX9
    if grep -qx 'blacklist spd5118' /etc/modprobe.d/blacklist-spd5118.conf 2>/dev/null; then ok "spd5118 blacklisted"; else
        act "blacklist spd5118 + update-initramfs (reboot afterwards)" bash -c \
            'echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf >/dev/null && sudo update-initramfs -u'
    fi
    # Tilix: /etc/profile.d/vte.sh must exist for cwd tracking (the .bashrc block sources it)
    [[ -e /etc/profile.d/vte.sh ]] && ok "/etc/profile.d/vte.sh" || \
        act "link /etc/profile.d/vte.sh -> vte-2.91.sh" sudo ln -s /etc/profile.d/vte-2.91.sh /etc/profile.d/vte.sh
    # NVIDIA suspend: 50- = VT-switch bypass Cosmic needs; 60- = make it conditional so Plasma X11 HDMI resumes
    if systemctl cat nvidia-suspend.service >/dev/null 2>&1; then
        local s before=$NEEDED; NEEDED=0
        for s in suspend hibernate suspend-then-hibernate; do
            inst "$ASSETS/nvidia/nvidia-$s-50-cosmic-no-vt-switch.conf" \
                 "/etc/systemd/system/nvidia-$s.service.d/50-cosmic-no-vt-switch.conf" 644 sudo
        done
        (( NEEDED && !CHECK )) && sudo systemctl daemon-reload
        (( NEEDED )) || NEEDED=$before
        ensure_repo
        local R=$REPO/plasma-suspend-fix/plasma-suspend-fix-redo.sh rc=0
        if [[ -x $R ]]; then
            "$R" --check >/dev/null 2>&1 || rc=$?
            case $rc in
                0) ok "60-plasma-vt-switch drop-ins" ;;
                1) act "install 60-plasma-vt-switch drop-ins" "$R" -y ;;
                *) note "plasma-suspend-fix-redo.sh refused (NVIDIA sleep mechanism changed?) - investigate" ;;
            esac
        else note "60- drop-ins: re-run after the repo is cloned"; fi
    else
        note "nvidia-suspend.service not found - NVIDIA driver missing? Skipping suspend drop-ins"
    fi
    # NAS: CIFS automounts (x-gvfs-hide keeps them out of Dolphin's Remote/devices list;
    # use the plain bookmarks from the plasma section instead)
    local share mp line
    for share in Public:wdnas_public public_2:wdnas_public2; do
        mp=/mnt/${share#*:}
        line="//wdmycloudex2.local/${share%%:*}  $mp  cifs  _netdev,x-systemd.automount,x-systemd.idle-timeout=60,x-systemd.mount-timeout=10,noauto,nofail,soft,x-gvfs-hide,credentials=/etc/.smbcredentials_wdnas,uid=$(id -u),gid=$(id -g),iocharset=utf8,vers=3.0  0  0"
        if grep -qE "[[:space:]]$mp[[:space:]]" /etc/fstab; then ok "fstab $mp"; else
            act "fstab: automount $mp" bash -c "$(declare -f bk); BK='$BK'; bk /etc/fstab; sudo mkdir -p '$mp'; echo '$line' | sudo tee -a /etc/fstab >/dev/null; sudo systemctl daemon-reload; sudo systemctl restart remote-fs.target"
        fi
    done
    if sudo test -f /etc/.smbcredentials_wdnas; then ok "/etc/.smbcredentials_wdnas"; else
        NEEDED=1
        if (( CHECK )); then echo "  ${RESET}${YELLOW}${BOLD}TODO${RESET}  create /etc/.smbcredentials_wdnas (prompted)"
        elif ask "NAS SMB username (empty = skip):" && [[ -n $REPLY ]]; then
            local u=$REPLY pw; read -rsp "  NAS SMB password: " pw; echo
            printf 'username=%s\npassword=%s\n' "$u" "$pw" | sudo tee /etc/.smbcredentials_wdnas >/dev/null
            sudo chmod 600 /etc/.smbcredentials_wdnas; ok "wrote /etc/.smbcredentials_wdnas (root, 600)"
        else note "create /etc/.smbcredentials_wdnas yourself (username=/password= lines, chmod 600)"; fi
    fi
    # /etc/hosts pins (NAS mDNS renamed itself once; router has DHCP bindings for both)
    local h
    for h in "192.168.1.9  wdmycloudex2.local wdmycloudex2   # NAS pinned (mDNS rename workaround)" \
             "192.168.1.131 pidp-11.local"; do
        if grep -qE "^[0-9.]+[[:space:]]+$(awk '{print $2}' <<<"$h" | sed 's/\./\\./g')([[:space:]]|$)" /etc/hosts; then ok "/etc/hosts $(awk '{print $2}' <<<"$h")"; else
            act "/etc/hosts: $h" bash -c "$(declare -f bk); BK='$BK'; bk /etc/hosts; echo '$h' | sudo tee -a /etc/hosts >/dev/null"
        fi
    done
    # sudoers: validated with visudo before installing
    sudoers_rule() {   # sudoers_rule FILE LINE
        if sudo test -f "$1" && sudo grep -qxF "$2" "$1"; then ok "$1"; return; fi
        tmp=$(mktemp); echo "$2" > "$tmp"
        act "sudoers: $1" bash -c "sudo visudo -cf '$tmp' >/dev/null && sudo install -m 440 -o root -g root '$tmp' '$1'"
        rm -f "$tmp"
    }
    sudoers_rule /etc/sudoers.d/system76-power-nopasswd "%sudo ALL=(ALL) NOPASSWD: /usr/bin/system76-power"
    if (( NOPASSWD )); then sudoers_rule "/etc/sudoers.d/nopasswd-$USER" "$USER ALL=(ALL) NOPASSWD: ALL"
    else note "passwordless sudo not requested (use --nopasswd-sudo)"; fi
}

sec_utils() {
    hdr "[utils] Our utilities (~/claude/utils -> ~/bin, ~/.local/bin)"
    ensure_repo
    [[ -d $REPO/.git ]] || { note "repo not cloned yet - nothing more to check"; return 0; }
    local f
    for f in backup2nas/dir-backup.sh backup2nas/sd-backup.sh grok-sync/grok-sync.sh grok-sync/grok-sync-launch.sh \
             grok-dedup/grok-dedup.sh grok-dedup/grok-dedup-ui.py grok-dedup/grok-dedup-launch.sh \
             linux-sync/linux-sync.sh linux-sync/linux-sync-launch.sh linux-sync/linux-sync-cron-check.sh \
             linux-sync/linux-sync-status.sh linux-nodes-status/linux-nodes-status.sh ssh-passwordless-setup/ssh-node-setup.sh; do
        inst "$REPO/$f" "$HOME/bin/$(basename "$f")" 755
    done
    inst "$REPO/backup2nas/dir-backup.dialogrc" "$HOME/bin/dir-backup.dialogrc"
    inst "$REPO/plasma-suspend-fix/plasma-suspend-fix-redo.sh" "$HOME/.local/bin/plasma-suspend-fix-redo.sh" 755
    # Utilities with their own installers (they also set up /usr/local/bin links / sudoers)
    [[ -L /usr/local/bin/lanscan.sh ]] && cmp -s "$REPO/lanscan/lanscan.sh" "$HOME/bin/lanscan.sh" && ok "lanscan" || \
        act "lanscan (install-lanscan.sh)" bash "$REPO/lanscan/install-lanscan.sh"
    cmp -s "$REPO/gpu-mode/gpu-mode.py" "$HOME/.local/bin/gpu-mode" && ok "gpu-mode" || \
        act "gpu-mode (gpu-mode-install.sh)" bash "$REPO/gpu-mode/gpu-mode-install.sh"
    [[ -L /usr/local/bin/set-default-apps.sh ]] && cmp -s "$REPO/default-apps/set-default-apps.sh" "$HOME/bin/set-default-apps.sh" && ok "set-default-apps.sh" || \
        act "set-default-apps.sh (install-default-apps.sh)" bash "$REPO/default-apps/install-default-apps.sh"
    # Icons + launchers (repo .desktop files hardcode /home/jlc; rewrite to this $HOME)
    local I=$HOME/.local/share/icons n
    inst "$REPO/grok-sync/grok-sync.png" "$I/grok-sync.png"
    inst "$REPO/linux-sync/linux-sync.png" "$I/linux-sync.png"
    inst "$REPO/crontab-ui/crontab-ui-icon.svg" "$I/hicolor/scalable/apps/crontab-ui.svg"
    inst "$REPO/gpu-mode/gpu-mode.svg" "$I/hicolor/scalable/apps/gpu-mode.svg"
    for n in 16 32 48 64 128 256; do inst "$REPO/grok-dedup/icons/grok-dedup-$n.png" "$I/hicolor/${n}x${n}/apps/grok-dedup.png"; done
    local d tmp before=$NEEDED; NEEDED=0
    for d in grok-sync/grok-sync grok-dedup/grok-dedup linux-sync/linux-sync crontab-ui/crontab-ui gpu-mode/gpu-mode; do
        tmp=$(mktemp); sed "s|/home/jlc|$HOME|g" "$REPO/$d.desktop" > "$tmp"
        inst "$tmp" "$HOME/.local/share/applications/$(basename "$d").desktop"; rm -f "$tmp"
    done
    (( NEEDED && !CHECK )) && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    (( NEEDED )) || NEEDED=$before
}

sec_dotfiles() {
    hdr "[dotfiles] ~/.bashrc, git, gh"
    if grep -q 'JLC CUSTOMIZATIONS' "$HOME/.bashrc" 2>/dev/null; then ok "~/.bashrc JLC block"; else
        act "append JLC block to ~/.bashrc" bash -c "$(declare -f bk); BK='$BK'; bk '$HOME/.bashrc'; cat >> '$HOME/.bashrc'" <<'EOF'

# >>> JLC CUSTOMIZATIONS >>>
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
# Tilix: report the cwd so new tabs/splits open in the same directory
if [ -n "$TILIX_ID" ] || [ -n "$VTE_VERSION" ]; then
    [ -f /etc/profile.d/vte.sh ] && source /etc/profile.d/vte.sh
fi
# Hybrid GPU: prefer Intel VA-API decoders over NVIDIA's in GStreamer (smooth video playback)
export GST_PLUGIN_FEATURE_RANK="nvh264dec:0,nvh265dec:0,nvav1dec:0,vah264dec:256,vaapih264dec:256"
export CRON_DB_PATH=~/.crontab-ui
# <<< JLC CUSTOMIZATIONS <<<
EOF
    fi
    [[ $(git config --global user.name || true) == jlc ]] && ok "git user.name" || act "git user.name=jlc" git config --global user.name jlc
    if [[ -n $(git config --global user.email || true) ]]; then ok "git user.email"; else
        NEEDED=1
        if (( CHECK )); then echo "  ${RESET}${YELLOW}${BOLD}TODO${RESET}  git user.email (prompted)"
        elif ask "git email (empty = skip):" && [[ -n $REPLY ]]; then git config --global user.email "$REPLY"; ok "git user.email set"
        else note "set it later: git config --global user.email you@example.com"; fi
    fi
    if gh auth status >/dev/null 2>&1; then ok "gh logged in"; else
        NEEDED=1
        if (( CHECK )); then echo "  ${RESET}${YELLOW}${BOLD}TODO${RESET}  gh auth login + gh auth setup-git (interactive)"
        elif [[ $MODE != yes ]]; then gh auth login && gh auth setup-git || note "gh login skipped - run later: gh auth login && gh auth setup-git"
        else note "run later: gh auth login && gh auth setup-git"; fi
    fi
}

sec_plasma() {
    hdr "[plasma] Plasma look and behaviour"
    if [[ ${XDG_CURRENT_DESKTOP:-} != *KDE* ]]; then
        note "not in a Plasma session - log into Plasma (X11) and run: $(basename "$0") --only plasma"
        return 0
    fi
    local K=$HOME/.config/kdeglobals
    kset kdeglobals General TerminalApplication tilix
    kset kdeglobals General TerminalService com.gexperts.Tilix.desktop
    kset kdeglobals KDE SingleClick false
    [[ $(gsettings get com.gexperts.Tilix.Settings window-style) == "'disable-csd'" ]] && ok "Tilix uses KWin frame" || \
        act "Tilix window-style=disable-csd (restart Tilix)" gsettings set com.gexperts.Tilix.Settings window-style disable-csd
    # Ctrl+Alt+T -> Tilix. Konsole's .desktop claims it; kglobalaccel owns the file, so stop it while editing.
    if [[ $(kreadconfig5 --file kglobalshortcutsrc --group com.gexperts.Tilix.desktop --key _launch) == Ctrl+Alt+T,* ]]; then ok "Ctrl+Alt+T -> Tilix"; else
        act "Ctrl+Alt+T -> Tilix (Konsole unbound)" bash -c "$(declare -f bk); BK='$BK'; bk '$HOME/.config/kglobalshortcutsrc'
            systemctl --user stop plasma-kglobalaccel.service
            kwriteconfig5 --file kglobalshortcutsrc --group org.kde.konsole.desktop --key _launch 'none,Ctrl+Alt+T,Konsole'
            kwriteconfig5 --file kglobalshortcutsrc --group com.gexperts.Tilix.desktop --key _k_friendly_name Tilix
            kwriteconfig5 --file kglobalshortcutsrc --group com.gexperts.Tilix.desktop --key _launch 'Ctrl+Alt+T,none,Tilix'
            systemctl --user start plasma-kglobalaccel.service"
    fi
    # Window decoration: Breeze, 4px border
    local before=$NEEDED; NEEDED=0
    kset kwinrc org.kde.kdecoration2 library org.kde.breeze
    kset kwinrc org.kde.kdecoration2 theme Breeze
    kset kwinrc org.kde.kdecoration2 BorderSize Normal
    kset kwinrc org.kde.kdecoration2 BorderSizeAuto false
    # cosmic-jlc: purple (196,133,216) active title bar + frame, black title text; inactive dark.
    # Gotchas: a [Colors:Header] group makes KWin ignore [WM]; frame/inactiveFrame aren't copied
    # by plasma-apply-colorscheme; KWin only reloads colours on a kconfig ConfigChanged signal.
    inst "$ASSETS/cosmic-jlc.colors" "$HOME/.local/share/color-schemes/cosmic-jlc.colors"
    [[ $(kreadconfig5 --file kdeglobals --group General --key ColorScheme) == cosmic-jlc ]] && ok "colour scheme cosmic-jlc" || \
        act "apply colour scheme cosmic-jlc" bash -c "$(declare -f bk); BK='$BK'; bk '$K'; plasma-apply-colorscheme cosmic-jlc"
    kset kdeglobals WM frame 196,133,216
    kset kdeglobals WM inactiveFrame 44,44,44
    if grep -q '^\[Colors:Header\]' "$K" 2>/dev/null; then
        act "remove [Colors:Header] groups from kdeglobals" python3 - "$K" <<'PY'
import sys
p = sys.argv[1]; out = []; skip = False
for line in open(p).read().splitlines(keepends=True):
    s = line.strip()
    if s.startswith('['):
        skip = s in ("[Colors:Header]", "[Colors:Header][Inactive]")
    if not skip:
        out.append(line)
open(p, 'w').write(''.join(out))
PY
    else ok "no [Colors:Header] in kdeglobals"; fi
    if (( NEEDED && !CHECK )); then
        gdbus emit --session --object-path /kdeglobals --signal org.kde.kconfig.notify.ConfigChanged \
            "{'WM': [b'activeBackground', b'frame', b'inactiveFrame']}" >/dev/null
        qdbus org.kde.KWin /KWin reconfigure >/dev/null
    fi
    (( NEEDED )) || NEEDED=$before
    # Default apps (KWrite, MarkText, Okular, Dolphin, gThumb, mpv, Chrome)
    if [[ $(xdg-mime query default text/plain) == org.kde.kwrite.desktop && $(xdg-mime query default text/markdown) == com.github.marktext.marktext.desktop \
          && $(xdg-mime query default application/pdf) == okularApplication_pdf.desktop && $(xdg-mime query default inode/directory) == org.kde.dolphin.desktop ]]; then
        ok "default apps"
    else act "default apps (set-default-apps.sh)" bash -c "$(declare -f bk); BK='$BK'; bk '$HOME/.config/mimeapps.list'; bash '$REPO/default-apps/set-default-apps.sh' >/dev/null"; fi
    # Dolphin sidebar: plain NAS folder bookmarks (the fstab x-gvfs-hide hides the device entries)
    local X=$HOME/.local/share/user-places.xbel
    if [[ ! -f $X ]]; then note "open Dolphin once (creates its Places file), then re-run --only plasma"
    elif grep -q 'href="file:///mnt/wdnas_public2"' "$X" && grep -q 'href="file:///mnt/wdnas_public"' "$X"; then ok "Dolphin NAS bookmarks"
    elif pgrep -x dolphin >/dev/null; then note "close Dolphin, then re-run --only plasma to add the NAS bookmarks"
    else
        act "Dolphin bookmarks for /mnt/wdnas_public{,2}" bash -c "$(declare -f bk); BK='$BK'; bk '$X'; python3 - '$X'" <<'PY'
import sys, time
p = sys.argv[1]; s = open(p).read(); add = ''
for i, name in enumerate(('wdnas_public', 'wdnas_public2')):
    href = f'file:///mnt/{name}'
    if f'href="{href}"' in s:
        continue
    add += f''' <bookmark href="{href}">
  <title>{name}</title>
  <info>
   <metadata owner="http://freedesktop.org">
    <bookmark:icon name="folder-network"/>
   </metadata>
   <metadata owner="http://www.kde.org">
    <ID>{int(time.time())}/{i}</ID>
   </metadata>
  </info>
 </bookmark>
'''
open(p, 'w').write(s.replace('</xbel>', add + '</xbel>', 1))
PY
    fi
}

# ---------------------------------------------------------------- main
MODE=ask; ONLY=""; NOPASSWD=0
while (( $# )); do
    case $1 in
        --check) MODE=check ;;
        -y|--yes) MODE=yes ;;
        --only) ONLY=${2:-}; shift ;;
        --nopasswd-sudo) NOPASSWD=1 ;;
        -h|--help) summary; exit 0 ;;
        *) echo "Usage: $(basename "$0") [--check | -y] [--only a,b] [--nopasswd-sudo] [-h]"; exit 2 ;;
    esac
    shift
done
(( EUID == 0 )) && die "run as your normal user, not root (it uses sudo where needed)"
command -v kreadconfig5 >/dev/null || [[ $ONLY != *plasma* ]] || die "kreadconfig5 missing - run the apt section first"

RUN=("${SECTIONS[@]}")
if [[ -n $ONLY ]]; then
    IFS=, read -ra RUN <<<"$ONLY"
    for s in "${RUN[@]}"; do [[ " ${SECTIONS[*]} " == *" $s "* ]] || die "unknown section '$s' (valid: ${SECTIONS[*]})"; done
fi
[[ $MODE == ask ]] && summary
[[ $MODE != check ]] && sudo -v   # ask for the sudo password once, up front

for s in "${RUN[@]}"; do
    case $MODE in
        check) CHECK=1 NEEDED=0; "sec_$s" ;;
        yes)   CHECK=0 NEEDED=0; "sec_$s" ;;
        ask)   CHECK=1 NEEDED=0; "sec_$s"
               if (( NEEDED )); then
                   read -rp "  Apply [$s]? [y/N] " a
                   if [[ $a == [yY] ]]; then CHECK=0 NEEDED=0; "sec_$s"; else echo "  Skipped - nothing changed."; fi
               fi ;;
    esac
done

# MANDATORY: without the 60- drop-ins, an HDMI monitor on the NVIDIA GPU stays dark after
# suspend/resume in Plasma X11 (Pop's 50- Cosmic drop-ins skip the VT switch KWin needs).
hdr "Mandatory check: NVIDIA suspend/wake fix (plasma-suspend-fix-redo.sh)"
FIX=$REPO/plasma-suspend-fix/plasma-suspend-fix-redo.sh; FIXRC=0
if [[ -x $FIX ]]; then "$FIX" --check >/dev/null 2>&1 || FIXRC=$?; else FIXRC=3; fi
case $FIXRC in
    0) ok "NVIDIA suspend/wake fix is in place" ;;
    1) echo "  ${RESET}${RED}${BOLD}MISSING${RESET} NVIDIA suspend/wake fix - run: $(basename "$0") --only system" ;;
    2) echo "  ${RESET}${RED}${BOLD}BLOCKED${RESET} plasma-suspend-fix-redo.sh refused (NVIDIA driver or its sleep script changed) - investigate before suspending" ;;
    3) echo "  ${RESET}${RED}${BOLD}MISSING${RESET} $FIX not found - run: $(basename "$0") --only utils,system" ;;
esac

hdr "Done."
[[ -d $BK ]] && echo "Backups of changed files: $BK"
cat <<EOF
Manual follow-ups (not scriptable):
  - Restore ~/.ssh (keys + config) and, if wanted, ~/.crontab-ui (crontab-ui job DB) from backup.
  - FlashForgeUI .deb and the Flash Studio AppImage (~/Apps) if you still use them.
  - Reboot after the system section (spd5118 blacklist + initramfs, sddm).
  - In Plasma: run --only plasma, restart Tilix, then test suspend/resume with the HDMI monitor
    (journalctl -b -t suspend | tail -3 should show "non-COSMIC: normal VT switch").
EOF
(( FIXRC == 0 )) || exit 1
