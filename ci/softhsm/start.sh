#!/bin/bash

set -euo pipefail

service syslog-ng start

mkdir -p /var/run/sshd /root/.ssh
chmod 700 /root/.ssh

if [[ -n "${SSH_AUTHORIZED_KEYS:-}" ]]; then
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "SSH authorized_keys configured for root login."
else
    echo "SSH_AUTHORIZED_KEYS is empty. sshd will listen on port 22, but key-based login will fail until a public key is provided."
fi

ssh-keygen -A

cat >/etc/ssh/sshd_config.d/softhsm.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM no
AllowTcpForwarding yes
X11Forwarding no
PermitTunnel no
EOF

echo "Validating sshd configuration..."
/usr/sbin/sshd -t
echo "Starting sshd on port 22..."
/usr/sbin/sshd
echo "sshd started successfully and is listening on port 22."

function chck_empty(){
    if [[ "$2" == "" ]]; then
        echo "INVALID option $1: '$2' !!PANIC!!"
        exit 1
    fi
    echo "$1: $2"
}

echo "creating hsm config file..."
echo "=========================="
echo "directories.tokendir = /softhsm/tokens" > /etc/softhsm2.conf
echo "objectstore.backend = db" >> /etc/softhsm2.conf
echo "log.level = DEBUG" >> /etc/softhsm2.conf
echo "slots.removable = false" >> /etc/softhsm2.conf 

echo "config file content:"
cat  /etc/softhsm2.conf 

echo "=========================="
chck_empty "Label" "$LABEL"
chck_empty "PIN" "$PIN"
chck_empty "SO PIN" "$SO_PIN"
echo "=========================="

requires_init=false

echo "checking if SoftHSM requires init..."
output=$(softhsm2-util --show-slots)
if echo "$output" | grep -qw "$LABEL"; then 
    echo "Label '$LABEL' exists. Init already done."
else
  echo "Label '$LABEL' does not exist. Init required."
  requires_init=true
fi

echo "=========================="
if [[ "$requires_init" == "false" ]]; then
    echo "SoftHSM already initialized. Skipping init."
else
    echo "Initializing SoftHSM..."
    softhsm2-util --init-token --free --label "$LABEL" --pin "$PIN" --so-pin "$SO_PIN"
    echo "Init process completed."
fi

echo "=========================="
mkdir -p /run/p11-kit
chown root:root /run/p11-kit
chmod 700 /run/p11-kit

P11_SOCKET_PATH="unix:path=/run/p11-kit/pkcs11"
echo "Starting p11-kit server on unix socket: $P11_SOCKET_PATH"
echo "Module provider: /usr/local/lib/softhsm/libsofthsm2.so"
echo "Token selector: pkcs11:token=$LABEL"

echo "
 ___  ___  ________  _____ ______           ________  _______   ________  ________      ___    ___ 
|\  \|\  \|\   ____\|\   _ \  _   \        |\   __  \|\  ___ \ |\   __  \|\   ___ \    |\  \  /  /|
\ \  \\\  \ \  \___|\ \  \\\__\ \  \       \ \  \|\  \ \   __/|\ \  \|\  \ \  \_|\ \   \ \  \/  / /
 \ \   __  \ \_____  \ \  \\|__| \  \       \ \   _  _\ \  \_|/_\ \   __  \ \  \ \\ \   \ \    / / 
  \ \  \ \  \|____|\  \ \  \    \ \  \       \ \  \\  \\ \  \_|\ \ \  \ \  \ \  \_\\ \   \/  /  /  
   \ \__\ \__\____\_\  \ \__\    \ \__\       \ \__\\ _\\ \_______\ \__\ \__\ \_______\__/  / /    
    \|__|\|__|\_________\|__|     \|__|        \|__|\|__|\|_______|\|__|\|__|\|_______|\___/ /     

                     +------------------------------------------------------+
                     |                SoftHSM Container Stack               |
                     +------------------------------------------------------+
                     | SSH client key  ->  sshd  ->  p11-kit server         |
                     |                                 |                    |
                     |                                 v                    |
                     |                         /run/p11-kit/pkcs11          |
                     |                                 |                    |
                     |                                 v                    |
                     |                           libsofthsm2.so             |
                     |                                 |                    |
                     |                                 v                    |
                     |                        /softhsm/tokens (PVC)         |
                     +------------------------------------------------------+

"

echo "SoftHSM startup complete. SSH is enabled on port 22 and p11-kit server is starting in the foreground."

p11-kit server --foreground \
    --name "$P11_SOCKET_PATH" \
    --provider /usr/local/lib/softhsm/libsofthsm2.so \
    "pkcs11:token=$LABEL"

