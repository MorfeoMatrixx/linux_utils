# smb-user-mount

Mounts an SMB/CIFS share at login, no `/etc/fstab` changes. Written for a
headless RPi node (user `pi`, already an admin/sudoer) mounting a share on
`wdmycloudex2.local`, but the pattern is generic.

`mount.cifs` needs `CAP_SYS_ADMIN`, so it can't run as a plain user without
either an `/etc/fstab` `user`-option entry, or `sudo`. Since `pi` already
has passwordless sudo on this node, the script just calls `sudo mount`
directly — no `/etc/fstab` changes, and no extra sudoers setup needed
either, since `sudo` already never prompts here.

## One-time setup (on the target Pi)

1. Create the mount point and a credentials file, both owned by `pi` —
   no root needed for either:
   ```bash
   mkdir -p /home/pi/wdnas1
   cat > /home/pi/.smbcredentials_wdnas <<'EOF'
   username=jlc
   password=<nas account password>
   EOF
   chmod 600 /home/pi/.smbcredentials_wdnas
   ```

2. Install the script:
   ```bash
   mkdir -p ~/bin
   cp mount-wdnas1.sh ~/bin/
   chmod +x ~/bin/mount-wdnas1.sh
   ```

3. Sanity check before wiring it into `.profile`:
   ```bash
   sudo /home/pi/bin/mount-wdnas1.sh
   mountpoint /home/pi/wdnas1
   sudo umount /home/pi/wdnas1
   ```

## Wiring into `.profile`

Add to `~/.profile`:
```bash
sudo /home/pi/bin/mount-wdnas1.sh &
```

- Backgrounded (`&`) so a slow/unreachable NAS never delays login — the
  script itself also caps the mount attempt at 15s via `timeout`.
- Since `pi`'s sudo is already passwordless, this `sudo` call never
  prompts — which matters specifically because it's backgrounded: a
  password prompt with no attached terminal would just hang forever
  otherwise.
- Idempotent — checks `mountpoint` first, so repeat logins (multiple SSH
  sessions, etc.) never double-mount or error out.

Failures and successes are logged via `logger` instead of printed to the
login shell (nothing is watching an unattended `.profile` invocation):
```bash
journalctl -t mount-wdnas1
# or
grep mount-wdnas1 /var/log/syslog
```
