#!/bin/bash
# LAN scan with hostname resolution via system resolver (mdns4-enabled nsswitch)
# Usage: lanscan.sh [subnet]   -- if omitted, auto-detects active network as /24

SUBNET="$1"

if [ -z "$SUBNET" ]; then
    # Get IP + interface of default route
    read -r IFACE IP <<< "$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev")d=$(i+1);if($i=="src")s=$(i+1)}print d, s}')"
    if [ -z "$IP" ]; then
        echo "Could not auto-detect network. Specify subnet manually, e.g.: lanscan.sh 192.168.1.0/24"
        exit 1
    fi
    SUBNET="$(echo "$IP" | cut -d. -f1-3).0/24"
    echo "Auto-detected interface $IFACE, IP $IP -> scanning $SUBNET"
fi

echo "Scanning $SUBNET ..."

IPS=$(sudo nmap -sn "$SUBNET" -oG - | awk '/Up$/{print $2}')

printf "%-16s %s\n" "IP" "HOSTNAME"
printf "%-16s %s\n" "----" "--------"
for ip in $IPS; do
    name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    [ -z "$name" ] && name="(unknown)"
    printf "%-16s %s\n" "$ip" "$name"
done
