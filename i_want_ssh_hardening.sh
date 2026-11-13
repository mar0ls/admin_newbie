#!/usr/bin/env bash

# ==========================
# SSH hardening: key-only login, no root login, fail2ban
# Before: make sure key login works (ssh-copy-id user@server)
# Usage:  sudo ./i_want_ssh_hardening.sh
# Undo:   sudo rm /etc/ssh/sshd_config.d/10-admin-newbie.conf && sudo systemctl reload ssh
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

user=${SUDO_USER:-}
if [[ -z $user || $user == root ]]; then
    echo "Run this with sudo from your normal account - root login is about to be disabled." >&2
    exit 1
fi

# No key = no way back in after passwords are off
home=$(getent passwd "$user" | cut -d: -f6)
if [[ ! -s $home/.ssh/authorized_keys ]]; then
    echo "No SSH key in $home/.ssh/authorized_keys." >&2
    echo "Run ssh-copy-id $user@<server> from your computer, test it, then try again." >&2
    exit 1
fi

command -v sshd >/dev/null || { echo "openssh-server is not installed." >&2; exit 1; }

if ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    echo "sshd_config doesn't include sshd_config.d/ - system too old for this script." >&2
    exit 1
fi

# sshd uses the first value it sees, "10-" loads before 50-cloud-init.conf
dropin=/etc/ssh/sshd_config.d/10-admin-newbie.conf
cat > "$dropin" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF

mkdir -p /run/sshd
if ! sshd -t; then
    rm -f "$dropin"
    echo "sshd config test failed, change reverted." >&2
    exit 1
fi

# On Ubuntu 24.04 ssh is socket-activated and may not be running - that's fine
systemctl try-reload-or-restart ssh

effective=$(sshd -T)
for check in "permitrootlogin no" "passwordauthentication no"; do
    grep -qx "$check" <<<"$effective" \
        || echo "Warning: '$check' is overridden somewhere in /etc/ssh/" >&2
done
say "SSH: key-only, no root login"

say "Installing fail2ban"
apt-get update
# python3-systemd: read logs from journal, 24.04 may have no /var/log/auth.log
apt-get install -y fail2ban python3-systemd

cat > /etc/fail2ban/jail.d/admin-newbie.local <<'EOF'
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd

say "Done. Test login in a NEW terminal before closing this one."
echo "    Unban: sudo fail2ban-client set sshd unbanip <ip>"
