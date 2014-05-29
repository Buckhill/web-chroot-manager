#!/bin/bash
#Author: Marko Bencek
#email: marko@buckhill.co.uk
#Date 05/29/2014
#Copyright Buckhill Ltd 2014
#Website www.buckhill.co.uk
#GitHub: https://github.com/Buckhill/web-chroot-manager
#License GPLv3


[ "$(whoami)" != "root" ] && { echo "Run me as root";exit 1;}

INSTALL="/usr/local/sbin/web-chroot-manager.sh /etc/buckhill-wcm"
stop=0
for I in $INSTALL
do
	if [ -d $I ] || [ -f $I ] || [ -L $I ]
	then
		echo "The $I already exists"
		stop=1
	fi
		
	if [ -d ./${I##*/} ] || [ -f ./${I##*/} ]
	then
		:
	else
		echo "The ./${I##*/} doesn't exist"
		stop=1
	fi
done

if [  $stop -eq 0 ]
then
	for I in $INSTALL
	do
		cp -rv ./${I##*/} $I
		chmod +x $I
	done
else
	echo "Installation is stopped due to previous errors"
	exit 1
fi

