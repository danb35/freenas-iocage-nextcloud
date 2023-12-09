#!/bin/sh
# Build an iocage jail under FreeNAS 11.3-13.0 using the current release of Nextcloud 26
# https://github.com/danb35/freenas-iocage-nextcloud

# set -x

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

#####
#
# General configuration
#
#####

# Initialize defaults
JAIL_IP=""
JAIL_INTERFACES=""
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
CONFIG_PATH=""
THEMES_PATH=""
STANDALONE_CERT=0
SELFSIGNED_CERT=0
DNS_CERT=0
NO_CERT=0
CERT_EMAIL=""
DL_FLAGS=""
DNS_SETTING=""
CONFIG_NAME="nextcloud-config"
NEXTCLOUD_VERSION="27"
COUNTRY_CODE="US"
JAIL_BASEJAIL="false"
PGP_KEYSERVER="pgpkeys.eu"
NEXTCLOUD_PGP_KEYID="28806A878AE423A28372792ED75899B9A724937A"

# Check for nextcloud-config and set configuration
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "${SCRIPT}")
if ! [ -e "${SCRIPTPATH}"/"${CONFIG_NAME}" ]; then
  echo "${SCRIPTPATH}/${CONFIG_NAME} must exist."
  exit 1
fi
. "${SCRIPTPATH}"/"${CONFIG_NAME}"
INCLUDES_PATH="${SCRIPTPATH}"/includes

ADMIN_PASSWORD=$(openssl rand -base64 12)
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
if [ "${DATABASE}" = "mariadb" ]; then
  DB_NAME="MariaDB"
elif [ "${DATABASE}" = "pgsql" ]; then
  DB_NAME="PostgreSQL"
fi

RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
# If release is 13.1-RELEASE, change to 13.2-RELEASE
if [ "${RELEASE}" = "13.1-RELEASE" ]; then
  RELEASE="13.2-RELEASE"
fi 
JAILS_MOUNT=$(zfs get -H -o value mountpoint $(iocage get -p)/iocage)

#####
#
# Input/Config Sanity checks
#
#####

# Check that necessary variables were set by nextcloud-config
if [ -z "${JAIL_IP}" ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z "${JAIL_INTERFACES}" ]; then
  echo 'JAIL_INTERFACES not set, defaulting to: vnet0:bridge0'
  JAIL_INTERFACES="vnet0:bridge0"
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
  echo "See https://caddyserver.com/download for available plugins."
  echo "Use only the last part of the name.  E.g., for"
  echo "\"github.com/caddy-dns/cloudflare\", enter \"coudflare\"."
  exit 1
fi

if [ $DNS_CERT -eq 1 ] && [ "${CERT_EMAIL}" = "" ] ; then
  echo "CERT_EMAIL must be set when using Let's Encrypt certs."
  exit 1
fi

if [ $STANDALONE_CERT -eq 1 ] && [ "${CERT_EMAIL}" = "" ] ; then
  echo "CERT_EMAIL must be set when using Let's Encrypt certs."
  exit 1
fi

# If DB_PATH, FILES_PATH, CONFIG_PATH and PORTS_PATH weren't set in nextcloud-config, set them
if [ -z "${DB_PATH}" ]; then
  DB_PATH="${POOL_PATH}"/nextcloud/db
fi
if [ -z "${FILES_PATH}" ]; then
  FILES_PATH="${POOL_PATH}"/nextcloud/files
fi
if [ -z "${CONFIG_PATH}" ]; then
  CONFIG_PATH="${POOL_PATH}"/nextcloud/config
fi
if [ -z "${THEMES_PATH}" ]; then
  THEMES_PATH="${POOL_PATH}"/nextcloud/themes
fi
if [ -z "${PORTS_PATH}" ]; then
  PORTS_PATH="${POOL_PATH}"/portsnap
fi

# Sanity check DB_PATH, FILES_PATH, and PORTS_PATH -- they all have to be different,
# and can't be the same as POOL_PATH
if [ "${DB_PATH}" = "${FILES_PATH}" ] || [ "${FILES_PATH}" = "${PORTS_PATH}" ] || [ "${PORTS_PATH}" = "${DB_PATH}" ] || [ "${CONFIG_PATH}" = "${FILES_PATH}" ] || [ "${CONFIG_PATH}" = "${PORTS_PATH}" ] || [ "${CONFIG_PATH}" = "${DB_PATH}" ]
then
  echo "DB_PATH, FILES_PATH, CONFIG_PATH and PORTS_PATH must all be different!"
  exit 1
elif [ "${THEMES_PATH}" = "${PORTS_PATH}" ] || [ "${THEMES_PATH}" = "${DB_PATH}" ] || [ "${THEMES_PATH}" = "${CONFIG_PATH}" ]
then
  echo "DB_PATH, FILES_PATH, CONFIG_PATH, THEMES_PATH and PORTS_PATH must all be different!"
  exit 1
fi

if [ "${DB_PATH}" = "${POOL_PATH}" ] || [ "${FILES_PATH}" = "${POOL_PATH}" ] || [ "${PORTS_PATH}" = "${POOL_PATH}" ] || [ "${CONFIG_PATH}" = "${POOL_PATH}" ] || [ "${THEMES_PATH}" = "${POOL_PATH}" ]
then
  echo "DB_PATH, FILES_PATH, CONFIG_PATH, THEMES_PATH and PORTS_PATH must all be different from POOL_PATH!"
  exit 1
fi

# Extract IP and netmask, sanity check netmask
IP=$(echo ${JAIL_IP} | cut -f1 -d/)
NETMASK=$(echo ${JAIL_IP} | cut -f2 -d/)
if [ "${NETMASK}" = "${IP}" ]
then
  NETMASK="24"
fi
if [ "${NETMASK}" -lt 8 ] || [ "${NETMASK}" -gt 30 ]
then
  NETMASK="24"
fi

# Check for reinstall
if [ "$(ls -A "${CONFIG_PATH}")" ]; then
	echo "Existing Nextcloud config detected... Checking Database compatibility for reinstall"
	if [ "$(ls -A "${DB_PATH}/${DATABASE}")" ]; then
		echo "Database is compatible, continuing..."
		REINSTALL="true"
	else
		echo "ERROR: You can not reinstall without the previous database"
		echo "Please try again after removing your config files or using the same database used previously"
		exit 1
	fi
fi

#####
#
# Jail Creation
#
#####

# List packages to be auto-installed after jail creation
# PHP Modules listed in order, as seen on "Installation of Linux" in Nextcloud Documentation
# Notes: The php-hash and the php-json modules are part of PHP Core.
#        There is no php-libxml module for FreeBSD, instead we install php-xml
#        The last three modules (iconv, xsl, opcache) are not listed in the documentation for Nextcloud 23
#        Keeping them because original author put them there
cat <<__EOF__ >/tmp/pkg.json
{
  "pkgs": [
    "nano",
    "sudo",
    "vim",
    "redis",
    "gnupg",
    "bash",
    "go",
    "git",
    "ffmpeg",
    "perl5",
    "p5-Locale-gettext",
    "help2man",
    "texinfo",
    "m4",
    "autoconf",
    "php82",
    "php82-ctype",
    "php82-curl",
    "php82-dom",
    "php82-filter",
    "php82-gd",
    "php82-xml",
    "php82-mbstring",
    "php82-posix",
    "php82-session",
    "php82-simplexml",
    "php82-xmlreader",
    "php82-xmlwriter",
    "php82-zip",
    "php82-zlib",
    "php82-fileinfo",
    "php82-bz2",
    "php82-intl",
    "php82-ldap",
    "php82-pecl-smbclient",
    "php82-ftp",
    "php82-imap",
    "php82-bcmath",
    "php82-gmp",
    "php82-exif",
    "php82-pecl-APCu",
    "php82-pecl-memcache",
    "php82-pecl-redis",
    "php82-pecl-imagick",
    "php82-pcntl",
    "php82-phar",
    "php82-iconv",
    "php82-sysvsem",
    "php82-xsl",
    "php82-opcache"
  ]
}
__EOF__

# Create the jail and install previously listed packages
if [ "${JAIL_BASEJAIL}" = "true" ]; then
    JAIL_TYPE_OPTION="--basejail"
else
    JAIL_TYPE_OPTION=""
fi

if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" interfaces="${JAIL_INTERFACES}" ip4_addr="${INTERFACE}|${IP}/${NETMASK}" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" "${JAIL_TYPE_OPTION}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#####
#
# Directory Creation and Mounting
#
#####

mkdir -p "${DB_PATH}"/"${DATABASE}"
chown -R 88:88 "${DB_PATH}"/
mkdir -p "${FILES_PATH}"
chown -R 80:80 "${FILES_PATH}"
mkdir -p "${CONFIG_PATH}"
mkdir -p "${THEMES_PATH}"
# Ports not currently used, Commented out for future use
#mkdir -p "${PORTS_PATH}"/ports
#mkdir -p "${PORTS_PATH}"/db
iocage exec "${JAIL_NAME}" mkdir -p /mnt/files
if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /var/db/mysql
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /var/db/postgres
fi
iocage exec "${JAIL_NAME}" mkdir -p /mnt/includes
iocage exec "${JAIL_NAME}" mkdir -p /mnt/files
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/nextcloud/config
iocage exec "${JAIL_NAME}" mkdir -p /usr/local/www/nextcloud/themes

# Ports not currently used, Commented out for future use
#mkdir -p "${JAILS_MOUNT}"/jails/${JAIL_NAME}/root/var/db/portsnap
#mkdir -p "${JAILS_MOUNT}"/jails/${JAIL_NAME}/root/usr/ports
#iocage fstab -a "${JAIL_NAME}" "${PORTS_PATH}"/ports /usr/ports nullfs rw 0 0
#iocage fstab -a "${JAIL_NAME}" "${PORTS_PATH}"/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a "${JAIL_NAME}" "${FILES_PATH}" /mnt/files nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${CONFIG_PATH}" /usr/local/www/nextcloud/config nullfs rw 0 0
iocage fstab -a "${JAIL_NAME}" "${THEMES_PATH}" /usr/local/www/nextcloud/themes nullfs rw 0 0
if [ "${DATABASE}" = "mariadb" ]; then
  mkdir -p "${JAILS_MOUNT}"/jails/${JAIL_NAME}/root/var/db/mysql
  iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"/"${DATABASE}" /var/db/mysql  nullfs  rw  0  0
elif [ "${DATABASE}" = "pgsql" ]; then
  mkdir -p "${JAILS_MOUNT}"/jails/${JAIL_NAME}/root/var/db/postgres
  iocage fstab -a "${JAIL_NAME}" "${DB_PATH}"/"${DATABASE}" /var/db/postgres  nullfs  rw  0  0
fi
iocage fstab -a "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0
iocage exec "${JAIL_NAME}" chown -R www:www /mnt/files
iocage exec "${JAIL_NAME}" chmod -R 770 /mnt/files


#####
#
# Additional Dependency installation
#
#####

if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" pkg install -y mariadb106-server php82-pdo_mysql php82-mysqli
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" pkg install -y postgresql13-server php82-pgsql php82-pdo_pgsql
fi

# Ports not currently used, Commented out for future use
#iocage exec "${JAIL_NAME}" "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"

# Build xcaddy, use it to build Caddy
if ! iocage exec "${JAIL_NAME}" "go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest"
then
  echo "Failed to get xcaddy, terminating."
  exit 1
fi
if ! iocage exec "${JAIL_NAME}" cp /root/go/bin/xcaddy /usr/local/bin/xcaddy
then
  echo "Failed to move xcaddy to path, terminating."
  exit 1
fi
if [ ${DNS_CERT} -eq 1 ]; then
  if ! iocage exec "${JAIL_NAME}" xcaddy build --output /usr/local/bin/caddy --with github.com/caddy-dns/"${DNS_PLUGIN}"
  then
    echo "Failed to build Caddy with ${DNS_PLUGIN} plugin, terminating."
    exit 1
  fi  
else
  if ! iocage exec "${JAIL_NAME}" xcaddy build --output /usr/local/bin/caddy
  then
    echo "Failed to build Caddy without plugin, terminating."
    exit 1
  fi  
fi

#####
#
# Webserver Setup and Nextcloud Download  
#
#####

FILE="latest-${NEXTCLOUD_VERSION}.tar.bz2"
if ! iocage exec "${JAIL_NAME}" fetch -o /tmp https://download.nextcloud.com/server/releases/"${FILE}" https://download.nextcloud.com/server/releases/"${FILE}".asc 
then
	echo "Failed to download Nextcloud"
	exit 1
fi
if iocage exec "${JAIL_NAME}" fetch -o /tmp https://nextcloud.com/nextcloud.asc
then
    iocage exec "${JAIL_NAME}" gpg --import /tmp/nextcloud.asc
else
    if ! iocage exec "${JAIL_NAME}" gpg --keyserver "${PGP_KEYSERVER}" --recv-key "${NEXTCLOUD_PGP_KEYID}"
    then
	echo "Failed to download Nextcloud GPG signing key"
	exit 1
    fi
fi
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


# Generate and install self-signed cert, if necessary
if [ $SELFSIGNED_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pki/tls/private
  iocage exec "${JAIL_NAME}" mkdir -p /usr/local/etc/pki/tls/certs
  openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=${HOST_NAME}" -keyout "${INCLUDES_PATH}"/privkey.pem -out "${INCLUDES_PATH}"/fullchain.pem
  iocage exec "${JAIL_NAME}" cp /mnt/includes/privkey.pem /usr/local/etc/pki/tls/private/privkey.pem
  iocage exec "${JAIL_NAME}" cp /mnt/includes/fullchain.pem /usr/local/etc/pki/tls/certs/fullchain.pem
fi

# Copy and edit pre-written config files
if ! iocage exec "${JAIL_NAME}" cp -f /mnt/includes/php.ini /usr/local/etc/php.ini
then
	echo "Failed to copy php.ini"
	exit 1
fi
iocage exec "${JAIL_NAME}" chown -R www:www /usr/local/etc/php.ini
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/redis.conf /usr/local/etc/redis.conf
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/www.conf /usr/local/etc/php-fpm.d/
if [ $STANDALONE_CERT -eq 1 ] || [ $DNS_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/remove-staging.sh /root/
fi
if [ $NO_CERT -eq 1 ]; then
  echo "Copying Caddyfile for no SSL"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile-nossl /usr/local/www/Caddyfile
elif [ $SELFSIGNED_CERT -eq 1 ]; then
  echo "Copying Caddyfile for self-signed cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile-selfsigned /usr/local/www/Caddyfile
elif [ $DNS_CERT -eq 1 ]; then
  echo "Copying Caddyfile for Let's Encrypt DNS cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile-dns /usr/local/www/Caddyfile
else
  echo "Copying Caddyfile for Let's Encrypt cert"
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/Caddyfile /usr/local/www/
fi
iocage exec "${JAIL_NAME}" cp -f /mnt/includes/caddy /usr/local/etc/rc.d/

if [ "${DATABASE}" = "mariadb" ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my-system.cnf /usr/local/etc/mysql/conf.d/nextcloud.cnf
fi
iocage exec "${JAIL_NAME}" sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/www/Caddyfile
#iocage exec "${JAIL_NAME}" sed -i '' "s/DNS-PLACEHOLDER/${DNS_SETTING}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/dns_plugin/${DNS_PLUGIN}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/api_token/${DNS_TOKEN}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/jail_ip/${IP}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s/youremailhere/${CERT_EMAIL}/" /usr/local/www/Caddyfile
iocage exec "${JAIL_NAME}" sed -i '' "s|mytimezone|${TIME_ZONE}|" /usr/local/etc/php.ini

iocage exec "${JAIL_NAME}" sysrc caddy_enable="YES"
iocage exec "${JAIL_NAME}" sysrc caddy_config="/usr/local/www/Caddyfile"

iocage restart "${JAIL_NAME}"

#####
#
# Nextcloud Install 
#
#####

iocage exec "${JAIL_NAME}" touch /var/log/nextcloud.log
iocage exec "${JAIL_NAME}" chown www /var/log/nextcloud.log

# Add the www user to the redis group to allow it to access the socket
iocage exec "${JAIL_NAME}" pw usermod www -G redis
iocage exec "${JAIL_NAME}" chmod 777 /var/run/redis/redis.sock

# Skip generation of config and database for reinstall (this already exists when doing a reinstall)
if [ "${REINSTALL}" == "true" ]; then
	echo "Reinstall detected, skipping generation of new config and database"
	if [ "${DATABASE}" = "mariadb" ]; then
	iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
	iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
	fi
else

# Secure database, set root password, create Nextcloud DB, user, and password
if [ "${DATABASE}" = "mariadb" ]; then
  if ! iocage exec "${JAIL_NAME}" mysql -u root -e "CREATE DATABASE nextcloud;"
  then
    echo "Failed to create MariaDB database, aborting"
    exit 1
  fi
  iocage exec "${JAIL_NAME}" mysql -u root -e "GRANT ALL ON nextcloud.* TO nextcloud@localhost IDENTIFIED BY '${DB_PASSWORD}';"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DROP DATABASE IF EXISTS test;"
  iocage exec "${JAIL_NAME}" mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  iocage exec "${JAIL_NAME}" mysqladmin --user=root password "${DB_ROOT_PASSWORD}" reload
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/my.cnf /root/.my.cnf
  iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf
elif [ "${DATABASE}" = "pgsql" ]; then
  iocage exec "${JAIL_NAME}" cp -f /mnt/includes/pgpass /root/.pgpass
  iocage exec "${JAIL_NAME}" chmod 600 /root/.pgpass
  iocage exec "${JAIL_NAME}" chown postgres /var/db/postgres/
  iocage exec "${JAIL_NAME}" /usr/local/etc/rc.d/postgresql initdb
  iocage exec "${JAIL_NAME}" su -m postgres -c '/usr/local/bin/pg_ctl -D /var/db/postgres/data13 start'
  iocage exec "${JAIL_NAME}" sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.pgpass
  if ! iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE DATABASE nextcloud;"
  then
    echo "Failed to create PostgreSQL database, aborting"
    exit 1
  fi
  iocage exec "${JAIL_NAME}" psql -U postgres -c "CREATE USER nextcloud WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';"
  iocage exec "${JAIL_NAME}" psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;"
  iocage exec "${JAIL_NAME}" psql -U postgres -c "SELECT pg_reload_conf();"
fi

# Save passwords for later reference
echo "${DB_NAME} root password is ${DB_ROOT_PASSWORD}" > /root/${JAIL_NAME}_db_password.txt
echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt
echo "Nextcloud Administrator password is ${ADMIN_PASSWORD}" >> /root/${JAIL_NAME}_db_password.txt

# Create Nextcloud log directory
iocage exec "${JAIL_NAME}" mkdir -p /var/log/nextcloud/
iocage exec "${JAIL_NAME}" chown www:www /var/log/nextcloud

# CLI installation and configuration of Nextcloud

if [ "${DATABASE}" = "mariadb" ]; then
  if ! iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"mysql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/var/run/mysql/mysql.sock\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
  then
    echo "Failed to install Nextcloud, aborting"
    exit 1
  fi
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set mysql.utf8mb4 --type boolean --value=\"true\""
elif [ "${DATABASE}" = "pgsql" ]; then
  if ! iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ maintenance:install --database=\"pgsql\" --database-name=\"nextcloud\" --database-user=\"nextcloud\" --database-pass=\"${DB_PASSWORD}\" --database-host=\"localhost:/tmp/.s.PGSQL.5432\" --admin-user=\"admin\" --admin-pass=\"${ADMIN_PASSWORD}\" --data-dir=\"/mnt/files\""
  then
    echo "Failed to install Nextcloud, aborting"
    exit 1
  fi
fi
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:add-missing-indices"
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ db:convert-filecache-bigint --no-interaction"
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set logtimezone --value=\"${TIME_ZONE}\""
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set default_phone_region --value=\"${COUNTRY_CODE}\""
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set log_type --value="file"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logfile --value="/var/log/nextcloud/nextcloud.log"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set loglevel --value="2"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set logrotate_size --value="104847600"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.local --value="\OC\Memcache\APCu"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis host --value="/var/run/redis/redis.sock"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set redis port --value=0 --type=integer'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.distributed --value="\OC\Memcache\Redis"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set memcache.locking --value="\OC\Memcache\Redis"'
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwritehost --value=\"${HOST_NAME}\""
if [ $NO_CERT -eq 1 ]; then
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"http://${HOST_NAME}/\""
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwriteprotocol --value=\"http\""
else
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwrite.cli.url --value=\"https://${HOST_NAME}/\""
  iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set overwriteprotocol --value=\"https\""
fi
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ config:system:set htaccess.RewriteBase --value="/"'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ maintenance:update:htaccess'
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 1 --value=\"${HOST_NAME}\""
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_domains 2 --value=\"${IP}\""
iocage exec "${JAIL_NAME}" su -m www -c "php /usr/local/www/nextcloud/occ config:system:set trusted_proxies 1 --value=\"localhost\""
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ app:enable encryption'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:enable'
#iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ encryption:disable'
iocage exec "${JAIL_NAME}" su -m www -c 'php /usr/local/www/nextcloud/occ background:cron'
fi

iocage exec "${JAIL_NAME}" su -m www -c 'php -f /usr/local/www/nextcloud/cron.php'
iocage exec "${JAIL_NAME}" crontab -u www /mnt/includes/www-crontab


# Don't need /mnt/includes any more, so unmount it
iocage fstab -r "${JAIL_NAME}" "${INCLUDES_PATH}" /mnt/includes nullfs rw 0 0

#####
#
# Output results to console
#
#####

# Done!
echo "Installation complete!"
if [ $NO_CERT -eq 1 ]; then
  echo "Using your web browser, go to http://${HOST_NAME} to log in"
else
  echo "Using your web browser, go to https://${HOST_NAME} to log in"
fi

if [ "${REINSTALL}" == "true" ]; then
	echo "You did a reinstall, please use your old database and account credentials"
else

	echo "Default user is admin, password is ${ADMIN_PASSWORD}"
	echo ""
	echo "Database Information"
	echo "--------------------"
	echo "Database user = nextcloud"
	echo "Database password = ${DB_PASSWORD}"
	echo "The ${DB_NAME} root password is ${DB_ROOT_PASSWORD}"
	echo ""
	echo "All passwords are saved in /root/${JAIL_NAME}_db_password.txt"
fi

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

