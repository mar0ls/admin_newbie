#!/usr/bin/env bash

# ==========================
# Promiscuous mode on an interface as a service (survives reboot)
# Usage: sudo ./i_want_promisc_as_a_service.sh eth1
#        sudo ./i_want_promisc_as_a_service.sh       # asks for the interface
# Undo:  sudo systemctl disable --now promisc@eth1
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

iface=${1:-}
if [[ -z $iface ]]; then
    ip -br link
    read -rp "Interface for monitoring: " iface
fi

if ! ip link show dev "$iface" &>/dev/null; then
    echo "Interface '$iface' doesn't exist." >&2
    exit 1
fi

# Template unit, so it works for more than one interface.
# "up" because a mirror port usually has no IP and nobody else brings it up.
cat > /etc/systemd/system/promisc@.service <<'EOF'
[Unit]
Description=Promiscuous mode on %I
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev %I up promisc on
ExecStop=/usr/sbin/ip link set dev %I promisc off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

unit="promisc@$(systemd-escape "$iface").service"
systemctl daemon-reload
systemctl enable --now "$unit"

if ip link show dev "$iface" | grep -q PROMISC; then
    say "$iface is in promiscuous mode."
else
    echo "$iface is not in PROMISC mode, check: systemctl status $unit" >&2
    exit 1
fi
