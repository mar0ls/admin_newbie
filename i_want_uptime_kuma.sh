#!/usr/bin/env bash

# ==========================
# Uptime Kuma - monitoring with a web UI (needs Docker)
# Usage: sudo ./i_want_uptime_kuma.sh
#        sudo UPTIME_KUMA_BIND=10.8.0.1 ./i_want_uptime_kuma.sh   # only via WireGuard VPN
#        sudo UPTIME_KUMA_BIND=127.0.0.1 ./i_want_uptime_kuma.sh  # only from the server
# Then open http://<server-ip>:3001 and create the admin account.
# No Docker yet? Run i_want_docker_with_portainer.sh first.
# ==========================

UPTIME_KUMA_VERSION=${UPTIME_KUMA_VERSION:-2}
UPTIME_KUMA_PORT=${UPTIME_KUMA_PORT:-3001}

# Who can open it. Empty = anyone on the network (Docker skips ufw!)
# 127.0.0.1 = only from the server, 10.8.0.1 = only through the WireGuard VPN
UPTIME_KUMA_BIND=${UPTIME_KUMA_BIND:-}

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

if ! command -v docker >/dev/null; then
    echo "Docker is not installed. Run i_want_docker_with_portainer.sh first." >&2
    exit 1
fi

if [[ -n $UPTIME_KUMA_BIND ]] && ! ip -o addr show | grep -qF " $UPTIME_KUMA_BIND/"; then
    echo "$UPTIME_KUMA_BIND is not an address of this server." >&2
    echo "For the VPN address, run i_want_wireguard.sh first." >&2
    exit 1
fi

if docker container inspect uptime-kuma &>/dev/null; then
    say "uptime-kuma already exists, making sure it's running"
    echo "    To change version, port or address: docker rm -f uptime-kuma, then run me again"
    echo "    (your data stays in the uptime-kuma volume)"
    docker start uptime-kuma >/dev/null
else
    say "Starting Uptime Kuma ($UPTIME_KUMA_VERSION)"
    docker run -d \
        --name uptime-kuma \
        --restart=always \
        -p "${UPTIME_KUMA_BIND:+$UPTIME_KUMA_BIND:}$UPTIME_KUMA_PORT:3001" \
        -v uptime-kuma:/app/data \
        "louislam/uptime-kuma:$UPTIME_KUMA_VERSION"
fi

host=${UPTIME_KUMA_BIND:-localhost}
for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://$host:$UPTIME_KUMA_PORT" || true)
    [[ $code == 200 || $code == 302 ]] && break
    sleep 2
done

if [[ $code != 200 && $code != 302 ]]; then
    echo "Not responding yet, check: docker logs uptime-kuma" >&2
    exit 1
fi

if [[ $UPTIME_KUMA_BIND == 127.0.0.1 ]]; then
    say "Done. It only listens on this server."
    echo "    From your computer: ssh -L $UPTIME_KUMA_PORT:localhost:$UPTIME_KUMA_PORT <user>@<server-ip>"
    echo "    then open http://localhost:$UPTIME_KUMA_PORT and create the admin account"
else
    [[ -n $UPTIME_KUMA_BIND ]] || host=$(hostname -I | awk '{print $1}')
    say "Done. Open http://$host:$UPTIME_KUMA_PORT and create the admin account"
fi
