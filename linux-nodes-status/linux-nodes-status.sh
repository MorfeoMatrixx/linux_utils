#!/bin/bash
set -uo pipefail
# Connects to every host defined in ~/.ssh/config and displays a fleet status
# table (nodes as columns, properties as rows) in vintage green-phosphor style.

SSH_CONFIG="${HOME}/.ssh/config"
SSH_TIMEOUT=6
TMPDIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMPDIR"
    # Defensive reset: background ssh jobs sharing our controlling tty's stdin
    # can leave it in a bad state (raw mode / mouse-tracking escape codes
    # stuck on) if one gets killed by the timeout mid-negotiation.
    stty sane 2>/dev/null
    { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?25h' > /dev/tty; } 2>/dev/null
}
trap cleanup EXIT

# Remote probe script: POSIX sh only (must run under bash, dash or busybox ash).
read -r -d '' REMOTE_PROBE <<'REMOTE_EOF' || true
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$IP" ]; then
    IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
fi
if [ -z "$IP" ]; then
    # no iproute2 (e.g. TinyCore/busybox): fall back to ifconfig
    IP=$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?[0-9]{1,3}(\.[0-9]{1,3}){3}' \
        | grep -v '127\.0\.0\.1' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1)
fi
MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
if [ -n "$MODEL" ]; then
    # "Raspberry Pi 3 Model B Plus Rev 1.3" -> "RPi 3B+ R1.3"
    MODEL=$(echo "$MODEL" | sed \
        -e 's/Raspberry Pi/RPi/' \
        -e 's/ Model \([A-Za-z]\)/\1/' \
        -e 's/ Plus/+/' \
        -e 's/Rev /R/')
else
    CPU=$(lscpu 2>/dev/null | awk -F: '/^Model name/{print $2}' | sed 's/^ *//')
    [ -z "$CPU" ] && CPU=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    if [ -n "$CPU" ]; then
        # "12th Gen Intel(R) Core(TM) i5-12450HX" -> "i5-12450HX"
        MODEL=$(echo "$CPU" | awk '{print $NF}')
    else
        MODEL=$(uname -m)
    fi
fi
RAM=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
[ -z "$RAM" ] && RAM=$(awk '/MemTotal/{printf "%.1fG", $2/1024/1024}' /proc/meminfo 2>/dev/null)
STORAGE=$(df -h / 2>/dev/null | awk 'NR==2{print $2"B ("$5"U)"}')
if [ "$(awk '$2=="/"{print $3; exit}' /proc/mounts 2>/dev/null)" = "tmpfs" ]; then
    # root is RAM-backed (e.g. TinyCore/piCorePlayer): report the first real
    # persistent block-device mount instead of the tmpfs size
    REAL_FS=$(df -h 2>/dev/null | awk '$1 ~ /^\/dev\// && $6 !~ /^\/tmp\// {print $2, $5; exit}')
    [ -n "$REAL_FS" ] && STORAGE=$(echo "$REAL_FS" | awk '{print $1"B ("$2"U)"}')
fi
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -1)
if [ -z "$IFACE" ]; then
    # no iproute2: default route's interface is the first column of the
    # /proc/net/route entry whose destination is 00000000
    IFACE=$(awk '$2 == "00000000" {print $1; exit}' /proc/net/route 2>/dev/null)
fi
CONN="unknown"
if [ -n "$IFACE" ]; then
    if [ -d "/sys/class/net/$IFACE/wireless" ]; then
        FREQ=$(iw dev "$IFACE" link 2>/dev/null | awk '/freq:/{print $2; exit}')
        [ -z "$FREQ" ] && FREQ=$(iwconfig "$IFACE" 2>/dev/null | awk -F'Frequency:' '/Frequency/{split($2,a," "); print a[1]; exit}')
        case "$FREQ" in
            2.4*|24[0-9][0-9]*) CONN="WiFi 2.4GHz" ;;
            5.*|5[0-9][0-9][0-9]*) CONN="WiFi 5GHz" ;;
            *) CONN="WiFi" ;;
        esac
    else
        SPEED=""
        # sysfs "speed" is only meaningful for a real NIC (one with a
        # /device symlink); veth/container interfaces report a bogus
        # default (usually 10000) with no actual link negotiation.
        if [ -e "/sys/class/net/$IFACE/device" ]; then
            SPEED=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null)
            if [ -z "$SPEED" ] || [ "$SPEED" -le 0 ] 2>/dev/null; then
                SPEED=$(ethtool "$IFACE" 2>/dev/null | awk -F: '/Speed/{gsub(/[^0-9]/,"",$2); print $2}')
            fi
        fi
        if [ -n "$SPEED" ] && [ "$SPEED" -ge 1000 ] 2>/dev/null; then
            CONN="ETH $((SPEED / 1000))Gbps"
        elif [ -n "$SPEED" ]; then
            CONN="ETH ${SPEED}Mbps"
        else
            CONN="ETH"
        fi
    fi
fi
OS=$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
[ -z "$OS" ] && OS=$(uname -sr)
# "Debian GNU/Linux 13 (trixie)" -> "Debian 13 Trixie"
CODENAME=$(printf '%s' "$OS" | sed -n 's/.*(\([A-Za-z0-9._-]*\)).*/\1/p')
OS=$(printf '%s' "$OS" | sed \
    -e 's/([^)]*)//' \
    -e 's/GNU\/Linux //' \
    -e 's/Linux //' \
    -e 's/ v\([0-9]\)/ \1/' \
    -e 's/ *$//')
if [ -n "$CODENAME" ]; then
    OS="$OS $(printf '%s' "$CODENAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
fi
# total uptime in days (avoids locale-dependent `uptime -p` wording)
UPSEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
if [ -n "$UPSEC" ]; then
    UPTIME=$(awk -v s="$UPSEC" 'BEGIN{printf "%.1fd", s/86400}')
else
    UPTIME=$(uptime 2>/dev/null | sed 's/^ *//')
fi
printf 'IP=%s\nMODEL=%s\nRAM=%s\nSTORAGE=%s\nCONN=%s\nOS=%s\nUPTIME=%s\n' \
    "$IP" "$MODEL" "$RAM" "$STORAGE" "$CONN" "$OS" "$UPTIME"
REMOTE_EOF

# Extract canonical (first-alias) host names from the ssh config, skipping
# wildcard/pattern entries that aren't real machines.
mapfile -t HOSTS < <(awk '/^Host[ \t]/{print $2}' "$SSH_CONFIG" | grep -v '[*?]')

if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "No hosts found in $SSH_CONFIG"
    exit 1
fi

echo "Querying ${#HOSTS[@]} host(s) from $SSH_CONFIG ..."

for host in "${HOSTS[@]}"; do
    (
        out=$(timeout "$((SSH_TIMEOUT + 4))" ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" \
            -o StrictHostKeyChecking=accept-new "$host" "$REMOTE_PROBE" </dev/null 2>"$TMPDIR/$host.err")
        if [ -z "$out" ]; then
            reason="Unreachable"
            if grep -qi 'Permission denied' "$TMPDIR/$host.err"; then
                reason="auth failed"
            fi
            echo "UNREACHABLE=$reason" > "$TMPDIR/$host"
        else
            echo "$out" > "$TMPDIR/$host"
        fi
    ) &
done
wait

declare -A DATA
FIELDS=(IP MODEL RAM STORAGE CONN OS UPTIME)
LABELS=("IP" "Model/CPU" "RAM" "Storage" "Connection" "OS" "Uptime")

for host in "${HOSTS[@]}"; do
    file="$TMPDIR/$host"
    if grep -q '^UNREACHABLE=' "$file" 2>/dev/null; then
        reason=$(sed -n 's/^UNREACHABLE=//p' "$file")
        DATA["$host,UNREACHABLE"]=1
        DATA["$host,IP"]="($reason)"
        for f in "${FIELDS[@]}"; do
            [ "$f" = "IP" ] && continue
            DATA["$host,$f"]=""
        done
        continue
    fi
    while IFS='=' read -r key val; do
        DATA["$host,$key"]="$val"
    done < "$file"
    for f in "${FIELDS[@]}"; do
        [ -z "${DATA["$host,$f"]+x}" ] && DATA["$host,$f"]="-"
    done
done

# --- vintage green-phosphor table rendering (hosts=rows, properties=columns),
# box-drawing borders + a flat drop-shadow, Midnight Commander style. ---
GREEN=$(tput setaf 2 2>/dev/null || true)
BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

ALIAS_LABEL="ALIAS"
MAX_COL_W=28
SHADOW_W=2

cell() {
    local text="$1" width="$2"
    text="${text:0:$width}"
    printf "%-${width}s" "$text"
}

# Size each column to its widest value (label or data), capped so one long
# Model/OS string doesn't blow out the whole table.
ALIAS_W=${#ALIAS_LABEL}
for host in "${HOSTS[@]}"; do
    [ "${#host}" -gt "$ALIAS_W" ] && ALIAS_W=${#host}
done
[ "$ALIAS_W" -gt "$MAX_COL_W" ] && ALIAS_W=$MAX_COL_W

declare -a COL_W
for i in "${!FIELDS[@]}"; do
    f="${FIELDS[$i]}"
    w=${#LABELS[$i]}
    for host in "${HOSTS[@]}"; do
        v="${DATA["$host,$f"]}"
        [ "${#v}" -gt "$w" ] && w=${#v}
    done
    [ "$w" -gt "$MAX_COL_W" ] && w=$MAX_COL_W
    COL_W[$i]=$w
done

ALL_W=("$ALIAS_W" "${COL_W[@]}")
NCOLS=${#ALL_W[@]}
BOX_W=$((NCOLS + 1))
for w in "${ALL_W[@]}"; do BOX_W=$((BOX_W + w + 2)); done

dashes() { printf '─%.0s' $(seq 1 "$1"); }
shade() { printf '▒%.0s' $(seq 1 "$1"); }

hborder() {
    local left="$1" mid="$2" right="$3"
    printf "%s" "$left"
    for i in "${!ALL_W[@]}"; do
        dashes "$((ALL_W[i] + 2))"
        [ "$i" -lt "$((NCOLS - 1))" ] && printf "%s" "$mid" || printf "%s" "$right"
    done
}

# Right-hand shadow strip after a content/border line (every row except the
# very top border, which sits flush with no shadow beside it).
shadow_line() {
    printf "%s%s%s\n" "$RESET" "$DIM$GREEN" "$(shade "$SHADOW_W")"
}

printf "%s%s" "$GREEN" "$BOLD"
hborder "┌" "┬" "┐"
printf "\n"

printf "│ "
cell "$ALIAS_LABEL" "$ALIAS_W"
for i in "${!FIELDS[@]}"; do
    printf " │ "
    cell "${LABELS[$i]}" "${COL_W[$i]}"
done
printf " │"
shadow_line

printf "%s%s" "$GREEN" "$BOLD"
hborder "├" "┼" "┤"
shadow_line

for host in "${HOSTS[@]}"; do
    if [ -n "${DATA["$host,UNREACHABLE"]:-}" ]; then
        printf "%s%s%s" "$RESET" "$GREEN" "$DIM"
    else
        printf "%s%s" "$RESET" "$GREEN"
    fi
    printf "│ "
    cell "$host" "$ALIAS_W"
    for i in "${!FIELDS[@]}"; do
        f="${FIELDS[$i]}"
        printf " │ "
        cell "${DATA["$host,$f"]}" "${COL_W[$i]}"
    done
    printf " │"
    shadow_line
done

printf "%s%s" "$GREEN" "$BOLD"
hborder "└" "┴" "┘"
shadow_line

# Bottom shadow strip: indented by SHADOW_W to align under the right-hand
# strip above, spanning the box width.
printf "%*s" "$SHADOW_W" ""
printf "%s%s%s\n" "$DIM$GREEN" "$(shade "$BOX_W")" "$RESET"
