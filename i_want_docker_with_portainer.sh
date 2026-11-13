#!/usr/bin/env bash

# ==========================
# Docker CE + Portainer CE for Ubuntu / Debian
# Usage: sudo ./i_want_docker_with_portainer.sh
# ==========================

# Portainer tag: "lts" or a fixed version, e.g. 2.27.3
PORTAINER_VERSION=${PORTAINER_VERSION:-lts}

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release
case "$ID ${ID_LIKE:-}" in
    *ubuntu*) distro=ubuntu; codename=${UBUNTU_CODENAME:-$VERSION_CODENAME} ;;
    *debian*) distro=debian; codename=$VERSION_CODENAME ;;
    *) echo "Only Ubuntu and Debian are supported." >&2; exit 1 ;;
esac

is_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'; }

# Remove distro packages that conflict with Docker CE.
# Old docker.socket has to be stopped first, otherwise it stays half-alive
# after the swap and the new dockerd can't start.
if is_installed docker.io; then
    systemctl stop docker.socket docker.service 2>/dev/null || true
fi
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if is_installed "$pkg"; then
        say "Removing $pkg"
        apt-get remove -y "$pkg"
    fi
done

say "Adding Docker repository"
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$distro/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$distro $codename stable" \
    > /etc/apt/sources.list.d/docker.list

say "Installing Docker"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl restart docker.socket docker
docker version --format 'Docker {{.Server.Version}} is running'

# docker without sudo (after re-login). Note: docker group = root access.
if [[ -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
    usermod -aG docker "$SUDO_USER"
fi

if docker container inspect portainer &>/dev/null; then
    say "Portainer already exists, making sure it's running"
    docker start portainer >/dev/null
else
    say "Starting Portainer ($PORTAINER_VERSION)"
    docker volume create portainer_data >/dev/null
    # Only 9443 (web UI). 8000 is for Edge Agents, not needed here.
    docker run -d \
        --name portainer \
        --restart=always \
        -p 9443:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        "portainer/portainer-ce:$PORTAINER_VERSION"
fi

ip=$(hostname -I | awk '{print $1}')
say "Done. Open https://$ip:9443 and create the admin account within 5 minutes"
echo "    (after that Portainer locks setup - fix with: docker restart portainer)"
