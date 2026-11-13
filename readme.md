![unnamed](https://github.com/user-attachments/assets/427d82fd-7d7e-4f91-ae3d-c563526d567c)

# admin_newbie

[![tests](https://github.com/mar0ls/admin_newbie/actions/workflows/tests.yml/badge.svg)](https://github.com/mar0ls/admin_newbie/actions/workflows/tests.yml)

Bash scripts that set up common things on a fresh Ubuntu server, one script per task.
Each one is a single file: read it, download it, run it with `sudo`.

Tested on Ubuntu 24.04. Debian 12 should work too.

## Scripts

| Script | What it does |
|---|---|
| [i_want_docker_with_portainer.sh](i_want_docker_with_portainer.sh) | Docker CE from Docker's repo + Portainer web UI on port 9443 |
| [i_want_nextcloud.sh](i_want_nextcloud.sh) | Nextcloud with Apache, PHP-FPM, MariaDB, APCu and Redis |
| [i_want_smb.sh](i_want_smb.sh) | Samba share in `~/sambashare`, only for your user |
| [i_want_firewall.sh](i_want_firewall.sh) | ufw: block incoming except SSH and ports you choose |
| [i_want_ssh_hardening.sh](i_want_ssh_hardening.sh) | SSH with keys only, no root login, fail2ban |
| [i_want_auto_updates.sh](i_want_auto_updates.sh) | Daily automatic security updates |
| [i_want_swap.sh](i_want_swap.sh) | Swap file, for small VPSes that come without one |
| [i_want_new_admin_user.sh](i_want_new_admin_user.sh) | New user with sudo and an SSH key |
| [i_want_backup.sh](i_want_backup.sh) | Daily encrypted backups with restic |
| [i_want_wireguard.sh](i_want_wireguard.sh) | WireGuard VPN server, client configs with QR codes |
| [i_want_uptime_kuma.sh](i_want_uptime_kuma.sh) | Uptime Kuma: monitoring with a web UI (in Docker) |
| [i_want_offload_off.sh](i_want_offload_off.sh) | Turns off NIC offloading (for packet capture / IDS) |
| [i_want_promisc_as_a_service.sh](i_want_promisc_as_a_service.sh) | Keeps an interface in promiscuous mode after reboot |

## How to use

Download one script, look at it, run it:

```bash
curl -O https://raw.githubusercontent.com/mar0ls/admin_newbie/main/i_want_firewall.sh
less i_want_firewall.sh
chmod +x i_want_firewall.sh
sudo ./i_want_firewall.sh
```

Or clone the whole repo:

```bash
git clone https://github.com/mar0ls/admin_newbie.git
cd admin_newbie
sudo ./i_want_firewall.sh
```

Run them with `sudo` from your normal account, not as root. Some scripts (Samba, SSH)
need to know who you are.

## Script notes

### Docker + Portainer

```bash
sudo ./i_want_docker_with_portainer.sh
```

- Removes `docker.io` and other distro packages that conflict with Docker CE.
- Adds you to the `docker` group, so after logging out and back in you can run `docker` without sudo.
- Portainer: `https://<server-ip>:9443`. Create the admin account within 5 minutes,
  otherwise run `docker restart portainer` and try again.
- Portainer version is set at the top of the script (`PORTAINER_VERSION`), or:
  `sudo PORTAINER_VERSION=2.27.3 ./i_want_docker_with_portainer.sh`

**Heads up:** ports published with `docker run -p` skip ufw rules.

### Nextcloud

```bash
sudo ./i_want_nextcloud.sh
sudo NC_DOMAIN=cloud.example.com NC_ADMIN_USER=marcin ./i_want_nextcloud.sh
```

- Passwords are generated and saved in `/root/nextcloud-credentials.txt`.
- Versions are at the top of the script: `NEXTCLOUD_VERSION` (default `latest`) and `PHP_VERSION`
  (default: what your system ships).
- Plain HTTP. If the server is reachable from the internet, add HTTPS:
  `sudo apt install certbot python3-certbot-apache && sudo certbot --apache`
- Ubuntu 24.04 comes with PHP 8.3. Recent Nextcloud releases mark 8.3 as deprecated, and a future
  release may need 8.4. If that happens, use `NEXTCLOUD_VERSION` to stay on an older release.
- Nextcloud's admin page will still show two warnings: the PHP 8.3 one above and a missing
  HSTS header. The second goes away once you set up HTTPS.
- The script won't run if `/var/www/nextcloud` already exists.

### Samba

```bash
sudo ./i_want_smb.sh
```

Shares `~/sambashare`. Only your user can log in, with a separate Samba password.
Connect with `\\<server-ip>\sambashare` (Windows) or `smb://<server-ip>/sambashare` (macOS/Linux).
Your original config is saved as `/etc/samba/smb.conf.orig`.

### Firewall

```bash
sudo ./i_want_firewall.sh                  # SSH only
sudo ./i_want_firewall.sh 80/tcp 443/tcp   # SSH + web
```

The SSH port is read from your sshd config and allowed before ufw is enabled, so you
won't lock yourself out. Undo: `sudo ufw disable`.

### SSH hardening

```bash
sudo ./i_want_ssh_hardening.sh
```

**First make sure key login works** (`ssh-copy-id user@server` from your computer).
The script stops if your account has no SSH key, because disabling passwords
without a key would lock you out.

- Settings go to `/etc/ssh/sshd_config.d/10-admin-newbie.conf`. Delete that file and run
  `sudo systemctl reload ssh` to undo.
- fail2ban bans an IP for 1 hour after 5 failed logins in 10 minutes.
  Unban: `sudo fail2ban-client set sshd unbanip <ip>`

Keep your current session open and try logging in from a second terminal before you close it.

### Automatic updates

```bash
sudo ./i_want_auto_updates.sh
sudo AUTO_REBOOT=03:30 ./i_want_auto_updates.sh   # also reboot at 03:30 when needed
```

Security updates only. With no `AUTO_REBOOT` set, the server never reboots on its own.
Log: `/var/log/unattended-upgrades/unattended-upgrades.log`

### Swap

```bash
sudo ./i_want_swap.sh       # 2G
sudo ./i_want_swap.sh 4G
```

Does nothing if swap is already on. Also sets `vm.swappiness = 10`.

### New admin user

```bash
sudo ./i_want_new_admin_user.sh anna
sudo ./i_want_new_admin_user.sh anna "ssh-ed25519 AAAA... anna@laptop"
```

Creates the user, adds it to `sudo` and, if you pass a public key, to `authorized_keys`.
It still asks for a password, because `sudo` needs one even when you log in with a key.

### Backup (restic)

```bash
sudo ./i_want_backup.sh /mnt/backup/restic                 # folder or external disk
sudo ./i_want_backup.sh sftp:user@nas:/backups/server      # any restic repository
sudo BACKUP_PATHS="/etc /srv/data" ./i_want_backup.sh /mnt/backup/restic
```

- Backs up `/etc /home /root /var/www` by default (set `BACKUP_PATHS`), every day at 02:30
  (`BACKUP_TIME`). Keeps 7 daily, 4 weekly and 6 monthly snapshots.
- Backups are encrypted. The password is generated and printed at the end:
  **save it somewhere else, without it the backups are useless.**
- Restore: `sudo restic-restore latest /tmp/restore`
- Backing up to the same disk protects against deleted files, not against a dead disk.
  Use another disk or machine for the repository.

### WireGuard VPN

```bash
sudo ./i_want_wireguard.sh            # server + first client (client1)
sudo ./i_want_wireguard.sh phone      # another client
```

- Client configs are in `/etc/wireguard/clients/`. A QR code is printed, so a phone can
  scan it in the WireGuard app.
- The server address in the configs is your server's first IP. If that's not the public
  one, run with `WG_ENDPOINT=vpn.example.com`.
- Open UDP 51820 on your router or cloud firewall (ufw is handled by the script).
- By default all client traffic goes through the VPN. For access to the server's network only:
  `WG_ALLOWED=10.8.0.0/24`.

### Uptime Kuma

```bash
sudo ./i_want_uptime_kuma.sh
```

Needs Docker (run `i_want_docker_with_portainer.sh` first). Open `http://<server-ip>:3001`
and create the admin account. Version and port are at the top of the script.

### Offload off / promiscuous mode

For a capture or IDS box (tcpdump, Suricata, Zeek, Arkime) on a SPAN / mirror port:

```bash
sudo ./i_want_offload_off.sh eth1
sudo ./i_want_promisc_as_a_service.sh eth1
```

Both create systemd services (`nic-offload-off@eth1`, `promisc@eth1`), so the settings
survive a reboot. Without arguments, `i_want_offload_off.sh` uses all physical interfaces.

Don't turn offloading off on a normal server, because it uses more CPU.

## Requirements

- Ubuntu 24.04 (22.04 and Debian 12 should work too)
- A user with sudo
- Internet access (packages are downloaded)

## Contributing

Found a bug, or have a script idea? Open an issue or a PR.
Every push runs ShellCheck and test runs on Ubuntu 24.04 (GitHub Actions).
