#!/usr/bin/env bash

# ==========================
# Swap file - for small VPSes without swap
# Usage: sudo ./i_want_swap.sh      # 2G
#        sudo ./i_want_swap.sh 4G
# ==========================

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

size=${1:-2G}
swapfile=/swapfile

if [[ ! $size =~ ^[0-9]+[MG]$ ]]; then
    echo "Size should look like 512M or 2G, got '$size'." >&2
    exit 1
fi

if [[ -n $(swapon --show --noheadings) ]]; then
    say "Swap is already on:"
    swapon --show
    exit 0
fi

if [[ -e $swapfile ]]; then
    echo "$swapfile exists but isn't active - check it or remove it." >&2
    exit 1
fi

fstype=$(findmnt -no FSTYPE /)
if [[ $fstype == btrfs || $fstype == zfs ]]; then
    echo "Plain swap file doesn't work on $fstype." >&2
    exit 1
fi

# Keep at least 1G free on disk
need=$(( $(numfmt --from=iec "$size") + 1024*1024*1024 ))
free=$(df --output=avail -B1 / | tail -1)
if (( free < need )); then
    echo "Not enough disk: $(numfmt --to=iec "$free") free, need $size + 1G." >&2
    exit 1
fi

say "Creating $size swap at $swapfile"
fallocate -l "$size" "$swapfile"
chmod 600 "$swapfile"
mkswap "$swapfile" >/dev/null
swapon "$swapfile"

grep -q "^$swapfile " /etc/fstab || echo "$swapfile none swap sw 0 0" >> /etc/fstab

# Use swap as a safety net, not right away
echo "vm.swappiness = 10" > /etc/sysctl.d/90-swappiness.conf
sysctl -q -p /etc/sysctl.d/90-swappiness.conf

swapon --show
free -h
say "Done."
