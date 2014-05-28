Web Chroot Manager (WCM) 
==================

Web Chroot Manager (WCM) aims to simplify the management of chroot in Linux.  It's a small easy to use application with a built in wizard which creates chroot environments suitable for PHP-FPM.

WCM supports adding additional binaries to chroot, updating of chroot with new packages, and generating and comparing blueprints of files contained inside the chroot.

### Limitations

WCM has been designed for Ubuntu 12.04+ LTS.  Debian and CentOS/Redhat support are due with the next release.

### Installation

Copy the configuration files to: /etc/buckhill-wcm/* and the shell file to your preferred location.

By default, WCM assumes that the configuration directory is located at /etc/buckhill-wcm.

You may change the CFDIR variable in order to move the configuration directory.

### WCM Workflow

	1. Use wizard to generate primary and secondary user(s) configuration
	2. Use wizard to geberate site(s) configuration
	3. Or, edit template file(s) manually
	4. Create user account(s) and site(s) using create command
	5. After site is completely deployed, generate blueprints as required 

### How to use WCM

Note: Starting WCM without any arguments specified will print help text detailing a list of roles and available options.

WCM has several roles and commands:-

	1. Wizard
	2. Create
	3. Install Extra Binaries
	4. Update Binaries
	5. Binary Blueprint Manager

### 1. Wizard Overview

The wizard is used to generate configuration files which are later used when creating chroot accounts and sites.

There are three sections:

	- Primary account
	- Secondary account
	- Site

To run, type: ./web-chroot-manager.sh wizard

### 1.1 Wizard - Primary Account

The primary account is the account under which the chroot is installed. Its UID and GID are used by PHP-FPM.

The wizard asks for:

- Username - it is good practice to use short usernames
- DNS server - Chroot will use its own resolver settings. You can use the default server settings or those from a provider.
- Shell - Usually there is no reason to change this.
- Extra binaries which will be installed under chroot. The binaries have to exists on the server.  Full path has to be provided and they have to be separated with a space.

To run, type: ./web-chroot-manager.sh wizard

### 1.2 Wizard - Secondary Account

The account for the site administrator. Access is allowed via SFTP.  It inherits the GID of the primary account.  
Since PHP is also run under the primary account you are free to deny access to the files by changing group permissions.

The wizard asks for:

- Username - it is good practice to use short usernames
- Username of parent (Primary Account) under which it will be created
- Shell - Usually there is no reason to change this.
- Email address - Required for other scripts, such as the WordPress Installer (LPI for Wordpress)

The Primary and Secondary account will be automatically added to primary and secondary groups, which are used 
for SSH access policy enforcing. 

Groups are defined in /etc/buckhill-wcm/general.conf under PRIMARY_GROUP and SECONDARY_GROUP variables.

Groups have to be setup on the server and the SSH server already configured, in order for the SSH access policy to work. 

You may use the linux-package-installer (LPI) to configure the SSH server, if required.

To run, type: ./web-chroot-manager.sh wizard

### 1.3 Wizard - Site

This generates a configuration for an Apache vhost which uses the PHP-FPM pool configured for the Primary account. 
The wizard requires the Primary account username.

The wizard asks for:

- Domain name
- Primary account username
- Listen socket (exp. 1.2.3.4:80) or leave * if you unsure
- Vhost alias for the domain

To run, type: ./web-chroot-manager.sh wizard

### 2. Create

Creates a chroot account (Primary account), Secondary account and site

The configuration file for each action has to exist within /etc/buckhill-wcm/

**Options:**

- -u [account_name] - Create Primary or Secondary account together with chroot
- -s [domain_name] - Creates site under chroot

To create chroot user, type: ./web-chroot-manager.sh create -u testuser

To create site under chroot user, type: ./web-chroot-manager.sh create -s testdomain.com

### 3. Install Extra Binaries

Installs extra binaries into the chroot and updates the configuration file of the Primary account

**Options (mandatory):**

- -u [primary_account]
- -p [binary list] separated by comma , full paths have to be provided

To run, type: ./web-chroot-manager.sh install -u testuser -p wget,ntp,nano 

### 4. Update Binaries

Updates binaries within a chroot.  The binary has to be specified in the Primary account configuration file

**Options (mandatory):**

- -u [primary_account]

Optionally you may specify which binaries will be updated with -p flag

If the flag is not provided then all binaries from the configuration file will be updated

To update all binaries, type: ./web-chroot-manager.sh update -u testuser

To update specific binaries, type: ./web-chroot-manager.sh update -u testuser -p wget,ntp,nano

### 5. Binary Blueprint Manager

With this function you can check your files against potentially unauthorised changes

The blueprint report provides a list of changed, missing, or new files

**Options:**

- -u [primary_account] **mandatory**
- -g Generates blueprint
- -c Compares current state with the previous blueprint. After the -c path another blueprint can be specified, otherwise latest blueprint is used
- -f [blueprint_file] 

A file exclusion list can be defined within "full_bp_exclusions", which has to be saved into the configuration directory of the primary account.

To run, type: ./web-chroot-manager.sh blueprint -u testuser -g

To compare against previous state, type: ./web-chroot-manager.sh blueprint -u testuser -c

To compare against previous state, type: ./web-chroot-manager.sh blueprint -u testuser -c -f /path/to/blueprintfile

### Directory structure and configuration files
 
**Main configuration file:**

/etc/buckhill-wcm/general.conf

**Configuration file for the user generated with wizard:**

/etc/buckhill-wcm/accounts/[Account Name]/user.conf

**Binary blueprint exclusions list for the user:**

/etc/buckhill-wcm/accounts/[Account Name]/full_bp_exclusions

The Linux Grep utility is used for matching patterns within this file, therefore the file format should be understandable to grep. For further informations check the grep documentation, specifically under "option -f"

**Binary blueprint files for the user:**

/etc/buckhill-wcm/accounts/[Username]/blueprints 

**Any binaries or file in this directory will be installed in chroot:**

/etc/buckhill-wcm/accounts/[Account Name]/custom/

**Website configuration:**

/etc/buckhill-wcm/accounts/sites/domain_name.conf

**Templates for php-fpm and Apache:**

/etc/buckhill-wcm/apache_vhost_template.conf

/etc/buckhill-wcm/apache_php-fpm.conf

/etc/buckhill-wcm/fpm_pool_template.conf
