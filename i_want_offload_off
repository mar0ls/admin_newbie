#!/bin/bash

# ==========================
# Offload off script 
# ==========================

# Check sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

echo "The script is running with root privileges."

# Check interfaces
delim=";"; ifaces=""; for item in `ls /sys/class/net/ | egrep '^eth|ens|eno|enp'`; do ifaces+="$item$delim"; done ; ifaces=${ifaces%"$deli$delim"}

# Changing params for all interfaces , offload off rx, tx, tso, gso, gpro, tx etc (look line 21)
for iface in ${ifaces//;/ }; do
  echo "Setting capture params for $iface"
  for i in rx tx tso gso gro tx nocache copy sg rxvlan; do ethtool -K $iface $i off > /dev/null 2>&1; done
done

G=$(tput setaf 2)
NC=$(tput sgr0)

echo "${G}The script done work !!! ${NC}"
