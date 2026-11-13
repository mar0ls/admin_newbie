#!/usr/bin/env bash

# ==========================
# WireGuard VPN server + client configs
# Usage: sudo ./i_want_wireguard.sh            # server + first client ("client1")
#        sudo ./i_want_wireguard.sh phone      # add another client
# Client configs: /etc/wireguard/clients/<name>.conf (a QR code is printed for phones)
# ==========================

WG_PORT=${WG_PORT:-51820}
WG_NET=${WG_NET:-10.8.0}                  # server is .1, clients get .2, .3, ...
WG_ENDPOINT=${WG_ENDPOINT:-$(hostname -I | awk '{print $1}')}   # public IP or domain
WG_DNS=${WG_DNS:-1.1.1.1}
WG_ALLOWED=${WG_ALLOWED:-0.0.0.0/0}       # 0.0.0.0/0 = all traffic through the VPN

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

name=${1:-client1}
if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Client name: letters, digits, - and _ only." >&2
    exit 1
fi

conf=/etc/wireguard/wg0.conf
clients=/etc/wireguard/clients

say "Installing WireGuard"
apt-get update
apt-get install -y wireguard qrencode

umask 077
mkdir -p "$clients"

if [[ ! -f $conf ]]; then
    say "Setting up the server"
    wan=$(ip route show default | awk '{print $5; exit}')
    wg genkey > /etc/wireguard/server.key
    wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub

    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-wireguard.conf
    sysctl -q -p /etc/sysctl.d/90-wireguard.conf

    cat > "$conf" <<EOF
[Interface]
Address = $WG_NET.1/24
ListenPort = $WG_PORT
PrivateKey = $(cat /etc/wireguard/server.key)
PostUp = iptables -I FORWARD 1 -i wg0 -j ACCEPT; iptables -I FORWARD 1 -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s $WG_NET.0/24 -o $wan -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s $WG_NET.0/24 -o $wan -j MASQUERADE
EOF

    if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
        ufw allow "$WG_PORT/udp"
    fi

    systemctl enable --now wg-quick@wg0
fi

if [[ -f $clients/$name.conf ]]; then
    echo "Client $name already exists: $clients/$name.conf" >&2
    exit 1
fi

# First free address after .1
used=$(grep -oE "${WG_NET//./\\.}\.[0-9]+" "$conf")
for i in $(seq 2 254); do
    grep -qx "$WG_NET.$i" <<<"$used" || { ip=$WG_NET.$i; break; }
done
if [[ -z ${ip:-} ]]; then
    echo "No free addresses left in $WG_NET.0/24." >&2
    exit 1
fi

say "Adding client $name ($ip)"
priv=$(wg genkey)
pub=$(wg pubkey <<<"$priv")

cat >> "$conf" <<EOF

# $name
[Peer]
PublicKey = $pub
AllowedIPs = $ip/32
EOF

cat > "$clients/$name.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $ip/32
DNS = $WG_DNS

[Peer]
PublicKey = $(cat /etc/wireguard/server.pub)
Endpoint = $WG_ENDPOINT:$WG_PORT
AllowedIPs = $WG_ALLOWED
PersistentKeepalive = 25
EOF

# Pick up the new peer without dropping other clients
wg syncconf wg0 <(wg-quick strip wg0)

say "Done. Client config: $clients/$name.conf"
echo "    Endpoint in it: $WG_ENDPOINT:$WG_PORT (if that's not your public address, rerun with WG_ENDPOINT=...)"
echo "    Open UDP $WG_PORT on your router / cloud firewall."
echo
qrencode -t ansiutf8 < "$clients/$name.conf"
