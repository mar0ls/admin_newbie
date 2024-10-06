#!/bin/bash

# ==========================
# SMB installation script for Ubuntu
# ==========================

# Input sudo password
read -s -p "Enter your sudo password: " sudo_password
echo

# Check if the currently logged user is root
if [ "$EUID" -eq 0 ]; then
    echo "You are already logged in as root. Exiting..."
    exit 1
else
    # Check if sudo password is correct
    echo "$sudo_password" | sudo -S true  # This command checks if the password is valid
    if [ $? -ne 0 ]; then
        echo "Invalid sudo password. Exiting..."
        exit 1
    fi
fi

# Continue with the rest of the script if not root and sudo password is valid
echo "Installing necessary packages..."
sudo apt update
sudo apt install -y samba samba-common

# Create a directory for the current user
current_user=$(whoami)
mkdir -p "/home/$current_user/sambashare"

# Add or uncomment the necessary Samba configurations
if grep -q "^#.*security = user" /etc/samba/smb.conf; then
    $sudo_cmd sed -i 's/^#.*security = user/security = user/' /etc/samba/smb.conf
else
    echo "security = user" | $sudo_cmd tee -a /etc/samba/smb.conf
fi

if grep -q "^#.*map to guest = never" /etc/samba/smb.conf; then
    $sudo_cmd sed -i 's/^#.*map to guest = never/map to guest = never/' /etc/samba/smb.conf
else
    echo "map to guest = never" | $sudo_cmd tee -a /etc/samba/smb.conf
fi

# Add Samba configuration
sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF
[sambashare]
    comment = Samba on Ubuntu
    path = /home/$current_user/sambashare
    read only = no
    browsable = yes
    writable=yes
    valid users = $current_user
EOF

# Restart Samba service and enable it to start on boot
echo "Starting Samba service..."
sudo systemctl restart smbd
sudo systemctl enable smbd

# Allow Samba through the firewall
sudo ufw allow samba

# Change ownership of the shared directory
sudo chown -R "$current_user:sambashare" "/home/$current_user/sambashare/"

# Set Samba password for the current user
sudo smbpasswd -a "$current_user"

# Check if Samba was set up correctly
if testparm; then
    echo "Samba setup successfully."
else
    echo "Samba setup failed."
    exit 1
fi
