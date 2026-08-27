# ssh-node-setup.sh — how to use

Automates the steps in [README.md](README.md): copies your existing SSH key to
a remote host, verifies passwordless login works, and manages the `Host`
alias for it in `~/.ssh/config`.

Installed at `~/bin/ssh-node-setup.sh`. Source lives in this directory —
after editing, copy it back to `~/bin/` and re-`chmod +x`.

## Prerequisites

- A key pair already generated on this laptop at `~/.ssh/id_ed25519` /
  `~/.ssh/id_ed25519.pub` (see README.md step 1 if not).
- The remote host reachable and accepting password login (needed once, to
  install the key).

## Usage

```bash
ssh-node-setup.sh <user>@<host> [port]
```

`port` defaults to `22`.

### Examples

```bash
ssh-node-setup.sh jlc@rpi3havsat2.local
ssh-node-setup.sh root@homeassistant.local 22
```

## What it does

1. Prints a banner and a summary of what it's about to do (key path, remote
   user/host, the alias it will use).
2. **Installs the key** — via `ssh-copy-id` if available, otherwise the
   manual `cat | ssh ... >> authorized_keys` fallback. Prompts for the
   remote's password once.
3. **Verifies** the connection with `ssh -o BatchMode=yes`, which fails
   loudly instead of silently falling back to a password prompt — so
   "Success" printed at this step means key auth genuinely works.
4. **Manages the `~/.ssh/config` alias**, derived from the hostname with
   `.local` stripped (e.g. `rpi3havsat2.local` → `rpi3havsat2`):
   - If no entry exists yet for that alias: asks (Enter = yes) whether to
     add a new `Host` block, and optionally a second alias name on the same
     line (matching the multi-alias style already used in this config, e.g.
     `Host rpi3havsat2 havsat2`).
   - If an entry already exists: shows you the matching line and asks if
     you want to add *another* alias to that same line instead of creating
     a duplicate block.
   - `Port` is only written if it's not the default `22`.
5. Prints the full resulting `~/.ssh/config` so you can see the result, then
   a closing banner.

After it finishes, connect with:

```bash
ssh <alias>
```

## Notes

- Safe to re-run against the same host — it won't duplicate the key on the
  remote (`ssh-copy-id` checks first) or duplicate the `Host` entry locally.
- For HAOS or other hosts needing special setup before `sshd` is reachable,
  do that first (see README.md "Special case: Home Assistant OS"), then run
  this script once the port is known and reachable.
