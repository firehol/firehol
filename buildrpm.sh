#!/bin/bash
# $Id: buildrpm.sh,v 1.9 2004/11/01 00:23:08 ktsaou Exp $
# 
# This script will build a FireHOL RPM.
#

here=`pwd`

if [ -z "$1" -o -z "$2" ]
then
	printf "\n\nUSAGE: $0 version release\n\n"
	exit 1
fi

files="firehol.sh .spec examples/client-all.conf"

for x in $files
do
	if [ ! -f $x ]
	then
		printf "\n\nPlease step into firehol directory before doing this.\n\n"
		exit 1
	fi
done

myname="firehol-$1"
rpmname="$myname-$2"


printf "\nFireHOL RPM builder.\n"
printf "====================\n\n"

printf "This procedure will build the FireHOL RPM.\n\n"
printf "During this, your installed FireHOL files might\n"
printf "be overwritten.\n\n"
printf "Are you sure you want to build '${rpmname}' ? (yes/no) > "

read
if [ ! "$REPLY" = "yes" ]
then
	printf "ok. bye...\n\n"
	exit 1
fi

backup="/etc/init.d/firehol.$$"
backupconf="/etc/firehol/firehol.conf.$$"

# backup the current files.
test -f /etc/init.d/firehol       && mv -f /etc/init.d/firehol "${backup}"
test -f /etc/firehol/firehol.conf && mv -f /etc/firehol/firehol.conf "${backupconf}"

# make the tmp dir
test -d "/tmp/$myname" && rm -rf "/tmp/${myname}"
mkdir -p "/tmp/${myname}"

files="
README
TODO
COPYING
ChangeLog
WhatIsNew
firehol.sh
adblock.sh
buildrpm.sh
get-iana.sh
man/firehol.1
man/firehol.conf.5
examples/client-all.conf
examples/home-adsl.conf
examples/home-dialup.conf
examples/office.conf
examples/server-dmz.conf
examples/lan-gateway.conf
doc/adding.html
doc/commands.html
doc/css.css
doc/faq.html
doc/fwtest.html
doc/header.html
doc/index.html
doc/invoking.html
doc/language.html
doc/overview.html
doc/services.html
doc/search.html
doc/support.html
doc/trouble.html
doc/tutorial.html
"
for x in $files
do
	if [ ! -f "$x" ]
	then
		echo "Cannot find file: $x"
		exit 1
	fi
	install -D -m 644 $x "/tmp/$myname/$x"
done
chmod 755 /tmp/$myname/*.sh

# fix the rpm spec file
cat .spec						|\
	sed "s/^Version: MYVERSION/Version: $1/"	|\
	sed "s/^Release: MYRELEASE/Release: $2/" >"/tmp/$myname/.spec"

# make the tar
cd /tmp
tar jcpf "$myname.tar.bz2" "$myname"

# make the rpm
rpmbuild -tb "$myname.tar.bz2"

# cd to the old directory
cd "$here"

# restore the original files.
test -f "${backup}"     && mv -f "${backup}" /etc/init.d/firehol
test -f "${backupconf}" && mv -f "${backupconf}" /etc/firehol/firehol.conf
