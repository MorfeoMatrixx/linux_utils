#!/usr/bin/env bash
# Set up passwordless SSH login to a remote host using this laptop's existing key,
# then optionally add (or extend) a Host alias for it in ~/.ssh/config.
set -euo pipefail

banner() {
    echo
    echo "======================================================"
    echo " $1"
    echo "======================================================"
}

usage() {
    echo "Usage: $0 <user>@<host> [port]"
    echo "Example: $0 jlc@rpi3havsat2.local"
    echo "Example: $0 root@homeassistant.local 22"
    exit 1
}

[[ $# -ge 1 ]] || usage

TARGET="$1"
PORT="${2:-22}"
PUBKEY="$HOME/.ssh/id_ed25519.pub"
SSH_CONFIG="$HOME/.ssh/config"

REMOTE_USER="${TARGET%@*}"
REMOTE_HOST="${TARGET#*@}"
DEFAULT_ALIAS="${REMOTE_HOST%.local}"

banner "SSH node setup: $TARGET (port $PORT)"

echo "Local public key:  $PUBKEY"
echo "Remote user:       $REMOTE_USER"
echo "Remote host:       $REMOTE_HOST"
echo "Default alias:     $DEFAULT_ALIAS"

if [[ ! -f "$PUBKEY" ]]; then
    echo
    echo "No key found at $PUBKEY. Generate one first:"
    echo "  ssh-keygen -t ed25519 -C \"\$(whoami)@\$(hostname)\""
    exit 1
fi

echo
echo "Step 1/2: installing the public key on $TARGET..."
if command -v ssh-copy-id >/dev/null 2>&1; then
    echo "Using ssh-copy-id (will prompt for the remote password once)."
    ssh-copy-id -p "$PORT" -i "$PUBKEY" "$TARGET"
else
    echo "ssh-copy-id not found, falling back to manual append over ssh."
    cat "$PUBKEY" | ssh -p "$PORT" "$TARGET" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
fi
echo "Key installed."

echo
echo "Step 2/2: verifying passwordless login (ssh -o BatchMode=yes)..."
if ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=5 "$TARGET" true; then
    echo "Success: $TARGET now accepts key-based login."
else
    echo "Key was installed but a password-free connection still failed."
    echo "Check remote ~/.ssh permissions (700 dir, 600 authorized_keys) and sshd config."
    exit 1
fi

# --- ~/.ssh/config alias setup ---

find_host_line() {
    local a="$1"
    [[ -f "$SSH_CONFIG" ]] && grep -nE "^Host[[:space:]]+(\S+[[:space:]]+)*${a}([[:space:]]+\S+)*[[:space:]]*$" "$SSH_CONFIG" | head -1
}

append_alias_to_line() {
    local lineno="$1" new_alias="$2"
    sed -i "${lineno}s/[[:space:]]*$/ ${new_alias}/" "$SSH_CONFIG"
}

echo
echo "Checking $SSH_CONFIG for an existing alias..."
MATCH="$(find_host_line "$DEFAULT_ALIAS" || true)"

if [[ -n "$MATCH" ]]; then
    LINE_NO="${MATCH%%:*}"
    LINE_TEXT="${MATCH#*:}"
    echo "Found existing entry (line $LINE_NO): $LINE_TEXT"
    read -rp "Add another alias for this host? (blank to skip): " EXTRA_ALIAS
    if [[ -n "$EXTRA_ALIAS" ]]; then
        echo "Adding '$EXTRA_ALIAS' to that Host line..."
        append_alias_to_line "$LINE_NO" "$EXTRA_ALIAS"
        echo "Added. You can now use: ssh $EXTRA_ALIAS"
    else
        echo "Skipped, leaving the existing entry as is."
    fi
else
    echo "No existing entry found for '$DEFAULT_ALIAS'."
    read -rp "Add alias '$DEFAULT_ALIAS' to $SSH_CONFIG? [Y/n] " ADD_ALIAS
    ADD_ALIAS="${ADD_ALIAS:-y}"
    if [[ "$ADD_ALIAS" =~ ^[Yy] ]]; then
        read -rp "Add another alias too? (blank to skip): " EXTRA_ALIAS

        ALIASES="$DEFAULT_ALIAS"
        [[ -n "$EXTRA_ALIAS" ]] && ALIASES="$DEFAULT_ALIAS $EXTRA_ALIAS"

        echo "Appending new Host block to $SSH_CONFIG..."
        {
            [[ -s "$SSH_CONFIG" ]] && echo
            echo "Host $ALIASES"
            echo "    HostName $REMOTE_HOST"
            echo "    User $REMOTE_USER"
            [[ "$PORT" != "22" ]] && echo "    Port $PORT"
        } >> "$SSH_CONFIG"

        echo "Added. You can now use: ssh $DEFAULT_ALIAS"
    else
        echo "Skipped adding alias."
    fi
fi

echo
echo "--- $SSH_CONFIG ---"
cat "$SSH_CONFIG"

banner "Done: $TARGET is set up for passwordless SSH"
