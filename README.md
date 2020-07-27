# It should go without saying (because this isn't the master branch) that this isn't expected to be release-quality code.  Use at your own risk and be prepared to help troubleshoot.

# freenas-iocage-nextcloud
Script to create an iocage jail on FreeNAS for the latest Nextcloud 19 release, including Caddy 2.x, MariaDB 10.3/PostgreSQL 10, and Let's Encrypt

This script will create an iocage jail on FreeNAS 11.3 or TrueNAS CORE 12.0 with the latest release of Nextcloud 19, along with its dependencies.  It will obtain a trusted certificate from Let's Encrypt for the system, install it, and configure it to renew automatically.  It will create the Nextcloud database and generate a strong root password and user password for the database system.  It will configure the jail to store the database and Nextcloud user data outside the jail, so it will not be lost in the event you need to rebuild the jail.

## Status
This script will work with FreeNAS 11.3, and it should also work with TrueNAS CORE 12.0.  Due to the EOL status of FreeBSD 11.2, it is unlikely to work reliably with earlier releases of FreeNAS.

## Usage

### Prerequisites (Let's Encrypt)
This script works best when your installation is able to obtain a certificate from [Let's Encrypt](https://letsencrypt.org/).  When you use it this way, Caddy is able to handle all of the TLS-related configuration for you, obtain and renew certificates automatically, etc.  In order for this to happen, you must meet the two requirements below:

* First, you must own or control a real Internet domain name.  This script obtains a TLS encryption certificate from Let's Encrypt, who will only issue for public domain names.  Thus, domains like `cloud.local`, `mycloud.lan`, or `nextcloud.home` won't work.  Domains can be very inexpensive, and in some cases, they can be free.  [Freenom](https://www.freenom.com/), for example, provides domains for free if you jump through the right hoops.  [EasyDNS](https://easydns.com/) is a fine domain registrar for paid domains, costing roughly US$15 per year (which varies slightly with the top-level domain).

* Second, one of these two conditions must be met in order for Let's Encrypt to validate your control over the domain name:

  * You must be able and willing to open ports 80 and 443 from the entire Internet to the jail, and leave them open.  If this applies, do it **before** running this script.
  * DNS hosting for the domain name needs to be with a provider that Caddy supports.  At this time, only Cloudflare is supported.

[Cloudflare](https://www.cloudflare.com/) provides DNS hosting at no cost, and it's well-supported by Caddy.  Cloudflare also provides Dynamic DNS service, if your desired Dynamic DNS client supports their API.  If it doesn't, [DNS-O-Matic](https://dnsomatic.com/) is a Dynamic DNS provider that will interface with many DNS hosts including Cloudflare, has a much simpler API that's more widely supported, and is also free of charge.

This document previously had a discussion of using Freenom, Cloudflare, and DNS-O-Matic to give you free dynamic DNS and certificate validation with a free domain.  However, due to abuse, Cloudflare has removed the ability to use its API with free domains when using Cloudflare's free plan.  For this to work, you'll need to pay either for Cloudflare or for a domain (and the latter is likely less expensive).  If you want to use a Freenom domain, you'll need to be able and willing to open ports 80 and 443 to your jail, so you can get your certificate without using DNS validation.

If you aren't able or willing to obtain a certificate from Let's Encrypt, this script also supports configuring Caddy with a self-signed certificate, or with no certificate (and thus no HTTPS) at all.

### Prerequisites (Other)
There are Three options when it comes to datasets and folder structure:
- 1 Dataset with subfolders
- 1 Dataset with 4 sub-datasets
- 4 Datasets

Although not required, it's recommended to create 1 Dataset with 4 sub-datasets on your main storage pool
- 1 Dataset named `nextcloud`
Under which you create 4 other datasets
- one named `files`, which will store the Nextcloud user data.
- one named `config`, which will store the Nextcloud configuration.
- one named `themes`, which will store the Nextcloud themes.
- one called `db`, which will store the SQL database.  For optimal performance, set the record size of the `db` dataset to 16 KB (under Advanced Settings in the FreeNAS web GUI).  It's also recommended to cache only metadata on the `db` dataset; you can do this by running `zfs set primarycache=metadata poolname/db`.

If you use 1 dataset with subfolders it's recomended to use a similar structure.

If these are not present, a directory `/nextcloud` will be created in `$POOL_PATH`, and subdirectories of `db` (with a subdirectory of either `mariadb` or `pgsql`, depending on which database you chose), `files`, `config`, and `themes` will be created there.  But for a variety of reasons, it's preferred to keep these things in their own dataset.

### Installation
Download the repository to a convenient directory on your FreeNAS system by changing to that directory and running `git clone https://github.com/danb35/freenas-iocage-nextcloud`.  Then change into the new `freenas-iocage-nextcloud` directory and create a file called `nextcloud-config` with your favorite text editor.  In its minimal form, it would look like this:
```
JAIL_IP="192.168.1.199"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
TIME_ZONE="America/New_York"
HOST_NAME="YOUR_FQDN"
STANDALONE_CERT=1
```
Many of the options are self-explanatory, and all should be adjusted to suit your needs, but only a few are mandatory.  The mandatory options are:

* JAIL_IP is the IP address for your jail.  You can optionally add the netmask in CIDR notation (e.g., 192.168.1.199/24).  If not specified, the netmask defaults to 24 bits.  Values of less than 8 bits or more than 30 bits are invalid.
* DEFAULT_GW_IP is the address for your default gateway
* POOL_PATH is the path for your data pool.
* TIME_ZONE is the time zone of your location, in PHP notation--see the [PHP manual](http://php.net/manual/en/timezones.php) for a list of all valid time zones.
* HOST_NAME is the fully-qualified domain name you want to assign to your installation.  If you are planning to get a Let's Encrypt certificate (recommended), you must own (or at least control) this domain, because Let's Encrypt will test that control.  If you're using a self-signed cert, or not getting a cert at all, it's only important that this hostname resolve to your jail inside your network.
* DNS_CERT, STANDALONE_CERT, SELFSIGNED_CERT, and NO_CERT determine which method will be used to generate a TLS certificate (or, in the case of NO_CERT, indicate that you don't want to use SSL at all).  DNS_CERT and STANDALONE_CERT indicate use of DNS or HTTP validation for Let's Encrypt, respectively.  One **and only one** of these must be set to 1.
* DNS_PLUGIN: If DNS_CERT is set, DNS_PLUGIN must contain the name of the DNS validation plugin you'll use with Caddy to validate domain control.  At this time, the only valid value is `cloudflare`.
* DNS_TOKEN: If DNS_CERT is set, this must be set to a properly-scoped Cloudflare API Token.  You will need to create an API token through Cloudflare's dashboard, which must have "Zone / Zone / Read" and "Zone / DNS / Edit" permissions on the zone (i.e., the domain) you're using for your installation.  See [this documentation](https://github.com/libdns/cloudflare) for further details.
 
In addition, there are some other options which have sensible defaults, but can be adjusted if needed.  These are:

* JAIL_NAME: The name of the jail, defaults to "nextcloud"
* DB_PATH, FILES_PATH, CONFIG_PATH, THEMES_PATH and PORTS_PATH: These are the paths to your database files, your data files, nextcloud config files, theme files and the FreeBSD Ports collection.  They default to $POOL_PATH/nextcloud/db, $POOL_PATH/nextcloud/files, $POOL_PATH/nextcloud/config, $POOL_PATH/nextcloud/themes and $POOL_PATH/portsnap, respectively.
* DATABASE: Which database management system to use.  Default is "mariadb", but can be set to "pgsql" if you prefer to use PostgreSQL.
* INTERFACE: The network interface to use for the jail.  Defaults to `vnet0`.
* VNET: Whether to use the iocage virtual network stack.  Defaults to `on`.
* CERT_EMAIL is the email address Let's Encrypt will use to notify you of certificate expiration, or for occasional other important matters.  This is optional.  If you **are** using Let's Encrypt, though, it should be set to a valid address for the system admin.

If you're going to open ports 80 and 443 from the outside world to your jail, do so before running the script, and set STANDALONE_CERT to 1.  If not, but you use a DNS provider that's supported by Caddy, set DNS_CERT to 1.  If neither of these is true, use either NO_CERT (if you want to run without SSL at all) or SELFSIGNED_CERT (to generate a self-signed certificate--this is also the setting to use if you want to use a certificate from another source).

Also, HOST_NAME needs to resolve to your jail from **inside** your network.  You'll probably need to configure this on your router.  If you're unable to do so, you can edit the hosts file on your client computers to achieve this result.

### Execution
Once you've downloaded the script and prepared the configuration file, run this script (`./nextcloud-jail.sh`).  The script will run for several minutes.  When it finishes, your jail will be created, Nextcloud will be installed and configured, and you'll be shown the randomly-generated password for the default user ("admin").  You can then log in and create users, add data, and generally do whatever else you like.

### Obtaining a trusted Let's Encrypt cert
This configuration generated by this script will obtain certs from a non-trusted certificate authority by default.  This is to prevent you from exhausting the [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) while you're testing things out.  Once you're sure things are working, you'll want to get a trusted cert instead.  To do this, you can use a simple script that's included.  As long as you haven't changed the default jail name, you can do this by running `iocage exec nextcloud /root/remove-staging.sh` (if you have changed the jail name, replace "nextcloud" in that command with the jail name).

### HTTP Strict Transport Security
When you log into your Nextcloud instance as administrator, you may see a configuration warning that HSTS is not enabled.  This is intentional.  HSTS is a useful security measure, but it can also lock you out of your site if certificate renewal isn't working properly.  I recommend you let the system obtain its initial trusted cert, and then renewing at least once, before enabling HSTS, to ensure that automatic renewal works as intended.  Ordinarily this will take about 60 days.  To enable HSTS, follow these steps:

* `iocage console nextcloud`
* `nano /usr/local/www/Caddyfile`
* Uncomment (remove the `#`) from the line that begins with `Strict-Transport-Security`
* Save the edited file and exit `nano`.
* `service caddy reload`

### Default SNI
If you're going to run Nextcloud behind a reverse proxy, and you've used one of the options to enable TLS on the Nextcloud installation, you may see errors from Caddy indicating that it can't find the appropriate certificate.  In this case, you'll need to enable the `default_sni` option in the Caddyfile.  To do this, follow these steps:

* `iocage console nextcloud`
* `nano /usr/local/www/Caddyfile`
* Uncomment (remove the `#`) from the line that begins with `default_sni`
* Save the edited file and exit `nano`.
* `service caddy reload`

### To Do
I'd appreciate any suggestions (or, better yet, pull requests) to improve the various config files I'm using.  Most of them are adapted from the default configuration files that ship with the software in question, and have only been lightly edited to work in this application.  But if there are changes to settings or organization that could improve performance, reliability, or security, I'd like to hear about them.
