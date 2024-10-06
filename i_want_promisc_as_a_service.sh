
#!/bin/bash

G=$(tput setaf 2)
NC=$(tput sgr0)

# ==========================
# Promiscus mode in interface as a service script for Ubuntu
# ==========================

# Input sudo password
read -s -p "${G}Enter your sudo password: ${NC}" root
echo

# Check if the currently logged user is root
if [ "$EUID" -eq 0 ]; then
    echo $root | sudo -S echo "${G}Sudo access granted.${NC}"
    exit 1
else
    # Check if sudo password is correct
    echo "$root" | sudo -S true  # This command checks if the password is valid
    if [ $? -ne 0 ]; then
        echo "Invalid sudo password. Exiting..."
        exit 1
    fi
fi

# Prompt name network interface for promisc mode
read -p "${G}Enter the network interface name for monitoring: ${NC}" interface


# Create systemd service files for promisc service
PROMISC_FILE=/etc/systemd/system/promisc.service
if ! grep -q "promisc" $PROMISC_FILE; then
  echo $root | sudo -S bash -c "cat > '$PROMISC_FILE' <<EOF
[Unit]
Description=Bring up an interface in promiscuous mode during boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev $interface promisc on
TimeoutStartSec=0
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF"
fi

# Reload systemd daemon, enable and start promisc services
echo $root | sudo -S systemctl daemon-reload 
echo $root | sudo -S systemctl enable promisc.service 

# Arkime and Promisc services status
echo "${G} PROMISC SERVICES STATUS:  ${NC}"
echo $root | sudo -S systemctl status promisc.service 

