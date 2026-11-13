#!/usr/bin/env bash

# ==========================
# SMB share in your home dir (~/sambashare), only your user has access
# Usage: sudo ./i_want_smb.sh
#        sudo SMB_PASSWORD='...' ./i_want_smb.sh   # no password prompt
# Connect: \\<server-ip>\sambashare  or  smb://<server-ip>/sambashare
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

user=${SUDO_USER:-}
if [[ -z $user || $user == root ]]; then
    echo "Run this with sudo from your normal account, not as root." >&2
    exit 1
fi
home=$(getent passwd "$user" | cut -d: -f6)
share=$home/sambashare
conf=/etc/samba/smb.conf

say "Installing Samba"
apt-get update
apt-get install -y samba

install -d -o "$user" -g "$user" "$share"

[[ -e $conf.orig ]] || cp "$conf" "$conf.orig"

if grep -q '^\[sambashare\]' "$conf"; then
    say "[sambashare] already in $conf"
else
    cat >> "$conf" <<EOF

[sambashare]
    comment = $user's share
    path = $share
    read only = no
    browseable = yes
    valid users = $user
EOF
fi

if ! testparm -s "$conf" &>/dev/null; then
    testparm -s "$conf"
    exit 1
fi

say "Setting Samba password for $user"
if [[ -n ${SMB_PASSWORD:-} ]]; then
    printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -s -a "$user"
else
    smbpasswd -a "$user"
fi

systemctl enable smbd
systemctl restart smbd

if command -v ufw >/dev/null; then
    ufw allow Samba
fi

ip=$(hostname -I | awk '{print $1}')
say "Done. Share: \\\\$ip\\sambashare (user: $user)"
