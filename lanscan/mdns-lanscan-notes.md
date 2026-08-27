# mDNS Hostname Resolution Fix + lanscan.sh

## Problem
`ping hostname.local` resolves fine, but scanners (Nmap, Zenmap, Angry IP
Scanner) show only IP addresses, never hostnames. Even `avahi-browse` (mDNS
service discovery) only catches devices that actively announce a *service* —
it misses plain hosts that only answer direct `.local` name queries.

## Root Cause
`ping` uses glibc's NSS resolver, which by default doesn't include the mDNS
plugin in the lookup chain. Most CLI network tools bypass NSS entirely and
use their own resolver (Nmap) or don't do reverse lookups well over mDNS
(Avahi browsing).

## Fix — enable mDNS in the system resolver (nsswitch.conf)

Edit `/etc/nsswitch.conf` and change the `hosts:` line to:

```bash
sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
sudo sed -i 's/^hosts:.*/hosts:          files mdns_minimal [NOTFOUND=return] mdns4 dns/' /etc/nsswitch.conf
```

Make sure the mDNS NSS plugin is installed (usually pulled in with Avahi):

```bash
sudo apt update && sudo apt install -y libnss-mdns avahi-daemon avahi-utils
```

No reboot needed — takes effect immediately for new resolver calls.

**Verify:**

```bash
getent hosts pop-os.local
getent hosts 192.168.1.18      # reverse lookup, IP -> name
```

Once this is in place, *any* tool using the system resolver (`getent`,
`host`, many GUI apps) becomes mDNS-aware — not just `ping`.

**Apply this fix on:** any Debian/Ubuntu-based box where you want proper
`.local` name resolution — Pop!_OS, Raspberry Pi OS (uConsole, RPis), Mint.

## lanscan.sh — quick LAN scan with hostnames

Depends on the nsswitch fix above (uses `getent hosts` for reverse lookup)
plus `nmap` for host discovery.

```bash
sudo apt install -y nmap

sudo tee /usr/local/bin/lanscan.sh > /dev/null << 'EOF'
#!/bin/bash
# LAN scan with hostname resolution via system resolver (mdns4-enabled nsswitch)
SUBNET="${1:-192.168.1.0/24}"

echo "Scanning $SUBNET ..."

IPS=$(sudo nmap -sn "$SUBNET" -oG - | awk '/Up$/{print $2}')

printf "%-16s %s\n" "IP" "HOSTNAME"
printf "%-16s %s\n" "----" "--------"
for ip in $IPS; do
    name=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}')
    [ -z "$name" ] && name="(unknown)"
    printf "%-16s %s\n" "$ip" "$name"
done
EOF
sudo chmod +x /usr/local/bin/lanscan.sh
```

**Usage:**

```bash
sudo lanscan.sh 192.168.1.0/24
```

Installed in `/usr/local/bin` (not `~/bin`) so it works with `sudo` — sudo
resets PATH to a fixed secure_path that always includes `/usr/local/bin`.

## Known caveat
Devices that broadcast multiple mDNS names (e.g. Android's randomized
privacy hostname vs. an app's own service name — like a media/IoT app
advertising something like "FlowBox-Z3-...") may show a different alias
here than a full mDNS-service-browsing tool (e.g. yscan) would show. Not a
bug — just two different valid records for the same device. Android's
privacy hostname also rotates periodically, so don't rely on it staying
stable.

## Alternative tool
`yscan` (TUI) — does live mDNS service browsing, shows richer per-service
names/details. Good complement to lanscan.sh for deeper inspection of a
single device.
