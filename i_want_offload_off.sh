#!/usr/bin/env bash

# ==========================
# Offload off script (GRO, GSO, TSO, checksum, VLAN) - for capture / IDS boxes
# Stays off after reboot (nic-offload-off@<iface>.service)
# Usage: sudo ./i_want_offload_off.sh            # all physical interfaces
#        sudo ./i_want_offload_off.sh eth1 eth2  # only these
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

command -v ethtool >/dev/null || { apt-get update; apt-get install -y ethtool; }

if [[ $# -gt 0 ]]; then
    ifaces=("$@")
else
    # Physical NICs have a "device" entry in sysfs, lo/bridges/veth don't
    ifaces=()
    for dev in /sys/class/net/*; do
        [[ -e $dev/device ]] && ifaces+=("$(basename "$dev")")
    done
fi

if [[ ${#ifaces[@]} -eq 0 ]]; then
    echo "No physical interfaces found. Pass the name: sudo $0 eth1" >&2
    exit 1
fi

for iface in "${ifaces[@]}"; do
    if ! ip link show dev "$iface" &>/dev/null; then
        echo "Interface $iface doesn't exist (see: ip -br link)" >&2
        exit 1
    fi
done

# One feature at a time - not every NIC supports all of them
cat > /usr/local/sbin/nic-offload-off <<'EOF'
#!/bin/sh
for f in rx tx sg tso gso gro lro rxvlan txvlan; do
    ethtool -K "$1" "$f" off >/dev/null 2>&1
done
exit 0
EOF
chmod 755 /usr/local/sbin/nic-offload-off

cat > /etc/systemd/system/nic-offload-off@.service <<'EOF'
[Unit]
Description=Disable NIC offloading on %I
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nic-offload-off %I
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

for iface in "${ifaces[@]}"; do
    say "Offload off on $iface"
    unit="nic-offload-off@$(systemd-escape "$iface").service"
    systemctl enable "$unit"
    systemctl restart "$unit"
    ethtool -k "$iface" | grep -E '^(rx-checksumming|tx-checksumming|scatter-gather|tcp-segmentation-offload|generic-segmentation-offload|generic-receive-offload|large-receive-offload):' | sed 's/^/    /'
done

say "Done. Anything still 'on' is [fixed] on this NIC and can't be changed."
