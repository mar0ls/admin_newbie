#!/usr/bin/env bash

# ==========================
# Daily encrypted backups with restic (systemd timer)
# Usage: sudo ./i_want_backup.sh /mnt/backup/restic            # folder or external disk
#        sudo ./i_want_backup.sh sftp:user@nas:/backups/server # any restic repo URL
#        sudo BACKUP_PATHS="/etc /srv/data" ./i_want_backup.sh /mnt/backup/restic
# Restore: sudo restic-restore latest /tmp/restore
# For S3 and similar, put the access keys in /etc/restic/restic.env
# ==========================

BACKUP_PATHS=${BACKUP_PATHS:-"/etc /home /root /var/www"}
BACKUP_TIME=${BACKUP_TIME:-02:30}
KEEP_DAILY=${KEEP_DAILY:-7}
KEEP_WEEKLY=${KEEP_WEEKLY:-4}
KEEP_MONTHLY=${KEEP_MONTHLY:-6}

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

repo=${1:-}
if [[ -z $repo ]]; then
    echo "Usage: sudo $0 <folder or restic repo URL>" >&2
    exit 1
fi

# Only back up paths that exist, a missing one would fail the whole run
paths=()
for p in $BACKUP_PATHS; do
    if [[ -e $p ]]; then paths+=("$p"); else echo "Skipping $p (not found)"; fi
done
if [[ ${#paths[@]} -eq 0 ]]; then
    echo "None of the BACKUP_PATHS exist." >&2
    exit 1
fi

say "Installing restic"
apt-get update
apt-get install -y restic openssl

install -d -m 700 /etc/restic
if [[ ! -f /etc/restic/password ]]; then
    install -m 600 /dev/null /etc/restic/password
    openssl rand -base64 24 > /etc/restic/password
fi

# Don't back up the backup, if the repo sits inside one of the paths
exclude=""
if [[ $repo == /* ]]; then
    mkdir -p "$repo"
    exclude=$repo
fi

install -m 600 /dev/null /etc/restic/restic.env
cat > /etc/restic/restic.env <<EOF
RESTIC_REPOSITORY="$repo"
RESTIC_PASSWORD_FILE=/etc/restic/password
BACKUP_PATHS="${paths[*]}"
BACKUP_EXCLUDE="$exclude"
EOF

# restic with the settings from restic.env
r() {
    # shellcheck source=/dev/null
    (set -a; . /etc/restic/restic.env; restic "$@")
}

r cat config &>/dev/null || {
    say "Creating repository"
    r init
}

cat > /usr/local/sbin/restic-backup <<EOF
#!/bin/bash
set -euo pipefail
set -a; . /etc/restic/restic.env; set +a
args=()
[[ -z \$BACKUP_EXCLUDE ]] || args+=(--exclude "\$BACKUP_EXCLUDE")
restic backup "\${args[@]}" \$BACKUP_PATHS
restic forget --prune --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY
EOF
chmod 755 /usr/local/sbin/restic-backup

cat > /usr/local/sbin/restic-restore <<'EOF'
#!/bin/bash
set -euo pipefail
set -a; . /etc/restic/restic.env; set +a
restic restore "${1:-latest}" --target "${2:?Usage: restic-restore <snapshot|latest> <target dir>}"
EOF
chmod 755 /usr/local/sbin/restic-restore

cat > /etc/systemd/system/restic-backup.service <<'EOF'
[Unit]
Description=restic backup

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/restic-backup
Nice=10
EOF

cat > /etc/systemd/system/restic-backup.timer <<EOF
[Unit]
Description=Daily restic backup

[Timer]
OnCalendar=*-*-* $BACKUP_TIME
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now restic-backup.timer

say "First backup"
systemctl start restic-backup.service
r snapshots

say "Done. Next run: $(systemctl show restic-backup.timer -p NextElapseUSecRealtime --value)"
echo
echo "    SAVE THIS PASSWORD somewhere else (password manager). Without it the backups are useless:"
echo "    $(cat /etc/restic/password)"
