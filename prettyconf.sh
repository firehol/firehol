#!/bin/sh

COMMS="http://firehol.sourceforge.net/commands.html"

if [ ! -f "$1" ]
then
	echo "$0 filename"
	exit 1
fi

CONF="/tmp/prettyconf.sed"

rm -f "${CONF}"
touch "${CONF}"



keyword() {
	cat <<EOF >>"${CONF}"
s|^$1[[:space:]]|<a href="${COMMS}#$1">$1</a> |g
s|[[:space:]]$1[[:space:]]| <a href="${COMMS}#$1">$1</a> |g
EOF

}

keyword interface
keyword router
keyword server
keyword client
keyword route
keyword protection
keyword iptables
keyword accept
keyword reject
keyword src
keyword dst
keyword inface
keyword outface

#echo >"${CONF}" "s/\//a/g"
#echo >>"${CONF}" "s/e/a/g"

cat $1 | sed -f "${CONF}"

cat "${CONF}"
