#!/usr/bin/env bash

# ==========================
# Uptime Kuma - monitoring with a web UI (needs Docker)
# Usage: sudo ./i_want_uptime_kuma.sh
# Then open http://<server-ip>:3001 and create the admin account.
# No Docker yet? Run i_want_docker_with_portainer.sh first.
# ==========================

UPTIME_KUMA_VERSION=${UPTIME_KUMA_VERSION:-2}
UPTIME_KUMA_PORT=${UPTIME_KUMA_PORT:-3001}

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

if docker container inspect uptime-kuma &>/dev/null; then
    say "uptime-kuma already exists, making sure it's running"
    docker start uptime-kuma >/dev/null
else
    say "Starting Uptime Kuma ($UPTIME_KUMA_VERSION)"
    docker run -d \
        --name uptime-kuma \
        --restart=always \
        -p "$UPTIME_KUMA_PORT:3001" \
        -v uptime-kuma:/app/data \
        "louislam/uptime-kuma:$UPTIME_KUMA_VERSION"
fi

for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$UPTIME_KUMA_PORT" || true)
    [[ $code == 200 || $code == 302 ]] && break
    sleep 2
done

if [[ $code != 200 && $code != 302 ]]; then
    echo "Not responding yet, check: docker logs uptime-kuma" >&2
    exit 1
fi

ip=$(hostname -I | awk '{print $1}')
say "Done. Open http://$ip:$UPTIME_KUMA_PORT and create the admin account"
