#!/bin/sh
# $Id: check-iana.sh,v 1.2 2008/03/17 22:08:43 ktsaou Exp $

MYMAIL="$1"
if [ -z "${MYMAIL}" ]
then
	echo >&2 "Please set your e-mail."
	exit 1
fi

IPV4_ADDRESS_SPACE_URL="http://www.iana.org/assignments/ipv4-address-space"

ianafile=iana-reserved.txt
spooldir=/var/spool/firehol

mkdir -p "${spooldir}" || exit 1
cd "${spooldir}" || exit 1

wget -O - --proxy=off "${IPV4_ADDRESS_SPACE_URL}?" >"${spooldir}/${ianafile}.tmp" 2>/dev/null
if [ ! -s "${spooldir}/${ianafile}.tmp" ]
then
	logger -p alert -t FireHOL "Cannot fetch '${IPV4_ADDRESS_SPACE_URL}'."
	exit 1
fi

if [ ! -s "${spooldir}/${ianafile}" ]
then
	logger -p alert -t FireHOL "First fetch of '${IPV4_ADDRESS_SPACE_URL}'."
	mv -f "${spooldir}/${ianafile}.tmp" "${spooldir}/${ianafile}"
	exit 0
fi

diff "${spooldir}/${ianafile}" "${spooldir}/${ianafile}.tmp" >/dev/null 2>&1
if [ $? -eq 0 ]
then
	logger -p alert -t FireHOL "Page '${IPV4_ADDRESS_SPACE_URL}' not changed."
	exit 0
else
	cat <<EOF | sendmail -bm -i -oi -t
From: IANA Monitor on `hostname` <${MYMAIL}>
To: FireHOL Admins <${MYMAIL}>
Errors-To: FireHOL Admins <${MYMAIL}>
Subject: New IANA Reservations Detected!

 Dear admin,

 The following changes have been made at IANA Reservations page.

`diff "${spooldir}/${ianafile}" "${spooldir}/${ianafile}.tmp"`

 You may have to update your firewall by running the get-iana.sh script.

 Regards,

 Your IANA Reservations Monitor

EOF

	logger -p alert -t FireHOL "Changes detected in '${IPV4_ADDRESS_SPACE_URL}'. Mail sent to '${MYMAIL}'."
	mv -f "${spooldir}/${ianafile}.tmp" "${spooldir}/${ianafile}"
	exit 0
fi

exit 1

