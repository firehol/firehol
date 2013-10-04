#!/bin/bash

installto=/usr/sbin

fh=`which firehol`	
[ -z "$fw" ] && fh="$installto/firehol"

fq=`which fireqos`
[ -z "$fq" ] && fq="$installto/fireqos"

echo "Copying firehol.sh to $fh"
cp firehol.sh "$fh"
chown root:root "$fh"
chmod 0755 "$fh"

echo "Copying fireqos.sh to $fq"
cp fireqos.sh "$fq"
chown root:root "$fq"
chmod 0755 "$fq"

if [ ! -d /etc/firehol ]
then
	echo "Creating /etc/firehol"
	mkdir /etc/firehol
	chown root:root /etc/firehol
	chmod 0755 /etc/firehol
fi
