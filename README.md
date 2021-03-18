# nethserver-lemonldap-ng
[LemonLDAP::NG](https://lemonldap-ng.org/welcome/) is a single sign-on/identity and access management (SSO/IAM) application.  It supports both of the standard Nethserver accounts providers, and allows other applications to authenticate using HTTP headers (external authentication, a/k/a "Apache authentication"), SAML, CAS, and OpenID Connect.  It also handles multi-factor authentication using TOTP (and apps like Authy or Google Authenticator), hardware tokens, and other technologies.

This package provides basic integration of LemonLDAP::NG into Nethserver, setting up the necessary Apache virtual hosts, configuring them for your domain, and configuring LemonLDAP::NG to connect to your specified accounts provider.  Further manual configuration will be required to allow it to protect any application you're interested in.

## Prep

Install the danb35 repo: `yum install https://repo.familybrown.org/nethserver/7/noarch/nethserver-danb35-1.1.0-1.ns7.noarch.rpm`

Then you'll need to add the LemonLDAP::NG repos.  Create `/etc/yum.repos.d/lemonldap-ng.repo` with your text editor of choice.  Its contents should be:
```
[lemonldap-ng]
name=LemonLDAP::NG packages
baseurl=https://lemonldap-ng.org/redhat/stable/$releasever/noarch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-OW2

[lemonldap-ng-extras]
name=LemonLDAP::NG extra packages
baseurl=https://lemonldap-ng.org/redhat/extras/$releasever
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-OW2
```
You'll also need to install the GPG key: `curl https://lemonldap-ng.org/_media/rpm-gpg-key-ow2 > /etc/pki/rpm-gpg/RPM-GPG-KEY-OW2`

## Install

Now run `yum install nethserver-lemonldap-ng`.  Yum will install LemonLDAP::NG and all its dependencies, along with the integration package.

## Post-install configuration

### Host names
By default, the authentication portal will be available at https://auth.yourdomain, and the manager at https://manager.yourdomain.  You can change these defaults using the `portalFqdn` and `managerFqdn` properties, respectively.

### TLS certificates
By default, the portal and manager virtual hosts will use the default system TLS certificate.  This means that the FQDNs for the portal and manager will need to be part of that certificate.  If you prefer, you can create a separate certificate for those virtual hosts and specify it using the `CrtFile`, `ChainFile`, and `KeyFile` properties.

### LLNG Master Config file
Unlike most configuration in Nethserver, the main configuration file for LemonLDAP::NG is not templated.  Most changes will be done directly through its web interface (https://manager.yourdomain).  However, this package provides a script that will create a basic configuration.  That script will be created or updated any time you run `signal-event nethserver-lemonldap-ng-update`.  Then, to run it, run `/root/lemon_config.sh`.  This script will set the portal to enforce SSL on your domain, require secure cookies, remove the test applications, and connect to your accounts provider as configured in Nethserver.

## Configuration properties
Configuration for this module is stored in the main configuration database, under the `lemonldap` key.  Available properties are:

|Property|Default|Description|
|---|---|---|
|portalFqdn|auth.$DomainName|FQDN where the authentication portal will be visible|
|managerFqdn|manager.$DomainName|FQDN where the manager will be visible|
|CrtFile|(system default)|Path to TLS certificate for the portal and manager virtual hosts|
|ChainFile|(system default)|Path to the intermediate CA certificate(s), if any|
|KeyFile|(system default)|Path to the TLS private key for the portal and manager virtual hosts|
