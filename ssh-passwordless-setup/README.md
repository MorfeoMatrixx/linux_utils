# Passwordless SSH setup

How to set up key-based SSH login to avoid typing a password every time.

## 1. Generate a key pair (once per machine)

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
```

Accept the default path (`~/.ssh/id_ed25519`). Leave the passphrase empty for
zero prompts, or set one and use `ssh-agent`/`ssh-add` to cache it per session.

## 2. Copy the public key to each remote

```bash
ssh-copy-id <user>@<host>
```

Prompts for the remote's password once, then appends your public key to
`~/.ssh/authorized_keys` on that host.

If `ssh-copy-id` isn't available:

```bash
cat ~/.ssh/id_ed25519.pub | ssh <user>@<host> \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## 3. Add host aliases to `~/.ssh/config`

```
Host myserver
    HostName myserver.example.com
    User someuser
    Port 22          # only needed if non-default
```

Then just `ssh myserver`.

## Special case: Home Assistant OS (HAOS)

HAOS has no general-purpose `sshd` on port 22 by default — it's an appliance
OS managed via the Supervisor. To get SSH access:

1. **Settings → Add-ons → Add-on Store** in the HA web UI.
2. Add the community repo if not already present (store ⋮ menu →
   Repositories → `https://github.com/hassio-addons/repository`).
3. Install **Advanced SSH & Web Terminal** (gives real root/host shell,
   unlike the official "Terminal & SSH" add-on which only gives the
   `ha` CLI in a container).
4. In its **Configuration** tab:
   - Paste your public key (`cat ~/.ssh/id_ed25519.pub`) into the
     `authorized_keys` field.
   - Note the configured port — check the actual value, don't assume
     the documented default (`22222`); this instance ended up on `22`.
5. Start the add-on, then add it to `~/.ssh/config`:

```
Host homeassistant
    HostName homeassistant.local
    User root
    Port 22       # match whatever the add-on config actually says
```

If `ssh` gives "Connection refused" on the expected port, the add-on
either isn't started or is configured on a different port — check
Settings → Add-ons → Advanced SSH & Web Terminal → Log/Configuration.

## Troubleshooting

**`sudo: unable to resolve host <hostname>`** — harmless warning but
annoying. The remote machine can't resolve its own hostname. Fix on the
remote:

```bash
echo "127.0.1.1 $(hostname)" | sudo tee -a /etc/hosts
```

**Key auth ignored, falls back to password on first login** — usually wrong
permissions on `~/.ssh/authorized_keys` on the remote (`sshd` silently
rejects loose permissions). Fix on the remote:

```bash
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

## Current host entries (this machine)

See `~/.ssh/config`:

- `rpi0pcp` → `tc@rpi0pcp.local`
- `rpi3havsat2` → `jlc@rpi3havsat2.local`
- `homeassistant` → `root@homeassistant.local:22` (via Advanced SSH & Web
  Terminal add-on)
- `uconsole` → `uconsole.local` (had `sudo` hostname fix applied)
