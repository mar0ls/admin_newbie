#!/usr/bin/env bash

# ==========================
# Basic ufw firewall: deny incoming except SSH (+ ports you pass), allow outgoing
# Usage: sudo ./i_want_firewall.sh                  # SSH only
#        sudo ./i_want_firewall.sh 80/tcp 443/tcp   # SSH + web
# Undo:  sudo ufw disable
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

command -v ufw >/dev/null || { apt-get update; apt-get install -y ufw; }

# Take the SSH port from sshd config, in case it's not 22
ssh_ports=()
if command -v sshd >/dev/null; then
    mkdir -p /run/sshd
    mapfile -t ssh_ports < <(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}')
    [[ ${#ssh_ports[@]} -gt 0 ]] || ssh_ports=(22)
fi

ufw default deny incoming
ufw default allow outgoing

for port in "${ssh_ports[@]}"; do
    say "Allowing SSH on $port"
    ufw allow "$port/tcp" comment 'SSH'
done

for rule in "$@"; do
    say "Allowing $rule"
    ufw allow "$rule"
done

ufw --force enable
ufw status verbose

if command -v docker >/dev/null; then
    echo
    echo "Note: ports published with 'docker run -p' bypass ufw."
    echo "Use -p 127.0.0.1:PORT:PORT for things that should stay local."
fi
