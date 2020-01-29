#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 using the current release of Nextcloud 17
# https://github.com/danb35/freenas-iocage-nextcloud

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE="vnet0"
VNET="on"
POOL_PATH=""
JAIL_NAME="nextcloud"
TIME_ZONE=""
HOST_NAME=""
DATABASE="mariadb"
DB_PATH=""
FILES_PATH=""
PORTS_PATH=""
STANDALONE_CERT=0
SELFSIGNED_CERT=0
DNS_CERT=0
NO_CERT=0
DL_FLAGS=""
DNS_SETTING=""

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
. "${SCRIPTPATH}"/nextcloud-config
CONFIGS_PATH="${SCRIPTPATH}"/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
if [ "${DATABASE}" = "mariadb" ]; then
  DB_NAME="MariaDB"
elif [ "${DATABASE}" = "pgsql" ]; then
  DB_NAME="PostgreSQL"
fi

ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g" | sed "s/-p[0-9]*//")

# Check for nextcloud-config and set configuration
if ! [ -e "${SCRIPTPATH}"/nextcloud-config ]; then
  echo "${SCRIPTPATH}/nextcloud-config must exist."
  exit 1
fi

# Check that necessary variables were set by nextcloud-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${DEFAULT_GW_IP}" ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z "${POOL_PATH}" ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi
if [ -z "${TIME_ZONE}" ]; then
  echo 'Configuration error: TIME_ZONE must be set'
  exit 1
fi
if [ -z "${HOST_NAME}" ]; then
  echo 'Configuration error: HOST_NAME must be set'
  exit 1
fi
if [ $STANDALONE_CERT -eq 0 ] && [ $DNS_CERT -eq 0 ] && [ $NO_CERT -eq 0 ] && [ $SELFSIGNED_CERT -eq 0 ]; then
  echo 'Configuration error: Either STANDALONE_CERT, DNS_CERT, NO_CERT,'
  echo 'or SELFSIGNED_CERT must be set to 1.'
  exit 1
fi
if [ $STANDALONE_CERT -eq 1 ] && [ $DNS_CERT -eq 1 ] ; then
  echo 'Configuration error: Only one of STANDALONE_CERT and DNS_CERT'
  echo 'may be set to 1.'
  exit 1
fi

if [ $DNS_CERT -eq 1 ] && [ -z "${DNS_PLUGIN}" ] ; then
  echo "DNS_PLUGIN must be set to a supported DNS provider."
  echo "See https://caddyserver.com/docs under the heading of \"DNS Providers\" for list."
  echo "Be sure to omit the prefix of \"tls.dns.\"."
  exit 1
fi  
if [ $DNS_CERT -eq 1 ] && [ -z "${DNS_ENV}" ] ; then
  echo "DNS_ENV must be set to a your DNS provider\'s authentication credentials."
  echo "See https://caddyserver.com/docs under the heading of \"DNS Providers\" for more."
  exit 1
fi  

if [ $DNS_CERT -eq 1 ] ; then
  DL_FLAGS="tls.dns.${DNS_PLUGIN}"
  DNS_SETTING="dns ${DNS_PLUGIN}"
fi

# If DB_PATH, FILES_PATH, and PORTS_PATH weren't set in nextcloud-config, set them
if [ -z "${DB_PATH}" ]; then
  DB_PATH="${POOL_PATH}"/db
fi
if [ -z "${FILES_PATH}" ]; then
  FILES_PATH="${POOL_PATH}"/files
fi
if [ -z "${PORTS_PATH}" ]; then
  PORTS_PATH="${POOL_PATH}"/portsnap
fi

# Sanity check DB_PATH, FILES_PATH, and PORTS_PATH -- they all have to be different,
# and can't be the same as POOL_PATH
if [ "${DB_PATH}" = "${FILES_PATH}" ] || [ "${FILES_PATH}" = "${PORTS_PATH}" ] || [ "${PORTS_PATH}" = "${DB_PATH}" ]
then
  echo "DB_PATH, FILES_PATH, and PORTS_PATH must all be different!"
  exit 1
fi

if [ "${DB_PATH}" = "${POOL_PATH}" ] || [ "${FILES_PATH}" = "${POOL_PATH}" ] || [ "${PORTS_PATH}" = "${POOL_PATH}" ]
then
  echo "DB_PATH, FILES_PATH, and PORTS_PATH must all be different"
  echo "from POOL_PATH!"
  exit 1
fi

# Make sure DB_PATH is empty -- if not, MariaDB/PostgreSQL will choke
if [ "$(ls -A "${DB_PATH}")" ]; then
  echo "${DB_PATH} is not empty!"
  echo "DB_PATH must be empty, otherwise this script will break your existing database."
  exit 1
fi

# Create the jail, pre-installing needed packages
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs":[
  "nano","sudo","redis","php73-ctype","gnupg","bash",
  "php73-dom","php73-gd","php73-iconv","php73-json","php73-mbstring",
  "php73-posix","php73-simplexml","php73-xmlreader","php73-xmlwriter",
  "php73-zip","php73-zlib","php73-hash","php73-xml",
  "php73-session","php73-wddx","php73-xsl","php73-filter",
  "php73-curl","php73-fileinfo","php73-bz2","php73-intl","php73-openssl",
  "php73-ldap","php73-ftp","php73-imap","php73-exif","php73-gmp",
  "php73-memcache","php73-opcache","php73-pcntl", "php73-pecl-imagick", "bash","perl5",
  "p5-Locale-gettext","help2man","texinfo","m4","autoconf"
  ]
}
__EOF__

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
if [ "${RELEASE}" = "11.1-RELEASE" ]; then
  iocage exec "${JAIL_NAME}" sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
  iocage exec "${JAIL_NAME}" pkg update -f
  iocage exec "${JAIL_NAME}" pkg upgrade -yf
fi
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" pkg install -qy mariadb103-server php73-pdo_mysql php73-mysqli
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" pkg install -qy postgresql10-server
fi
mkdir -p "${DB_PATH}"/
chown -R 88:88 "${DB_PATH}"/
mkdir -p "${FILES_PATH}"
chown -R 80:80 "${FILES_PATH}"
mkdir -p "${PORTS_PATH}"/ports
mkdir -p "${PORTS_PATH}"/db
iocage exec "${JAIL_NAME}" mkdir -p /mnt/files
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /var/db/mysql
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /var/db/postgres
fi
iocage exec "${JAIL_NAME}" mkdir -p /mnt/configs
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www
mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/var/db/portsnap
mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/mnt/files
mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/mnt/configs
mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/usr/ports
iocage fstab -a "${JAIL_NAME}" "${PORTS_PATH}"/ports /usr/ports nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${PORTS_PATH}"/db /var/db/portsnap nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${FILES_PATH}" /mnt/files nullfs rw 0 0
if [ "${DATABASE}" = "mariadb" ]; then
  mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/var/db/mysql
  iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"  /var/db/mysql  nullfs  rw  0  0
elif [ "${DATABASE}" = "pgsql" ]; then
  mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/var/db/postgres
  iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"  /var/db/postgres  nullfs  rw  0  0
fi
iocage fstab -a "${JAIL_NAME}" "${CONFIGS_PATH}" /mnt/configs nullfs rw 0 0
iocage exec "${JAIL_NAME}" chown -R www:www /mnt/files
iocage exec "${JAIL_NAME}" chmod -R 770 /mnt/files
iocage exec "${JAIL_NAME}" "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"
fetch -o /tmp https://getcaddy.com
if ! iocage exec "${JAIL_NAME}" bash -s personal "${DL_FLAGS}" < /tmp/getcaddy.com
then
	echo "Failed to download/install Caddy"
	exit 1
fi

FILE="latest-17.tar.bz2"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://download.nextcloud.com/server/releases/"${FILE}" https://download.nextcloud.com/server/releases/"${FILE}".asc https://nextcloud.com/nextcloud.asc
then
	echo "Failed to download Nextcloud"
	exit 1
fi
iocage exec "${JAIL_NAME}" gpg --import /tmp/nextcloud.asc
if ! iocage exec "${JAIL_NAME}" gpg --verify /tmp/"${FILE}".asc
then
	echo "GPG Signature Verification Failed!"
	echo "The Nextcloud download is corrupt."
	exit 1
fi
iocage exec "${JAIL_NAME}" tar xjf /tmp/"${FILE}" -C /usr/local/www/
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/www/nextcloud/
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" sysrc mysql_enable="YES"
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" sysrc postgresql_enable="YES"
fi
iocage exec "${JAIL_NAME}" sysrc redis_enable="YES"
iocage exec "${JAIL_NAME}" sysrc php_fpm_enable="YES"
iocage exec "${JAIL_NAME}" sh -c "ALLOW_UNSUPPORTED_SYSTEM=1 make -C /usr/ports/lang/php73 clean reinstall BATCH=yes"
iocage exec "${JAIL_NAME}" sh -c "ALLOW_UNSUPPORTED_SYSTEM=1 make -C /usr/ports/databases/pecl-redis clean install BATCH=yes"
iocage exec "${JAIL_NAME}" sh -c "ALLOW_UNSUPPORTED_SYSTEM=1 make -C /usr/ports/devel/pecl-APCu clean install BATCH=yes"
if [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" sh -c "make -C /usr/ports/databases/php73-pgsql clean install BATCH=yes"
  iocage exec "${JAIL_NAME}" sh -c "make -C /usr/ports/databases/php73-pdo_pgsql clean install BATCH=yes"
fi

# Generate and install self-signed cert, if necessary
if [ $SELFSIGNED_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pki/tls/private
  iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pki/tls/certs
  openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=${HOST_NAME}" -keyout "${CONFIGS_PATH}"/privkey.pem -out "${CONFIGS_PATH}"/fullchain.pem
  iocage exec "${JAIL_NAME}" cp /mnt/configs/privkey.pem /usr/local/etc/pki/tls/private/privkey.pem
  iocage exec "${JAIL_NAME}" cp /mnt/configs/fullchain.pem /usr/local/etc/pki/tls/certs/fullchain.pem
fi

# Copy and edit pre-written config files
iocage exec "${JAIL_NAME}" cp -f /mnt/configs/php.ini /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" cp -f /mnt/configs/redis.conf /usr/local/etc/redis.conf
iocage exec "${JAIL_NAME}" cp -f /mnt/configs/www.conf /usr/local/etc/php-fpm.d/
if [ $STANDALONE_CERT -eq 1 ] || [ $DNS_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/remove-staging.sh /root/
fi
if [ $NO_CERT -eq 1 ]; then
  echo "Copying Caddyfile for no SSL"
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/Caddyfile-nossl /usr/local/www/Caddyfile
elif [ $SELFSIGNED_CERT -eq 1 ]; then
  echo "Copying Caddyfile for self-signed cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/Caddyfile-selfsigned /usr/local/www/Caddyfile
else
  echo "Copying Caddyfile for Let's Encrypt cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/Caddyfile /usr/local/www/
fi
iocage exec "${JAIL_NAME}" cp -f /mnt/configs/caddy /usr/local/etc/rc.d/

if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/my-system.cnf /var/db/mysql/my.cnf
fi
iocage exec "${JAIL_NAME}" sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/DNS-PLACEHOLDER/${DNS_SETTING}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s|mytimezone|${TIME_ZONE}|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_cert_email="${CERT_EMAIL}"
iocage exec "${JAIL_NAME}" sysrc caddy_env="${DNS_ENV}"

iocage restart "${JAIL_NAME}"

# Secure database, set root password, create Nextcloud DB, user, and password
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE nextcloud;"
  iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON nextcloud.* TO nextcloud@localhost IDENTIFIED BY '${DB_PASSWORD}';"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  iocage exec "${JAIL_NAME}" mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASSWORD}') WHERE User='root';"
  iocage exec "${JAIL_NAME}" mysqladmin reload
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/my.cnf /root/.my.cnf
  iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/configs/pgpass /root/.pgpass
  iocage exec "${JAIL_NAME}" chmod 600 /root/.pgpass
  iocage exec "${JAIL_NAME}" chown postgres /var/db/postgres/
  iocage exec "${JAIL_NAME}" /usr/local/etc/rc.d/postgresql initdb
  iocage exec "${JAIL_NAME}" su -m postgres -c '/usr/local/bin/pg_ctl -D /var/db/postgres/data10 start'
  iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.pgpass
  iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE DATABASE nextcloud;"
  iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE USER nextcloud WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
  iocage exec "${JAIL_NAME}" psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;"
  iocage exec "${JAIL_NAME}" psql -U postgres -c "SELECT pg_reload_conf();"
fi

# Save passwords for later reference
iocage exec "${JAIL_NAME}" echo "${DB_NAME} root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
iocage exec "${JAIL_NAME}" echo "Nextcloud Administrator password is ${ADMIN_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt

# CLI installation and configuration of Nextcloud
iocage exec "${JAIL_NAME}" touch /var/log/nextcloud.log
iocage exec "${JAIL_NAME}" chown www /var/log/nextcloud.log
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"mysql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/mysql.sock\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set mysql.utf8mb4 --type boolean --value=\"true\""
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"pgsql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/.s.PGSQL.5432\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
fi
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set logtimezone --value=\"${TIME_ZONE}\""
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set log_type --value="file"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logfile --value="/var/log/nextcloud.log"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set loglevel --value="2"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logrotate_size --value="104847600"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.local --value="\OC\Memcache\APCu"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis host --value="/tmp/redis.sock"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis port --value=0 --type=integer'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"'
if [ $NO_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"http://${HOST_NAME}/\""
else
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"https://${HOST_NAME}/\""
fi
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value=\"${HOST_NAME}\""
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value=\"${JAIL_IP}\""
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ app:enable encryption'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:enable'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:disable'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ background:cron'
iocage exec "${JAIL_NAME}" su -m www -c 'php -f /usr/local/www/nextcloud/cron.php'
iocage exec "${JAIL_NAME}" crontab -u www /mnt/configs/www-crontab

# Don't need /mnt/configs any more, so unmount it
iocage fstab -r "${JAIL_NAME}" "${CONFIGS_PATH}" /mnt/configs nullfs rw 0 0

# Done!
echo "Installation complete!"
if [ $NO_CERT -eq 1 ]; then
  echo "Using your web browser, go to http://${HOST_NAME} to log in"
else
  echo "Using your web browser, go to https://${HOST_NAME} to log in"
fi
echo "Default user is admin, password is ${ADMIN_PASSWORD}"
echo ""
echo "Database Information"
echo "--------------------"
echo "Database user = nextcloud"
echo "Database password = ${DB_PASSWORD}"
echo "The ${DB_NAME} root password is ${DB_ROOT_PASSWORD}"
echo ""
echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
echo ""
if [ $STANDALONE_CERT -eq 1 ] || [ $DNS_CERT -eq 1 ]; then
  echo "You have obtained your Let's Encrypt certificate using the staging server."
  echo "This certificate will not be trusted by your browser and will cause SSL errors"
  echo "when you connect.  Once you've verified that everything else is working"
  echo "correctly, you should issue a trusted certificate.  To do this, run:"
  echo "  iocage exec ${JAIL_NAME} /root/remove-staging.sh"
  echo ""
elif [ $SELFSIGNED_CERT -eq 1 ]; then
  echo "You have chosen to create a self-signed TLS certificate for your Nextcloud"
  echo "installation.  This certificate will not be trusted by your browser and"
  echo "will cause SSL errors when you connect.  If you wish to replace this certificate"
  echo "with one obtained elsewhere, the private key is located at:"
  echo "/usr/local/etc/pki/tls/private/privkey.pem"
  echo "The full chain (server + intermediate certificates together) is at:"
  echo "/usr/local/etc/pki/tls/certs/fullchain.pem"
  echo ""
fi
