# freenas-iocage-nextcloud
Script to create an iocage jail on FreeNAS for the latest Nextcloud 14 release, including Apache 2.4.x, MariaDB 10.1/PostgreSQL 10, and Let's Encrypt

This script will create an iocage jail on FreeNAS 11.1 or 11.2 with the latest release of Nextcloud 14, along with its dependencies.  It will obtain a trusted certificate from Let's Encrypt for the system, install it, and configure it to renew automatically.  It will create the Nextcloud database and generate a strong root password and user password for the database system.  It will configure the jail to store the database and Nextcloud user data outside the jail, so it will not be lost in the event you need to rebuild the jail.

## Status
This script has been tested on FreeNAS 11.1-U2 and appears to be working without issue.  It is known to NOT work on 11.1-U3 or 11.1-U4 out of the box. 11.1-U3 has a version of iocage with a bug in the jail creation script. This can be fixed by using the following commands.

```
cd /tmp
git clone --recursive https://github.com/iocage/iocage
cp -R iocage/iocage/lib/ /usr/local/lib/python3.6/site-packages/iocage/lib
```
This script also appears to work without issue on FreeNAS 11.2-BETA1, BETA2, and BETA3.

## Usage

### Prerequisites
Although not required, it's recommended to create two datasets on your main storage pool: one named `files`, which will store the Nextcloud user data; and one called `db`, which will store the SQL database.  For optimal performance, set the record size of the `db` dataset to 16 KB (under Advanced Settings).

### Installation
Download the repository to a convenient directory on your FreeNAS system by running `git clone https://github.com/danb35/freenas-iocage-nextcloud`.  Then change into the new directory and create a file called `nextcloud-config`.  It should look like this:
```
JAIL_IP="192.168.1.199"
DEFAULT_GW_IP="192.168.1.1"
INTERFACE="igb0"
VNET="off"
POOL_PATH="/mnt/tank"
JAIL_NAME="nextcloud"
TIME_ZONE="America/New_York" # See http://php.net/manual/en/timezones.php
HOST_NAME="YOUR_FQDN"
DATABASE="mariadb"
STANDALONE_CERT=0
DNS_CERT=0
SELFSIGNED_CERT=0
NO_CERT=0
TEST_CERT="--test"
```
Many of the options are self-explanatory, and all should be adjusted to suit your needs.  JAIL_IP and DEFAULT_GW_IP are the IP address and default gateway, respectively, for your jail.  INTERFACE is the network interface that your FreeNAS server is actually using.  If you have multiple interfaces, run `ifconfig` and see which one has an IP address, and enter that one here. If you want to use a virtual non-shared IP, pick a unused name as your interface and set VNET to ''on''  POOL_PATH is the path for your data pool, on which the Nextcloud user data and SQL database will be stored.  JAIL_NAME is the name of the jail, and wouldn't ordinarily need to be changed.  If you don't specify it in nextcloud-config, JAIL_NAME will default to "nextcloud".  TIME_ZONE is the time zone of your location, as PHP sees it--see the [PHP manual](http://php.net/manual/en/timezones.php) for a list of all valid time zones.

HOST_NAME is the fully-qualified domain name you want to assign to your installation.  You must own (or at least control) this domain, because Let's Encrypt will test that control.  STANDALONE_CERT and DNS_CERT control which validation method Let's Encrypt will use to do this.  If HOST_NAME is accessible to the outside world--that is, you have ports 80 and 443 (at least) forwarded to your jail, so that if an outside user browses to http://HOST_NAME/, he'll reach your jail--set STANDALONE_CERT to 1, and DNS_CERT to 0.  If HOST_NAME is not accessible to the outside world, but your DNS provider has an API that allows you to make automated changes, set DNS_CERT to 1, and STANDALONE_CERT to 0.  In that case, you'll also need to copy `configs/acme_dns_issue.sh_orig` to `configs/acme_dns_issue.sh`, edit its contents appropriately, and make it executable (`chmod +x configs/acme_dns_issue.sh`).

DATABASE is the type of database you want to use. By default MariaDB is used since it is recommended for use with Nextcloud, but PostgreSQL is also supported and might be faster in some cases. It even has native 4-byte support meaning that it supports characters like Emoji's by default while this is still an experimental feature with MariDB. The only possible downside is that maybe some apps don't support anything other than MySQL/MariaDB, but everything in the Nextcloud app store does! This makes it a non-issue for most users, but if you use apps that cant be installed from the Nextcloud app store, look up if they support PostgreSQL.
Change the option to `pgsql` if you want to use PostgreSQL.
Converting the database later on is possible, but it's not easy and not recommended.

If you are unable or unwilling to use a Let's Encrypt certificate, you can instead create a self-signed certificate by setting SELFSIGNED_CERT to 1.  If you want to provide your own certificate (from another certificate authority, or from Cloudflare, for example), you should also set SELFSIGNED_CERT to 1, and then replace the self-signed certificate with your own certificate once the jail is created.

Finally, if you don't want to implement SSL in the jail at all, you can set NO_CERT to 1.  If your jail is behind a proxy that handles SSL, this might make sense.

**IMPORTANT:**  One of the four CERT variables must be set to 1.  Otherwise, the script will refuse to run.

DB_PATH, FILES_PATH, and PORTS_PATH can optionally be set to individual paths for your SQL database, your Nextcloud files, and your FreeBSD ports collection.  If not set, they'll default to $POOL_PATH/db, $POOL_PATH/files, and $POOL_PATH/portsnap, respectively.  These do not need to be set in nextcloud-config, and **should not be set** unless you want the SQL database, your Nextcloud files, and/or your ports collection to be in a non-standard location.

Finally, TEST_CERT is a flag to issue test certificates from Let's Encrypt.  They'll run through the same issuance process in the same, but will come from an un-trusted certificate authority (so you'll get a warning when you first visit your site).  For test purposes, I recommend you set this to "--test" as above, otherwise the [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) may prevent issuing the cert when you most want it.  Once you've confirmed that everything is working properly, you can set TEST_CERT to "".  Unless you set TEST_CERT to "" in nextcloud-config, it will default to "--test".

It's also helpful if HOST_NAME resolves to your jail from **inside** your network.  You'll probably need to configure this on your router.  If it doesn't, you'll still be able to reach your Nextcloud installation via the jail's IP address, but you'll get certificate errors that way.

### Execution
Once you've downloaded the script, prepared the configuration file, and (if applicable) made the necessary edits to `configs/acme_dns_issue.sh`, run this script (`./nextcloud-jail.sh`).  The script will run for several minutes.  When it finishes, your jail will be created, Nextcloud will be installed and configured, and you'll be shown the randomly-generated password for the default user ("admin").  You can then log in and create users, add data, and generally do whatever else you like.

### To Do
This script has been tested on a few different systems, obtaining the cert in both DNS and Standalone mode, and everything seems to be working properly.  Further testing is, of course, always appreciated.

I'd also appreciate any suggestions (or pull requests) to improve the various config files I'm using.  Most of them are adapted from the default configuration files that ship with the software in question, and have only been lightly edited to work in this application.  But if there are changes to settings or organization that could improve performance or reliability, I'd like to hear about them.
