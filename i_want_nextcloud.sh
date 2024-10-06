#!/bin/bash

# ==========================
# Nextcloud installation script with Apache2, PHP-FPM, Redis, Opcache, APCu, and MariaDB configuration
# ==========================

# Configuration variables
DB_USER="nextcloud"
DB_PASS="passw@rd"
DB_NAME="nextcloud"
ADMIN_USER="admin"
ADMIN_PASS="admin123"
TRUSTED_DOMAIN="192.168.50.232"

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

echo "The script is running with root privileges."

apt update $$ apt upgrade -y

# Install Apache2 and MariaDB
apt install apache2 mariadb-server -y

#Install PHP and requirments
apt install libapache2-mod-php php-bz2 php-gd php-mysql php-curl php-zip \
php-mbstring php-imagick php-ctype php-curl php-dom php-json php-posix \
php-bcmath php-xml php-intl php-gmp zip unzip wget

# Set on modules Apache and restart service
a2enmod rewrite dir mime env headers
systemctl restart apache2

# MariaDB configure
mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Download and install nextcloud
cd /var/www/
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
rm -rf latest.zip
chown -R www-data:www-data /var/www/nextcloud/
sudo -u www-data php /var/www/nextcloud/occ maintenance:install --database "mysql" \
--database-name "$DB_NAME" --database-user "$DB_USER" --database-pass "$DB_PASS" --admin-user "$ADMIN_USER" \
--admin-pass "$ADMIN_PASS"

# Install php-fpm and other requrments
apt install php8.1-fpm
service php8.1-fpm status
php-fpm8.1 -v
ls -la /var/run/php/php8.1-fpm.sock

# Set off Apache module prefork
a2dismod php8.1
a2dismod mpm_prefork

# Set on php-fpm
a2enmod mpm_event proxy_fcgi setenvif
a2enconf php8.1-fpm

# Configure PHP (php.ini)
sed -i 's/^\s*;\?\s*upload_max_filesize\s*=\s*.*/upload_max_filesize = 64M/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*post_max_size\s*=\s*.*/post_max_size = 96M/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*memory_limit\s*=\s*.*/memory_limit = 512M/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*max_execution_time\s*=\s*.*/max_execution_time = 600/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*max_input_vars\s*=\s*.*/max_input_vars = 3000/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*max_input_time\s*=\s*.*/max_input_time = 1000/' /etc/php/8.1/fpm/php.ini

# Configure php-fpm
sed -i 's/^#\?\(pm.max_children\s*=\s*\).*/\1 64/' /etc/php/8.1/fpm/pool.d/www.conf
sed -i 's/^#\?\(pm.start_servers\s*=\s*\).*/\1 16/' /etc/php/8.1/fpm/pool.d/www.conf
sed -i 's/^#\?\(pm.min_spare_servers\s*=\s*\).*/\1 16/' /etc/php/8.1/fpm/pool.d/www.conf
sed -i 's/^#\?\(pm.max_spare_servers\s*=\s*\).*/\1 32/' /etc/php/8.1/fpm/pool.d/www.conf

service php8.1-fpm restart

# Apache configuration
cat << EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud

    <Directory /var/www/nextcloud>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        Satisfy Any

       <IfModule mod_dav.c>
          Dav off
       </IfModule>

       SetEnv HOME /var/www/nextcloud
       SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/var/run/php/php8.1-fpm.sock|fcgi://localhost"
    </FilesMatch>
</VirtualHost>
EOF

service apache2 restart

# Opcache configuration in php.ini
sed -i 's/^\s*;\?\s*opcache.enable\s*=\s*.*/opcache.enable=1/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.enable_cli\s*=\s*.*/opcache.enable_cli=1/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.interned_strings_buffer\s*=\s*.*/opcache.interned_strings_buffer=8/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.max_accelerated_files\s*=\s*.*/opcache.max_accelerated_files=10000/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.memory_consumption\s*=\s*.*/opcache.memory_consumption=128/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.save_comments\s*=\s*.*/opcache.save_comments=1/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*opcache.revalidate_freq\s*=\s*.*/opcache.revalidate_freq=60/' /etc/php/8.1/fpm/php.ini


systemctl restart php8.1-fpm
systemctl restart apache2

# Install APCu
apt install php8.1-apcu
systemctl restart php8.1-fpm
systemctl restart apache2

# Install Redis
apt-get install redis-server php-redis
systemctl start redis-server
systemctl enable redis-server

# Redis configurate
sed -i 's/^#\s*port.*/port 0/' /etc/redis/redis.conf
sed -i 's/^#\s*unixsocket.*/unixsocket \/var\/run\/redis\/redis.sock/' /etc/redis/redis.conf
sed -i 's/^#\s*unixsocketperm.*/unixsocketperm 770/' /etc/redis/redis.conf

# Add user Apache to redis group
usermod -a -G redis www-data

# Redis configuration in php.ini
sed -i 's/^\s*;\?\s*redis.session.locking_enabled\s*=\s*.*/redis.session.locking_enabled=1/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*redis.session.lock_retries\s*=\s*.*/redis.session.lock_retries=-1/' /etc/php/8.1/fpm/php.ini
sed -i 's/^\s*;\?\s*redis.session.lock_wait_time\s*=\s*.*/redis.session.lock_wait_time=10000/' /etc/php/8.1/fpm/php.ini

# Configure nextcloud config.php
config_file="/var/www/nextcloud/config/config.php"

sed -i "/0 => 'localhost',/ a\    1 => '$TRUSTED_DOMAIN'," /var/www/nextcloud/config/config.php

if ! grep -q "'memcache.local' => '\\\\OC\\\\Memcache\\\\APCu'" $config_file; then
    sed -i "/'installed' => true,/ a\  'memcache.local' => '\\\\OC\\\\Memcache\\\\APCu'," $config_file
fi

if ! grep -q "'filelocking.enabled' => true" $config_file; then
    sed -i "/'memcache.local' => '\\\\OC\\\\Memcache\\\\APCu',/ a\  'filelocking.enabled' => true," $config_file
fi

if ! grep -q "'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis'" $config_file; then
    sed -i "/'filelocking.enabled' => true,/ a\  'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis'," $config_file
fi

if ! grep -q "'redis' => array(" $config_file; then
    sed -i "/'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis',/ a\  'redis' => array(\n    'host' => '\/var\/run\/redis\/redis.sock',\n    'port' => 0,\n    'dbindex' => 0,\n    'password' => '',\n    'timeout' => 1.5,\n  )," $config_file
fi

systemctl restart php8.1-fpm
systemctl restart apache2
systemctl restart redis


echo "Nextcloud installation and configuration completed successfully!"
