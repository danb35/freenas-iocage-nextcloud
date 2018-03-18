#!/bin/sh
# Build an iocage jail under FreeNAS 11.1 using the current release of Nextcloud 13

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/nextcloud-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)

echo '{"pkgs":["nano","curl","sudo","apache24","mariadb101-server","redis","php72-ctype","php72-dom","php72-gd","php72-iconv","php72-json","php72-mbstring","php72-posix","php72-simplexml","php72-xmlreader","php72-xmlwriter","php72-zip","php72-zlib","php72-pdo_mysql","php72-hash","php72-xml","php72-session","php72-mysqli","php72-wddx","php72-xsl","php72-filter","php72-curl","php72-fileinfo","php72-bz2","php72-intl","php72-openssl","php72-ldap","php72-ftp","php72-imap","php72-exif","php72-gmp","php72-memcache","php72-opcache","php72-pcntl","php72","mod_php72","bash","p5-Locale-gettext","help2man","texinfo","m4","autoconf","socat","git"]}' > /tmp/pkg.json

iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r 11.1-RELEASE ip4_addr="vnet0|${JAIL_IP}/24" vnet="on" allow_raw_sockets="1" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}"
rm /tmp/pkg.json
mkdir -p ${POOL_PATH}/db/
chown -R 88:88 ${POOL_PATH}/db/
mkdir -p ${POOL_PATH}/files
chown -R 80:80 ${POOL_PATH}/files
mkdir -p ${POOL_PATH}/portsnap/ports
mkdir -p ${POOL_PATH}/portsnap/db
iocage exec ${JAIL_NAME} mkdir -p /mnt/files
iocage exec ${JAIL_NAME} mkdir -p /var/db/mysql
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/portsnap/ports /usr/ports nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/portsnap/db /var/db/portsnap nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/files /mnt/files nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/db  /var/db/mysql  nullfs  rw  0  0
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage exec ${JAIL_NAME} chown -R www:www /mnt/files
iocage exec ${JAIL_NAME} chmod -R 770 /mnt/files
iocage exec ${JAIL_NAME} "if [ -z /usr/ports ]; then portsnap fetch extract; else portsnap auto; fi"
iocage exec ${JAIL_NAME} chsh -s /usr/local/bin/bash root
iocage exec ${JAIL_NAME} fetch -o /tmp https://download.nextcloud.com/server/releases/latest-13.tar.bz2
iocage exec ${JAIL_NAME} tar xjfv /tmp/latest-13.tar.bz2 -C /usr/local/www/apache24/data/
iocage exec ${JAIL_NAME} chown -R www:www /usr/local/www/apache24/data/nextcloud/
iocage exec ${JAIL_NAME} sysrc apache24_enable="YES"
iocage exec ${JAIL_NAME} sysrc mysql_enable="YES"
iocage exec ${JAIL_NAME} sysrc redis_enable="YES"
iocage exec ${JAIL_NAME} make -C /usr/ports/databases/pecl-redis clean install BATCH=yes
iocage exec ${JAIL_NAME} make -C /usr/ports/devel/pecl-APCu clean install BATCH=yes
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pki/tls/certs/
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pki/tls/private/
iocage exec ${JAIL_NAME} touch /usr/local/etc/pki/tls/private/privkey.pem
iocage exec ${JAIL_NAME} chmod 600 /usr/local/etc/pki/tls/private/privkey.pem
iocage exec ${JAIL_NAME} curl https://get.acme.sh -o /tmp/get-acme.sh
iocage exec ${JAIL_NAME} sh /tmp/get-acme.sh
iocage exec ${JAIL_NAME} rm /tmp/get-acme.sh

if [ $STANDALONE_CERT -eq 1 ]; then
  iocage exec ${JAIL_NAME} /root/.acme.sh/acme.sh --issue --home "/root/.acme.sh" --standalone -d ${HOST_NAME} --fullchain-file /usr/local/etc/pki/tls/certs/fullchain.pem --key-file /usr/local/etc/pki/tls/private/privkey.pem
fi

if [ $DNS_CERT -eq 1 ]; then
  iocage exec ${JAIL_NAME} /mnt/configs/acme_dns_issue.sh
fi

# Copy pre-written config files
iocage exec ${JAIL_NAME} cp -f /mnt/configs/httpd.conf /usr/local/etc/apache24/httpd.conf
iocage exec ${JAIL_NAME} cp -f /mnt/configs/php.ini /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} cp -f /mnt/configs/redis.conf /usr/local/etc/redis.conf
iocage exec ${JAIL_NAME} cp -f /mnt/configs/001_mod_php.conf /usr/local/etc/apache24/modules.d/001_mod_php.conf
iocage exec ${JAIL_NAME} cp -f /mnt/configs/nextcloud.conf /usr/local/etc/apache24/Includes/${HOST_NAME}.conf
iocage exec ${JAIL_NAME} cp -f /usr/local/share/mysql/my-small.cnf /var/db/mysql/my.cnf
iocage exec ${JAIL_NAME} sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/etc/apache24/Includes/${HOST_NAME}.conf
iocage exec ${JAIL_NAME} sed -i '' "s/yourhostnamehere/${HOST_NAME}/" /usr/local/etc/apache24/httpd.conf
iocage exec ${JAIL_NAME} sed -i '' "s/#skip-networking/skip-networking/" /var/db/mysql/my.cnf
iocage exec ${JAIL_NAME} sed -i '' "s|mytimezone|${TIME_ZONE}|" /usr/local/etc/php.ini
iocage restart ${JAIL_NAME}

iocage exec ${JAIL_NAME} mysql -u root -e "CREATE DATABASE nextcloud;"
iocage exec ${JAIL_NAME} mysql -u root -e "GRANT ALL ON nextcloud.* TO nextcloud@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
iocage exec ${JAIL_NAME} mysql -u root -e "DROP DATABASE IF EXISTS test;"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
iocage exec ${JAIL_NAME} mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASSWORD}') WHERE User='root';"
iocage exec ${JAIL_NAME} mysqladmin reload

iocage exec ${JAIL_NAME} cp -f /mnt/configs/my.cnf /root/.my.cnf
iocage exec ${JAIL_NAME} sed -i '' "s|mypassword|${DB_ROOT_PASSWORD}|" /root/.my.cnf

iocage exec ${JAIL_NAME} echo "MySQL root password is ${DB_ROOT_PASSWORD}" > /root/db_password.txt
iocage exec ${JAIL_NAME} echo "Nextcloud database password is ${DB_PASSWORD}" >> /root/db_password.txt

echo "Installation complete!"
echo "Using your web browser, go to https://${HOST_NAME} to configure"
echo "Be sure to choose a strong password for the admin user"
echo ""
echo "Database Information"
echo "--------------------"
echo "Database user = nextcloud"
echo "Database password = ${DB_PASSWORD}"
echo "Database name = nextcloud"
echo "Database host = localhost:/tmp/mysql.sock"
echo ""
echo "The MariaDB root password is ${DB_ROOT_PASSWORD}"
echo "Both database passwords are saved in /root/db_password.txt"
