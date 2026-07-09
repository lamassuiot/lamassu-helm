#!/bin/bash

set -euo pipefail

SSH_DESTINATION="${SSH_DESTINATION:?SSH_DESTINATION is required}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-/etc/p11-kit-ssh/id_ed25519}"
SSH_PORT="${SSH_PORT:-22}"
P11_LOCAL_SOCKET="${P11_LOCAL_SOCKET:-/run/p11-kit/pkcs11}"
P11_REMOTE_SOCKET="${P11_REMOTE_SOCKET:-/run/p11-kit/pkcs11}"
SSH_LOG_LEVEL="${SSH_LOG_LEVEL:-VERBOSE}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-10}"
SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL:-30}"
SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX:-3}"
SSH_STREAMLOCAL_BIND_MASK="${SSH_STREAMLOCAL_BIND_MASK:-0177}"
SSH_RUNTIME_IDENTITY_FILE="${SSH_RUNTIME_IDENTITY_FILE:-/tmp/p11-kit-ssh-key}"
SSH_HOME_DIR="${HOME:-/tmp}"
P11_LOCAL_SOCKET_DIR="$(dirname "$P11_LOCAL_SOCKET")"

# The container may run under an arbitrary uid (e.g. restricted PodSecurity), in
# which case $HOME may point to a directory we cannot write to. Fall back to a
# writable temporary HOME so ssh has a usable state directory.
if ! mkdir -p "$SSH_HOME_DIR/.ssh" 2>/dev/null; then
    SSH_HOME_DIR="$(mktemp -d)"
    export HOME="$SSH_HOME_DIR"
    mkdir -p "$SSH_HOME_DIR/.ssh"
fi
mkdir -p "$P11_LOCAL_SOCKET_DIR"
chmod 700 "$SSH_HOME_DIR/.ssh"

# The shared socket directory may come from a pod volume owned by another user.
# We only need it to exist; changing its mode is optional and should not block startup.
if [[ -O "$P11_LOCAL_SOCKET_DIR" ]]; then
    chmod 755 "$P11_LOCAL_SOCKET_DIR"
fi

if [[ ! -f "$SSH_IDENTITY_FILE" ]]; then
    echo "SSH identity file not found: $SSH_IDENTITY_FILE" >&2
    exit 1
fi

cp "$SSH_IDENTITY_FILE" "$SSH_RUNTIME_IDENTITY_FILE"
chmod 600 "$SSH_RUNTIME_IDENTITY_FILE"

rm -f "$P11_LOCAL_SOCKET"

echo "Starting PKCS#11 SSH tunnel"
echo "  destination : $SSH_DESTINATION"
echo "  ssh port    : $SSH_PORT"
echo "  local socket: $P11_LOCAL_SOCKET"
echo "  remote sock : $P11_REMOTE_SOCKET"
echo "  log level   : $SSH_LOG_LEVEL"
echo "  conn timeout: $SSH_CONNECT_TIMEOUT"
echo "  alive intvl : $SSH_SERVER_ALIVE_INTERVAL"
echo "  alive count : $SSH_SERVER_ALIVE_COUNT_MAX"
echo "  sock mask   : $SSH_STREAMLOCAL_BIND_MASK"
echo "  key source  : $SSH_IDENTITY_FILE"
echo "  key runtime : $SSH_RUNTIME_IDENTITY_FILE"

exec ssh -N \
    -o BatchMode=yes \
    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
    -o ExitOnForwardFailure=yes \
    -o LogLevel="$SSH_LOG_LEVEL" \
    -o ServerAliveInterval="$SSH_SERVER_ALIVE_INTERVAL" \
    -o ServerAliveCountMax="$SSH_SERVER_ALIVE_COUNT_MAX" \
    -o StreamLocalBindMask="$SSH_STREAMLOCAL_BIND_MASK" \
    -o TCPKeepAlive=yes \
    -o StreamLocalBindUnlink=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SSH_RUNTIME_IDENTITY_FILE" \
    -p "$SSH_PORT" \
    -L "$P11_LOCAL_SOCKET:$P11_REMOTE_SOCKET" \
    "$SSH_DESTINATION"
