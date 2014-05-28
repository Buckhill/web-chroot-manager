#!/bin/bash

#Author: Marko Bencek
#email: marko@buckhill.co.uk
#Date 04/17/2014
#Copyright Buckhill Ltd 2014
#Website www.buckhill.co.uk
#GitHub: https://github.com/Buckhill/web-chroot-manager
#License GPLv3

CFGDIR=/etc/buckhill-wcm
TS=`date +%s`

[ "$(whoami)" != "root" ] && { echo "Run me as root";exit 1;}

#setting empty variables"
QuestionOut=""
ChrootU=""
SANS=""

function check_group
{
	if grep -q "^$1:" /etc/group 
	then
		[ "$DEBUG" == "1" ] && echo group $1 exists
		return 0
	else 
		[ "$DEBUG" == "1" ] && echo "group $1 doesn't exist"
		return 1
	fi
	
}

function question
{
	echo -n "$1: " 
	read QuestionOut
	echo $read_out
}

function error_display
{
	echo "$1"
	echo "Exiting!"
	exit 1
}

function login_sanity_check
{
	if echo "$1" |grep -q '^[a-z][a-z0-9_\-]\{1,14\}[^\-]$'
	then
		[ "$DEBUG" == "1" ] && echo "Sanity check for $1 - successful"
		return 0
	else
		
		[ "$DEBUG" == "1" ] && echo "Sanity check for $1 - failed"
		return 1
	fi
}


function user_exist_check
{
	if grep -q "^$1:" /etc/passwd
	then
		[ "$DEBUG" == "1" ] && echo "User $1 exists"
		return 0
	else
		[ "$DEBUG" == "1" ] && echo "User $1 doesnt exist"
		return 1
	fi	
}

function home_dir_existance_check
{
	hdir_t=`awk -F : -v user="$1" ' $1 == user {print $6}' /etc/passwd`
	[ "$hdir_t" != "$HomeDir/$1" ] && 
	{
		[ "$DEBUG" == "1" ] && echo "Directory from passwd $hdir_t is not what we expected $HomeDir/$1"
		return 1 
	}
	[ -h $hdir_t ] ||
	{
		 [ "$DEBUG" == "1" ] && echo " the $hdir_t is not symlink"
		 return 1
	}

	rhdir=`ls -l $hdir_t |awk -F '-> ' '{print $2}'`
	[ "$rhdir" == "$CHROOT/$(id -gn $1)$hdir_t" ] || 
	{
		[ "$DEBUG" == "1" ] && echo "The link doesn't point to where we are expecting $rhdir  $CHROOT/$(id -gn $1)$hdir_t/" 
		return 1
	}	
	[ "$DEBUG" == "1" ] && echo "Home directory for $1 is set properly" 
	return 0

}

function fs_object_exists
{
	[ -e $1 ] || return 1
	[ "$DEBUG" == "1" ] && echo "fs object $1 exists" 
	return 0
}

function check_primary_account
{
	login_sanity_check "$1"  || error_display "Login name length has to be between 4 and 20 characters. Only small caps, numbers and _ are allowed. Login name can't start with a number"
	user_exist_check $1||  error_display "The account $1 doesn't exist"
	home_dir_existance_check $1|| error_display "The home directory for $1 is not properly set" 
	[ "$(id -un $1)" == "$(id -gn $1)" ] || error_display "The $1 is not a primary account" 
	[ "$DEBUG" == "1" ] && echo "All checks on account $1 performed successfully"
	return 0
}

function add_to_pass_grp
{
	ChrootU=$CHROOT/$1
	[ "$DEBUG" == "1" ] && echo "add_to_pass_grp password and group files generating for $1 in $ChrootU"
	[ -d $ChrootU/etc ] || mkdir $ChrootU/etc
	grep "^$1:" /etc/passwd >> $ChrootU/etc/passwd
	if [ "$1" == "$(id -gn  $1)" ]
	then
		[ "$DEBUG" == "1" ] && echo "add_to_pass_grp primary account generating group file"
		grep "^$1:" /etc/group >> $ChrootU/etc/group
	else
		[ "$DEBUG" == "1" ] && echo "add_to_pass_grp secondary account skipping group file"
	fi  

}

function template_install
{
	#$1 template file
	#$2 destination file
	[ -f $1 ] ||  error_display "Template $1 is missing"
        if [ -f $2 ]
        then
                 error_display "The configuration file $2 already exists"
        else
                [ "$DEBUG" == "1" ] && echo "Generating $2"
                sed -e "s/##UserName##/$UserName/g" -e "s|##CHROOT##|$CHROOT|g" -e "s/##PoolName##/$UserName/g" -e "s|##WEBDIR##|$WebDir|g" -e "s/##DOMAIN##/$SiteName/g" -e "s/##ALIASES##/$Aliases/g" -e "s/##PARENT##/$PARENT/g" -e "s/##IP##/$LISTEN/g" $1  >  $2
        fi
}

function new_primary_account 
{
	#sanity check	
	login_sanity_check "$UserName"  || error_display "Login name length has to be between 4 and 20 characters. Only small caps, numbers and _ are allowed. Login name can't start with a number"

	user_exist_check $UserName &&  error_display "$UserName already exists"
	
	ChrootU=$CHROOT/$UserName$HomeDir/$UserName 
	for dir in $ChrootU $HomeDir/$UserName 
	do
		fs_object_exists $dir  && error_display "$dir already exists"
	done

	check_group $PRIMARY_GROUP || groupadd -K GID_MIN=200 -K GID_MAX=499 $PRIMARY_GROUP
	useradd -d $HomeDir/$UserName -M -s $DefaultShell -G $PRIMARY_GROUP $UserName
	echo Account $UserName has been created
	passwd -l $UserName >/dev/null
	mkdir -p $ChrootU
	chown $UserName:$UserName $ChrootU
	ln -s  $ChrootU $HomeDir/$UserName
	add_to_pass_grp $UserName
	mkdir -p $CHROOT/$UserName$WebDir
	echo Chroot for $UserName has been created 
	
	template_install $CFGDIR/fpm_pool_template.conf $PHPfpmPoolDir/$UserName.conf
	template_install $CFGDIR/apache_php-fpm.conf $ApacheConfDir/$UserName-php-fpm.conf
	echo "Core templates for $UserName have been installed"
}

function new_sub_account
{
	check_primary_account $PARENT 
	
	#checks for subaccount 
	group=$(id -ng $PARENT)
	ChrootU=$CHROOT/$group$HomeDir/$UserName

	login_sanity_check "$UserName"  || error_display "Login name length has to be between 4 and 20 characters. Only small caps, numbers and _ are allowed. Login name can't start with a number"
	user_exist_check $UserName &&  error_display "$UserName already exists"
	for dir in $ChrootU $HomeDir/$UserName
        do
                fs_object_exists $dir  && error_display "$dir already exists"
        done
	
	check_group $SECONDARY_GROUP || groupadd -K GID_MIN=200 -K GID_MAX=499 $SECONDARY_GROUP
	useradd -d $HomeDir/$UserName -g $group -M -s $DefaultShell -G $SECONDARY_GROUP $UserName
        passwd -l $UserName >/dev/null

	if which chpasswd |grep -q chpasswd
	then
		[ "$DEBUG" == "1" ] && echo "chpasswd exists, setting password for $UserName"
		PASSWORD=`cat /dev/urandom | tr -cd "[:alnum:]" | head -c 8`
		echo "$UserName:$PASSWORD"|chpasswd
		echo "Password for user $UserName is $PASSWORD" 
	else
		[ "$DEBUG" == "1" ] && echo "chpasswd doesn't exist. Locking $UserName"
		passwd -l $UserName
	fi

        mkdir -p $ChrootU
        chown $UserName:$group $ChrootU
        ln -s  $ChrootU $HomeDir/$UserName
	ln -s  $CHROOT/$PARENT $CHROOT/$UserName
	add_to_pass_grp $UserName
}


function new_site
{
	check_primary_account $PARENT
	ChrootW=$CHROOT/$PARENT/$WebDir
	echo Creating site $SiteName
	
	if [ -d $ChrootW/$SiteName ] 
	then
		error_display "Directory $ChrootW/$SiteName already exists"
	else
		[ "$DEBUG" == "1" ] && echo "Creating web directory" 
	fi

	echo Creating site folders
	umask 002
	mkdir -p $ChrootW/$SiteName/htdocs $ChrootW/$SiteName/logs $ChrootW/$SiteName/tmp $ChrootW/$SiteName/misc
	chown $PARENT:$PARENT $ChrootW/$SiteName/htdocs $ChrootW/$SiteName/tmp $ChrootW/$SiteName/misc
	ln -s $ChrootW/$SiteName  $WebDir/$SiteName
	
	echo install template in Apache  
	template_install $CFGDIR/apache_vhost_template.conf  $ApacheAvDir/$SiteName.conf	
	ln -s $ApacheAvDir/$SiteName.conf $ApacheEnDir/$SiteName.conf
	echo Site $SiteName has been installed
	echo Please restart apache and php-fpm services 
}

function create
{
	if [ -z "$OBJECT_TYPE" ] 
	then
		error_display "OBJECT_TYPE is not defined" 
	else 
		[ "$DEBUG" == "1" ] && echo "OBJECT_TYPE is $OBJECT_TYPE" 
	fi

	case $OBJECT_TYPE in
		primary)
			new_primary_account
			if [ -z  "$JAILBINS" ]
			then
				 [ "$DEBUG" == "1" ] && echo "Creating empty jail" 
			else
				 [ "$DEBUG" == "1" ] && echo "Creating empty jail with $JAILBINS" 
			fi
			install_jail "$JAILBINS"
			;;
		secondary)
			if [ -z "$PARENT" ] 
			then
				error_display "The primary account isn't specified"
			else 
				[ "$DEBUG" == "1" ] && echo "Parent is  $PARENT" 
			fi

			new_sub_account
			;;
		site)
			if [ -z "$PARENT" ]
                        then
                                error_display "The primary account isn't specified"
                        else
                                [ "$DEBUG" == "1" ] && echo "Parent is  $PARENT"
                        fi
			new_site
			
			;;
		*)
			error_display "Unsupported OBJECT_TYPE $OBJECT_TYPE"
			;;
	esac 
}

function install_jail
{
	check_primary_account $UserName
	echo Installing jail for $UserName
	
	for fobj in $*
	do
		 [ -f $fobj ] ||  [ -h $fboj ]  || error_display "The $fobj is not file or symlink" 
	done 
		 [ "$DEBUG" == "1" ] && echo "All binaries exists"
	
	echo devs...
	#crete devs 
	[ -d $CHROOT/$UserName/dev ] || mkdir $CHROOT/$UserName/dev
	[ -r $CHROOT/$UserName/dev/random ] || mknod $CHROOT/$UserName/dev/random c 1 8
	[ -r $CHROOT/$UserName/dev/urandom ] || mknod $CHROOT/$UserName/dev/urandom c 1 9
	[ -r $CHROOT/$UserName/dev/null ]    || mknod -m 666 $CHROOT/$UserName/dev/null    c 1 3
	[ -r $CHROOT/$UserName/dev/zero ]    || mknod -m 666 $CHROOT/$UserName/dev/zero    c 1 5

	echo minimal libs ...
	for fobj in libnss_dns.so.2 libnss_files.so.2 libresolv.so.2
	do
		lib=$(find /lib -name $fobj |head -n1)
		[ -z "$lib" ]  &&  error_display "Lib $fobj is missing on system"
		cp -pf $cpo --parents    "$lib" "$CHROOT/$UserName"
	done

	echo etc...
	#minimal etc 	
	[ -d  $CHROOT/$UserName/etc ] || mkdir  $CHROOT/$UserName/etc
	if [ -f  $CFGDIR/accounts/$UserName/custom/etc/resolv.conf ]  
	then
		[ "$DEBUG" == "1" ] && echo "resolv.conf is found in custom"
	else
		[ "$DEBUG" == "1" ] && echo "generating resolv.conf from configuration"
		for NS_tmp in $NAMESERVERS
		do
			echo "nameserver $NS_tmp" >>  $CHROOT/$UserName/etc/resolv.conf 
		done
	fi
	
	#install time_db
	if [ -d $CHROOT/$UserName/usr/share/zoneinfo ]
	then
		:
	else
		mkdir -p $CHROOT/$UserName/usr/share/zoneinfo
		rsync -aH /usr/share/zoneinfo/ $CHROOT/$UserName/usr/share/zoneinfo
	fi
	
	
	if [ -f  $CFGDIR/accounts/$UserName/custom/etc/hosts ] 
	then
		[ "$DEBUG" == "1" ] && echo "hosts is found in custom"
	else
		[ "$DEBUG" == "1" ] && echo "generating default hosts"
		echo "127.0.0.1 localhost" >> $CHROOT/$UserName/etc/hosts
	fi
	
	mkdir -p $CHROOT/$UserName/var/log $CHROOT/$UserName/tmp
	chmod 777 $CHROOT/$UserName/tmp
	chmod o+t $CHROOT/$UserName/tmp
	
	echo Custom files...
	PDIR=$PWD
	cd $CFGDIR/accounts/$UserName/custom
	for fobj in `find . -type f`
	do
		cp -pf $cpo --parents  "$fobj" "$CHROOT/$UserName"	
	done 
	 
	for fobj in $*
        do
		push_to_chroot $fobj
        done
}

function push_to_chroot
{

	cp -pvf $cpo --parents  "$1" "$CHROOT/$UserName"
	push_to_bp "$CHROOT/$UserName$1"	

	for lib in `ldd "$1" | cut -d'>' -f2 | awk '{print $1}'`
	do
		if [ -f "$lib" ]
		then
			cp -pvf $cpo --parents "$lib" "$CHROOT/$UserName"
			push_to_bp "$CHROOT/$UserName$lib"
		fi 
	done
}

function push_to_bp
{
	#set -x
	[ -z "$1" ] && return 1  
	[ -z "$BP_FILE" ] && BP_FILE=`bp_file_bin`
	MD5O=`md5sum $1`
	if grep -q " ${MD5O#* }$" $BP_FILE
	then
		sed -i "s#^.* ${MD5O#* }\$#$MD5O#" $BP_FILE
	else
		echo "$MD5O" >> $BP_FILE
	fi
	#set +x
}

function check_chroot_bins
{
	ctmp=0
        [ -z "$1" ] && return 1
        for Bin in `echo $1 |sed 's/,/ /g'`
        do
                [ -f $CHROOT/$UserName/$Bin ] || [ -L $CHROOT/$UserName/$Bin ] ||
                {
                        ctmp=$(( ctmp + 1 ))
                }
        done
	if [ $ctmp -eq 0 ]
	then
		return 1 
	else
        	return 0
	fi
}

function check_source_bins
{
	[ -z "$1" ] && return 1
	for Bin in `echo $1 |sed 's/,/ /g'`
	do
		[ -f $Bin ] || [ -L $Bin ] || 
		{
			return 1
		}
	done
	return 0
}

function check_bins_in_jailbins
{
	ctmp=0
        [ -z "$1" ] && return 1
        for Bin in `echo $1 |sed 's/,/ /g'`
        do
		echo $JAILBINS |grep -qw $Bin && 
                {
			ctmp=$(( ctmp + 1 )) 
                }
        done
        if [ $ctmp -eq 0 ]
	then
		return 1
	else
		return 0
	fi
}

function update_chroot_bins
{
	if [ -z "$1" ] 
	then
		echo  updating all for $UserName
		echo $JAILBINS
		UPDATE_BINS=$JAILBINS
	else

        check_source_bins $1 || {
                echo "Some of provided bins are missing"
                exit 1
                }

        check_bins_in_jailbins $1 || {
                echo "Some of provided bins are missing in user's configuration"
                exit 1
                }
		UPDATE_BINS=`echo $1 |sed 's/,/ /g'`
		
	fi
	
	for Bin in $UPDATE_BINS
	do
		push_to_chroot $Bin
	done
}

function install_extra_bins
{
	check_source_bins $1 || {
		echo "Some of provided bins are missing"
		exit 1
		}
	
	check_bins_in_jailbins $1 && {
		echo "Some of provided bins is already in user's configuration"
		exit 1
		}
	check_chroot_bins $1 || {
		echo "Some bins are already installed in chroot"
		exit 1
		}
	#updating users conf
	
	JAILBINS="$JAILBINS $(for Bin in $(echo $1 |sed 's/,/ /g');do echo -n " $Bin";done )"
	JAILBINS=`echo $JAILBINS|awk '{print $0}'`
	sed -i "s#^JAILBINS=.*\$#JAILBINS=\"$JAILBINS\"#" $CFGDIR/accounts/$UserName/user.conf
	
	for Bin in `echo $1 |sed 's/,/ /g'`
        do	
		push_to_chroot $Bin
	done
}

function numeric_answers
{
 	declare -i ANS
	ANS=1000
	while [ $ANS -lt 1 ] || [ $ANS -gt $1 ] 
	do
		read -p "[ 1 - $1 ]: " ANS
	done
	return $ANS
}

function numeric_question
{
	count=0
	for Q in "$@"
	do	
		count=$(( count + 1 ))
		echo $count $Q
	done
	numeric_answers $#
	return $?
}

function wiz_ask_username
{
	read -p "Enter username: " SANS
	login_sanity_check $SANS  || {
		echo "Sanity check failed "
		wiz_ask_username
		}
	user_exist_check $SANS  &&  {
		echo "User already exists" 
		wiz_ask_username
		}
	[ -d $CFGDIR/accounts/$SANS ] && {
		echo "Profile for user $SANS already exists"
		wiz_ask_username
		}
}

function wiz_ask_parent
{
	read -p "Enter parent account: " SANS
	[ -f $CFGDIR/accounts/$SANS/user.conf ] || {
		echo "Parent account configuration doesn't exist."
		wiz_ask_parent
		}
	grep -q '^OBJECT_TYPE *= *primary *' $CFGDIR/accounts/$SANS/user.conf || {
		echo "Parent user has to be primary."
		wiz_ask_parent
		}
}

function wiz_ask_nameserver
{
	read -p "Enter nameserver ip address: " SANS
	echo "$SANS" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' &&  echo "$SANS" | awk -F'.' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255'|grep -q "$SANS" || {
		echo "IP address format check failed" 
		wiz_ask_nameserver
		}
}

function wiz_ask_apache_listen
{
	read -p "Enter listen socket in format IP_ADDRESS:PORT : " SANS
	echo "$SANS" | grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+' &&  echo "$SANS" | awk -F'[.:]' '$1 <=255 && $2 <= 255 && $3 <= 255 && $4 <= 255'|grep -q "$SANS" || {
		echo "The format check failed" 
		wiz_ask_apache_listen
		}
}

function wiz_ask_shell
{
	read -p "Enter path to SHELL: " SANS
	grep -q "^$SANS$" /etc/shells || {
                echo "The $SANS is not listed in /etc/shells"
                wiz_ask_shell
                }
}

function wiz_ask_domain
{
	read -p "Enter domain name: " SANS
         	host $SANS  >/dev/null 2>&1 || {
                	echo "The $SANS can't be resolved. Do you want to continue"
			numeric_question "Yes" "No" 
			[ $? -eq  2 ] && wiz_ask_domain
                	}
		[ -f $CFGDIR/sites/$SANS.conf ] && {
			echo "Configuration for domain $SANS already exists" 
			wiz_ask_domain
			}
}

function wiz_ask_email
{
	read -p "Enter email address: " SANS
	[ $(echo -n $SANS |sed 's/[^@]//g' |wc -c) -eq 1 ] && [ -n "$( echo $SANS|cut -d@ -f1)" ] || {
		echo "Email address format check failed"
		wiz_ask_email
		}
	
	host `echo $SANS|cut -d@ -f2`  >/dev/null 2>&1 || {
		echo "The domain $(echo $SANS|cut -d@ -f2) can't be resolved"
		wiz_ask_email
                }
}

function wiz_jailbins
{
	read -p "Enter path to binaries (ex. /bin/sh /bin/grep) " SANS 
	for i in $SANS
	do
		[ -f $i ] || {
			echo "The $i doesn't exist or is not a file"
			wiz_jailbins
			}
	done
}

function wizard_primary
{
	OBJECT_TYPE=primary	
	wiz_ask_username
	username=$SANS

	echo "Default name server for chroot is $NAMESERVER."
	echo "Do you want to change it?"
	numeric_question "Yes" "No"
	[ $? -eq 1 ] && {
		wiz_ask_nameserver
		NAMESERVER=$SANS
		}

        echo "Default SHELL is $DefaultShell"
        echo "Do you want to change it?"
        numeric_question "Yes" "No"
        [ $? -eq 1 ] && {
		wiz_ask_shell
        	DefaultShell=$SANS
		}

	echo "Do you want to install binaries into chroot?"
	numeric_question "Yes" "No"
	[ $? -eq 1 ] && {
		wiz_jailbins
		JAILBINS=$SANS
		}

	mkdir -p $CFGDIR/accounts/$username/custom
	cat  > $CFGDIR/accounts/$username/user.conf <<END
OBJECT_TYPE=$OBJECT_TYPE
NAMESERVERS=$NAMESERVERS
DefaultShell=$DefaultShell
JAILBINS="$JAILBINS"
END

}

function wizard_secondary
{
        OBJECT_TYPE=secondary
        wiz_ask_username
        username=$SANS

	wiz_ask_parent
	PARENT=$SANS

        echo "Default SHELL is $DefaultShell"
        echo "Do you wanna change it?"
        numeric_question "Yes" "No"
        [ $? -eq 1 ] && {
		 wiz_ask_shell
        	DefaultShell=$SANS
		}
	wiz_ask_email
	EMAIL=$SANS

        mkdir -p $CFGDIR/accounts/$username
        cat  > $CFGDIR/accounts/$username/user.conf <<END
OBJECT_TYPE=$OBJECT_TYPE
PARENT=$PARENT
DefaultShell=$DefaultShell
EMAIL=$EMAIL
END

}

function wizard_site
{
	wiz_ask_domain
	domain=$SANS
	
	wiz_ask_parent
        PARENT=$SANS
	
	echo "Site listens on * by default"
	echo "Do you want to change it?"
	numeric_question "Yes" "No"
	ANS=$?
	[ "$ANS" -eq 1 ] && { 
		wiz_ask_apache_listen
		LISTEN=$SANS
		}
	 [ "$ANS" -eq 2 ] && {
		LISTEN='*'
		}
	echo "Do you want to set alias?"
        numeric_question "Yes" "No"
	ANS=$?
        [ "$ANS" -eq 1 ] && { 
                wiz_ask_domain
                ALIASES=$SANS
                }
         [ "$ANS" -eq 2 ] && {
            	ALIASES='""' 
                }

	[ -d $CFGDIR/sites ] || mkdir $CFGDIR/sites
        cat  > $CFGDIR/sites/$domain.conf <<END
LISTEN="$LISTEN"
PARENT=$PARENT
ALIASES="$ALIASES"
END

}

function wizard
{
	numeric_question "Set new primary account" "Set new secondary account" "Set new site" "Exit"
	ANS=$?

	case $ANS in
		1)
			echo Configuring primary account
			wizard_primary
			;;
		2)
			echo Configuring secondary account
			wizard_secondary
			;;
		3)
			echo Configuring site
			wizard_site
			;;
		4)
			exit
			;;
	esac
	exit 
}

function bp_file_bin
{
	[ -d $CFGDIR/accounts/$UserName/blueprints ] || mkdir -p $CFGDIR/accounts/$UserName/blueprints
	bp_file="$CFGDIR/accounts/$UserName/blueprints/bin.bp"
	[ -f $bp_file ] || touch $bp_file
	echo $bp_file
}

function bp_file_full
{
	[ -d $CFGDIR/accounts/$UserName/blueprints ] || mkdir  -p $CFGDIR/accounts/$UserName/blueprints
	echo "$CFGDIR/accounts/$UserName/blueprints/full.$TS"
}

function bp_file_full_last
{

        if [ -d $CFGDIR/accounts/$UserName/blueprints ]
        then
                bp_file_last=`ls -lt $CFGDIR/accounts/$UserName/blueprints/full.* 2>/dev/null |grep '\.[0-9]\+$'|awk 'NR==1 {print $9}'`
                if [ -z "$bp_file_last" ]
                then
                        return 1
                else
                        echo $bp_file_last
                fi

        else    
                return 1
        fi
}

function gen_full_bp
{
	[ -f $CFGDIR/accounts/$UserName/full_bp_exclusions ] ||  touch $CFGDIR/accounts/$UserName/full_bp_exclusions
	BP_FILE=`bp_file_full`
	find $CHROOT/$UserName -type f  |grep -v -f $CFGDIR/accounts/$UserName/full_bp_exclusions |xargs md5sum |tee $BP_FILE
}

function check_full_bp
{
	if [ -z "$1" ]  
	then 
		BP_FILE_LAST=`bp_file_full_last` || error_massage "Blueprint hasnt been made yet."
	else
		BP_FILE_LAST=$1
	fi
	
	echo "Checking for missing or changed files under $CHROOT/$UserName"
	md5sum --quiet -c  $BP_FILE_LAST && echo "All good"

	echo "Checking for new files under  $CHROOT/$UserName"
	BP_FILES=`awk '{print $2}' $BP_FILE_LAST`
	CHROOT_FILES=`find $CHROOT/$UserName -type f  |grep -v -f $CFGDIR/accounts/$UserName/full_bp_exclusions`
	echo -e "$BP_FILES\n$CHROOT_FILES\n$CHROOT_FILES" |sort  |uniq -c |awk '{print $1,$2}'| grep '^2' |awk '{print $2}'
}

function usage
{
	cat <<EOF
Usage: $0 Command Options 
Commands:
	wizard -> It has no options but will ask the required questions. 
	create -> Creates primary chrooted account, secondary chrooted account or
		chrooted site according to configuration file generated by
		wizard.
		-u Username
		-s Domain
	install -> Installs extra binaries into chroot
		-u Username of primary chrooted account
		-p List of binaries (full path) separated with , 
	update  -> Updates binaries inside chroot. 
		-u Username of primary chrooted account
		-p List of binaries. If not provided all binaries from
		configuration file for the particular user will be updated.
	blueprint -> Generates and compares blueprints. 
		-u Username of primary chrooted account
		-g Generates blueprint for chroot
		-c Compares files in chroot against blueprint.
		-f Addition to "-c". Compares against provided blueprint 
	 	otherwise uses latest one.
		In $CFGDIR/accounts/UserName/full_bp_exclusions you can 
		specify what should be skipped in standard grep format.
EOF
	exit 
}

[ -z "$NAMESERVERS" ] && NAMESERVER=8.8.8.8


# loading general.conf file
if [ -f $CFGDIR/general.conf ]
then
	. $CFGDIR/general.conf
else
	error_display "The $CFGDIR/general.conf is missing."
fi

[ "$DEBUG" == "1" ] && cpo="-v"
	
COMMAND=$1
shift 

case $COMMAND in 
	wizard)
		wizard $* 
		;;
	create)
		while getopts ":u:s:" o
		do
        		case "${o}" in
               		u)
                        	UserName=${OPTARG}
                        	;;
			s)
				SiteName=${OPTARG}
				;;
    			esac
		done
		shift $((OPTIND-1))

		if [ -n "$UserName" ] && [ -n "$SiteName" ] 
		then 
			error_display "Can't set user and site at the sime time."
		fi

		if [ -z "$UserName" ] && [ -z "$SiteName" ]
		then
			usage
		fi


		if [ -n "$UserName" ]
		then

			if [ -f $CFGDIR/accounts/$UserName/user.conf ] 
			then
				. $CFGDIR/accounts/$UserName/user.conf
			else
				error_display "Configurataion for $UserName is missing" 
			fi
			create
		fi
		
		if [ -n "$SiteName" ]
		then
			if [ -f $CFGDIR/sites/$SiteName.conf ]
                        then
                                . $CFGDIR/sites/$SiteName.conf
				OBJECT_TYPE=site
				create
                        else
                                error_display "Configuration for $SiteName is missing"
                        fi


		fi
		;;
	install)
		while getopts ":u:p:" o
                do
                        case "${o}" in
                        u)
                                UserName=${OPTARG}
                                ;;
                        p)
                                Bins=${OPTARG}
                                ;;
                        esac
                done
                shift $((OPTIND-1))
		
		if [ -n "$UserName" ] && [ -f $CFGDIR/accounts/$UserName/user.conf ] && grep -q 'OBJECT_TYPE=primary' $CFGDIR/accounts/$UserName/user.conf
                then
                	. $CFGDIR/accounts/$UserName/user.conf
                else
                	error_display "Username is not specified or configuration is missing or account is not primary"
                fi

		install_extra_bins $Bins
		;;
	update)
		while getopts ":u:p:" o
                do
                        case "${o}" in
                        u)
                                UserName=${OPTARG}
                                ;;
                        p)
                                Bins=${OPTARG}
                                ;;
                        esac
                done
                shift $((OPTIND-1))
		if [ -n "$UserName" ] && [ -f $CFGDIR/accounts/$UserName/user.conf ] && grep -q 'OBJECT_TYPE=primary' $CFGDIR/accounts/$UserName/user.conf
                then
                        . $CFGDIR/accounts/$UserName/user.conf
                else
                        error_display "Username is not specified or configuration is missing or account is not primary"
                fi
		
		update_chroot_bins $Bins
		;;
		
		
	blueprint)
		while getopts ":u:gcf:" o
		do
			case "${o}" in
				u)
					UserName=${OPTARG}
					;;
				g)
					bp_gen=1
					;;
				c)
					bp_check=1
					;;
				f)
					bp_against=${OPTARG}
					;;
			esac
		done 
		shift $((OPTIND-1))

		if [ -n "$UserName" ] && [ -f $CFGDIR/accounts/$UserName/user.conf ] && grep -q 'OBJECT_TYPE=primary' $CFGDIR/accounts/$UserName/user.conf 
		then
                        . $CFGDIR/accounts/$UserName/user.conf
                else
                        error_display "Username is not specified or configuration is missing or account is not primary"
                fi
		
		[ "$bp_gen" == "1" ] && [ "$bp_check" == "1" ] &&  error_display "Error: Please specify generate or compare blueprints"
		
		[ "$bp_gen" == "1" ] && gen_full_bp
		[ "$bp_check" == "1" ] && {
			[ -f $bp_against ] || error_display "The $bp_against doesn't exist."
			check_full_bp $bp_against
			}
		 
		;;
	*)
		usage
		;;
esac	

exit
