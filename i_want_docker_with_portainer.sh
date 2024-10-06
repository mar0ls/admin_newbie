#!/bin/bash

# ==========================
# Docker installation script with portainer for Ubuntu
# ==========================

# Check sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

echo "The script is running with root privileges."

# List of packages to check
packages=("docker.io" "docker-doc" "docker-compose" "docker-compose-v2" "podman-docker" "containerd" "runc")

# Iterating through packages
for pkg in "${packages[@]}"; do
    if dpkg -l | grep -q "$pkg"; then  # Checking if the package is installed
        echo "Removing $pkg..."
        sudo apt-get remove -y "$pkg"  # Removing the package
    else
        echo "$pkg is not installed."
    fi
done

# Updating package list
sudo apt-get update

# Installing necessary tools
sudo apt-get install -y ca-certificates curl gnupg

# Creating directory for GPG key
sudo install -m 0755 -d /etc/apt/keyrings

# Downloading Docker's GPG key
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Adding Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Updating package list again
sudo apt-get update

# Installing Docker CE, CLI, Containerd, and additional plugins
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Checking if Docker was installed correctly
if docker --version; then
    echo "Docker has been successfully installed."
else
    echo "Docker installation failed!"
    exit 1
fi

# Creating a volume for Portainer
docker volume create portainer_data

# Running the Portainer container
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.21.2

# Checking if Portainer is running correctly
if [ "$(docker ps -q -f name=portainer)" ]; then
    echo "Portainer has been successfully installed and is running."
else
    echo "Portainer installation failed!"
    exit 1
fi
