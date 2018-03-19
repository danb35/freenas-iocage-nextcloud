# freenas-iocage-nextcloud
Script to create an iocage jail on FreeNAS for the latest Nextcloud 13 release, including Apache 2.4.x, MariaDB, and Let's Encrypt

This script will create an iocage jail on FreeNAS 11.1 with the latest release of Nextcloud 13, along with its dependencies.  It will obtain a trusted certificate from Let's Encrypt for the system, install it, and configure it to renew automatically.  It will create the Nextcloud database and generate a strong root password and user password for the database system.  It will configure the jail to store the database and Nextcloud user data outside the jail, so it will not be lost in the event you need to rebuild the jail.

## Usage

### Prerequisites
Although not required, it's recommended to create two datasets on your main storage pool: one named `files`, which will store the Nextcloud user data; and one called `db`, which will store the MariaDB database.  For optimal performance, set the record size of the `db` dataset to 16 KB (under Advanced Settings).

### Installation
Download the repository to a convenient directory on your FreeNAS system by running `git clone https://github.com/danb35/freenas-iocage-nextcloud`.  Then change into the new directory and create a file called `nextcloud-config`.  It should look like this:
```
JAIL_IP="192.168.1.199"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
JAIL_NAME="nextcloud"
TIME_ZONE="America/New_York" # See http://php.net/manual/en/timezones.php
HOST_NAME="YOUR_FQDN"
STANDALONE_CERT=0
DNS_CERT=0
```
Many of the options are self-explanatory, and all should be adjusted to suit your needs.  JAIL_IP and DEFAULT_GW_IP are the IP address and default gateway, respectively, for your jail.  POOL_PATH is the path for your data pool, on which the Nextcloud user data and MariaDB database will be stored.  JAIL_NAME is the name of the jail, and wouldn't ordinarily need to be changed.  TIME_ZONE is the time zone of your location, as PHP sees it--see the link above for a list of all valid time zone expressions.

HOST_NAME is the fully-qualified domain name you want to assign to your installation.  You must own (or at least control) this domain, because Let's Encrypt will test that control.  STANDALONE_CERT and DNS_CERT control which validation method Let's Encrypt will use to do this.  If HOST_NAME is accessible to the outside world--that is, you have ports 80 and 443 (at least) forwarded to your jail, so that if an outside user browses to http://HOST_NAME/, he'll reach your jail--set STANDALONE_CERT to 1, and DNS_CERT to 0.  If HOST_NAME is not accessible to the outside world, but your DNS provider has an API that allows you to make automated changes, set DNS_CERT to 1, and STANDALONE_CERT to 0.  In that case, you'll also need to copy `configs/acme_dns_issue.sh_orig` to `configs/acme_dns_issue.sh`, edit its contents appropriately, and make it executable (`chmod +x configs/acme_dns_issue.sh`)

It's also critical that HOST_NAME resolves to your jail from **inside** your network.  You'll probably need to configure this on your router. 

### Execution
Once you've downloaded the script, prepared the configuration file, and (if applicable) made the necessary edits to `configs/acme_dns_issue.sh`, make this script executable (`chmod +x nextcloud-jail.sh`) and run it (`./nextcloud-jail.sh`).  The script will run for several minutes.  When it finishes, your jail will be created, Nextcloud will be installed, and you'll be shown the database settings to configure your Nextcloud installation.

### Further Configuration
There's further configuration that needs to be done inside the jail after Nextcloud is set up; more to follow shortly on this.
