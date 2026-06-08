#!/bin/bash

set -euo pipefail

mkdir -p /root/.ssh /run/p11-kit
chmod 700 /root/.ssh
chmod 755 /run/p11-kit

SSH_DESTINATION="${SSH_DESTINATION:?SSH_DESTINATION is required}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-/etc/p11-kit-ssh/id_ed25519}"
SSH_PORT="${SSH_PORT:-22}"
P11_LOCAL_SOCKET="${P11_LOCAL_SOCKET:-/run/p11-kit/pkcs11}"
P11_REMOTE_SOCKET="${P11_REMOTE_SOCKET:-/run/p11-kit/pkcs11}"
SSH_LOG_LEVEL="${SSH_LOG_LEVEL:-VERBOSE}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL:-30}"
SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX:-3}"
SSH_RUNTIME_IDENTITY_FILE="${SSH_RUNTIME_IDENTITY_FILE:-/tmp/p11-kit-ssh-key}"

if [[ ! -f "$SSH_IDENTITY_FILE" ]]; then
    echo "SSH identity file not found: $SSH_IDENTITY_FILE" >&2
    exit 1
fi

cp "$SSH_IDENTITY_FILE" "$SSH_RUNTIME_IDENTITY_FILE"
chmod 600 "$SSH_RUNTIME_IDENTITY_FILE"

rm -f "$P11_LOCAL_SOCKET"
mkdir -p "$(dirname "$P11_LOCAL_SOCKET")"

echo "Starting PKCS#11 SSH tunnel"
echo "  destination : $SSH_DESTINATION"
echo "  ssh port    : $SSH_PORT"
echo "  local socket: $P11_LOCAL_SOCKET"
echo "  remote sock : $P11_REMOTE_SOCKET"
echo "  log level   : $SSH_LOG_LEVEL"
echo "  conn timeout: $SSH_CONNECT_TIMEOUT"
echo "  alive intvl : $SSH_SERVER_ALIVE_INTERVAL"
echo "  alive count : $SSH_SERVER_ALIVE_COUNT_MAX"
echo "  key source  : $SSH_IDENTITY_FILE"
echo "  key runtime : $SSH_RUNTIME_IDENTITY_FILE"

exec ssh -N \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ExitOnForwardFailure=yes \
    -o LogLevel="$SSH_LOG_LEVEL" \
    -o ServerAliveInterval="$SSH_SERVER_ALIVE_INTERVAL" \
    -o ServerAliveCountMax="$SSH_SERVER_ALIVE_COUNT_MAX" \
    -o TCPKeepAlive=yes \
    -o StreamLocalBindUnlink=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SSH_RUNTIME_IDENTITY_FILE" \
    -p "$SSH_PORT" \
    -L "$P11_LOCAL_SOCKET:$P11_REMOTE_SOCKET" \
    "$SSH_DESTINATION"
