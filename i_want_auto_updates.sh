#!/usr/bin/env bash

# ==========================
# Automatic security updates (unattended-upgrades)
# Usage: sudo ./i_want_auto_updates.sh
#        sudo AUTO_REBOOT=03:30 ./i_want_auto_updates.sh   # reboot at 03:30 if needed
# Log:   /var/log/unattended-upgrades/unattended-upgrades.log
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

AUTO_REBOOT=${AUTO_REBOOT:-}
if [[ -n $AUTO_REBOOT && ! $AUTO_REBOOT =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "AUTO_REBOOT should be a time like 03:30, got '$AUTO_REBOOT'." >&2
    exit 1
fi

say "Installing unattended-upgrades"
apt-get update
apt-get install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# Separate file, so 50unattended-upgrades stays untouched
reboot_conf=/etc/apt/apt.conf.d/52admin-newbie-reboot
if [[ -n $AUTO_REBOOT ]]; then
    cat > "$reboot_conf" <<EOF
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "$AUTO_REBOOT";
EOF
    say "Auto reboot at $AUTO_REBOOT when needed"
else
    rm -f "$reboot_conf"
fi

systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers 'apt-daily*' --no-pager

say "Done. Security updates will install daily."
