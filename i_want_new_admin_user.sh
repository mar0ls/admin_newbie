#!/usr/bin/env bash

# ==========================
# New admin user: sudo + optional SSH key
# Usage: sudo ./i_want_new_admin_user.sh marcin
#        sudo ./i_want_new_admin_user.sh marcin "ssh-ed25519 AAAA... me@laptop"
# The password is asked for (sudo needs it, also when you log in with a key).
# For no prompt: sudo NEW_USER_PASSWORD='...' ./i_want_new_admin_user.sh marcin
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

name=${1:-}
key=${2:-}

if [[ ! $name =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Usage: sudo $0 <username> [\"ssh public key\"]" >&2
    echo "Username: lowercase letters, digits, - and _" >&2
    exit 1
fi

if id "$name" &>/dev/null; then
    echo "User $name already exists." >&2
    exit 1
fi

if [[ -n $key && ! $key =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp[0-9]+|sk-[a-z0-9@.-]+)\  ]]; then
    echo "That doesn't look like an SSH public key (ssh-ed25519 AAAA..., ssh-rsa AAAA...)." >&2
    exit 1
fi

say "Creating $name"
adduser --disabled-password --gecos "" "$name"
usermod -aG sudo "$name"

if [[ -n ${NEW_USER_PASSWORD:-} ]]; then
    echo "$name:$NEW_USER_PASSWORD" | chpasswd
else
    passwd "$name"
fi

if [[ -n $key ]]; then
    home=$(getent passwd "$name" | cut -d: -f6)
    install -d -m 700 -o "$name" -g "$name" "$home/.ssh"
    echo "$key" > "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
    chown "$name:$name" "$home/.ssh/authorized_keys"
    say "SSH key added"
fi

say "Done. Log in as $name and check: sudo whoami"
[[ -n $key ]] || echo "    No SSH key yet. From your computer: ssh-copy-id $name@<server-ip>"
