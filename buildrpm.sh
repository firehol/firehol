#!/bin/bash

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
backupconf="/etc/firehol.conf.$$"

# backup the current files.
test -f /etc/init.d/firehol && mv -f /etc/init.d/firehol "${backup}"
test -f /etc/firehol.conf   && mv -f /etc/firehol.conf "${backupconf}"

# make the tmp dir
test -d "/tmp/$myname" && rm -rf "/tmp/${myname}"
mkdir -p "/tmp/${myname}"

# copy all needed files
find . -type f			|\
	grep -v "\.bck"		|\
	grep -v "CVS"		|\
	grep -v "buildrpm.sh"	|\
	grep -v "\~"		|\
	sed "s/^.\///"		|\
	(
		while read
		do
#			echo $REPLY
			install -D -m 644 $REPLY "/tmp/$myname/$REPLY"
		done
		chmod 755 /tmp/$myname/*.sh
	)

# fix the rpm spec file
cat .spec					|\
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
test -f "${backupconf}" && mv -f "${backupconf}" /etc/firehol.conf
