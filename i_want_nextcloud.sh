#!/usr/bin/env bash

# ==========================
# Nextcloud with Apache2, PHP-FPM, MariaDB, APCu and Redis
# Usage: sudo ./i_want_nextcloud.sh
#        sudo NC_DOMAIN=cloud.example.com ./i_want_nextcloud.sh
# HTTP only - add HTTPS (certbot --apache) if it's reachable from the internet.
# ==========================

# Versions
NEXTCLOUD_VERSION=${NEXTCLOUD_VERSION:-latest}   # or e.g. 31.0.9
PHP_VERSION=${PHP_VERSION:-}                     # empty = distro default (8.3 on Ubuntu 24.04)

# Settings. Empty passwords get generated and saved to /root/nextcloud-credentials.txt
NC_DOMAIN=${NC_DOMAIN:-$(hostname -I | awk '{print $1}')}
NC_ADMIN_USER=${NC_ADMIN_USER:-admin}
NC_ADMIN_PASS=${NC_ADMIN_PASS:-}
DB_NAME=${DB_NAME:-nextcloud}
DB_USER=${DB_USER:-nextcloud}
DB_PASS=${DB_PASS:-}
FPM_MAX_CHILDREN=${FPM_MAX_CHILDREN:-16}         # ~100 MB RAM each
NC_DIR=/var/www/nextcloud

set -euo pipefail

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
occ() { runuser -u www-data -- php "$NC_DIR/occ" "$@"; }

if [[ $EUID -ne 0 ]]; then
    echo "Run me with sudo: sudo $0" >&2
    exit 1
fi

if [[ -e $NC_DIR ]]; then
    echo "$NC_DIR already exists, Nextcloud is probably installed. Not touching it." >&2
    exit 1
fi

php=php${PHP_VERSION}

say "Installing Apache, MariaDB, Redis and PHP"
apt-get update
# No libapache2-mod-php - it pulls in mpm_prefork, we use PHP-FPM instead
apt-get install -y \
    apache2 mariadb-server redis-server cron unzip curl openssl \
    "$php-fpm" "$php-cli" "$php-mysql" "$php-gd" "$php-curl" "$php-zip" \
    "$php-mbstring" "$php-xml" "$php-intl" "$php-bcmath" "$php-gmp" \
    "$php-bz2" "$php-imagick" "$php-apcu" "$php-redis"

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
say "Using PHP $PHP_VERSION"

[[ -n $DB_PASS ]]       || DB_PASS=$(openssl rand -hex 16)
[[ -n $NC_ADMIN_PASS ]] || NC_ADMIN_PASS=$(openssl rand -hex 12)

# PHP config
cat > "/etc/php/$PHP_VERSION/fpm/conf.d/90-nextcloud.ini" <<'EOF'
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 600
max_input_time = 1000
max_input_vars = 3000

opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
opcache.save_comments = 1
EOF

# occ and cron run from CLI and need APCu too
cat > "/etc/php/$PHP_VERSION/cli/conf.d/90-nextcloud.ini" <<'EOF'
memory_limit = 512M
apc.enable_cli = 1
EOF

# php-fpm pool; env[] lines fix the "getenv" warning in Nextcloud admin
sed -i -E \
    -e "s/^pm\.max_children = .*/pm.max_children = $FPM_MAX_CHILDREN/" \
    -e "s/^pm\.start_servers = .*/pm.start_servers = 4/" \
    -e "s/^pm\.min_spare_servers = .*/pm.min_spare_servers = 2/" \
    -e "s/^pm\.max_spare_servers = .*/pm.max_spare_servers = 6/" \
    -e 's/^;(env\[(HOSTNAME|PATH|TMP|TMPDIR|TEMP)\])/\1/' \
    "/etc/php/$PHP_VERSION/fpm/pool.d/www.conf"

# Redis on unix socket only
sed -i -E \
    -e 's|^port .*|port 0|' \
    -e 's|^# ?unixsocket .*|unixsocket /run/redis/redis-server.sock|' \
    -e 's|^# ?unixsocketperm .*|unixsocketperm 770|' \
    /etc/redis/redis.conf
usermod -aG redis www-data
systemctl enable redis-server
systemctl restart redis-server

say "Creating database"
# Default redo log is too small for Nextcloud (it shows a warning in admin)
cat > /etc/mysql/mariadb.conf.d/99-nextcloud.cnf <<'EOF'
[mysqld]
innodb_log_file_size = 256M
EOF
systemctl enable mariadb
systemctl restart mariadb
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE OR REPLACE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

if [[ $NEXTCLOUD_VERSION == latest ]]; then
    zip=latest.zip
else
    zip=nextcloud-$NEXTCLOUD_VERSION.zip
fi

say "Downloading Nextcloud ($NEXTCLOUD_VERSION)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar -o "$tmp/$zip" "https://download.nextcloud.com/server/releases/$zip"
curl -fsSL -o "$tmp/$zip.sha256" "https://download.nextcloud.com/server/releases/$zip.sha256"
(cd "$tmp" && sha256sum -c --ignore-missing "$zip.sha256")
unzip -q "$tmp/$zip" -d /var/www/
chown -R www-data:www-data "$NC_DIR"

say "Installing Nextcloud"
occ maintenance:install \
    --database mysql \
    --database-name "$DB_NAME" \
    --database-user "$DB_USER" \
    --database-pass "$DB_PASS" \
    --admin-user "$NC_ADMIN_USER" \
    --admin-pass "$NC_ADMIN_PASS"

occ config:system:set trusted_domains 1 --value="$NC_DOMAIN"
occ config:system:set memcache.local --value='\OC\Memcache\APCu'
occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
occ config:system:set redis host --value=/run/redis/redis-server.sock
occ config:system:set redis port --value=0 --type=integer
# Heavy daily jobs between 01:00 and 05:00 UTC
occ config:system:set maintenance_window_start --value=1 --type=integer

# Pretty URLs (/login instead of /index.php/login)
occ config:system:set htaccess.RewriteBase --value=/
occ maintenance:update:htaccess
occ maintenance:repair --include-expensive >/dev/null

# Background jobs from system cron
occ background:cron
echo "*/5 * * * * php -f $NC_DIR/cron.php" | crontab -u www-data -
# One run now, otherwise admin shows "last cron run: 56 years ago" for 5 minutes
runuser -u www-data -- php -f "$NC_DIR/cron.php"

# Apache
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName $NC_DOMAIN
    DocumentRoot $NC_DIR

    <Directory $NC_DIR>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews

        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

a2dismod -q "php$PHP_VERSION" mpm_prefork 2>/dev/null || true
a2enmod -q mpm_event proxy_fcgi setenvif rewrite headers env dir mime
a2enconf -q "php$PHP_VERSION-fpm"
a2dissite -q 000-default
a2ensite -q nextcloud
apache2ctl configtest
systemctl restart "php$PHP_VERSION-fpm" apache2

creds=/root/nextcloud-credentials.txt
install -m 600 /dev/null "$creds"
cat > "$creds" <<EOF
Nextcloud: http://$NC_DOMAIN
Admin:     $NC_ADMIN_USER / $NC_ADMIN_PASS
Database:  $DB_NAME, user $DB_USER / $DB_PASS
EOF

say "Nextcloud is up: http://$NC_DOMAIN (admin: $NC_ADMIN_USER)"
echo "    Passwords saved in $creds"
