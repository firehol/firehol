#!/bin/bash

# $Id: get-iana.sh,v 1.5 2003/08/23 23:26:50 ktsaou Exp $
#
# $Log: get-iana.sh,v $
# Revision 1.5  2003/08/23 23:26:50  ktsaou
# Bug #793889:
# Change #!/bin/sh to #!/bin/bash to allow FireHOL run on systems that
# bash is not linked to /bin/sh.
#
# Revision 1.4  2002/10/27 12:44:42  ktsaou
# CVS test
#

#
# Program that downloads the IPv4 address space allocation by IANA
# and creates a list with all reserved address spaces.
#

IPV4_ADDRESS_SPACE_URL="http://www.iana.org/assignments/ipv4-address-space"
IANA_RESERVED="IANA - Reserved"

LOG="/tmp/log.$$"

wget -O - --proxy=off "${IPV4_ADDRESS_SPACE_URL}" 2>>$LOG	|\
	grep "${IANA_RESERVED}"					|\
	cut -d ' ' -f 1						|\
(
	printf 'RESERVED_IPS="'
	
	while IFS="/" read range net
	do
		if [ ! $net -eq 8 ]
		then
			echo >>$LOG "Cannot handle network masks of $net bits ($range/$net)"
			continue
		fi
		 
		first=`echo $range | cut -d '-' -f 1`
		first=`expr $first + 0`
		last=`echo $range | cut -d '-' -f 2`
		last=`expr $last + 0`
		
		x=$first
		while [ ! $x -gt $last ]
		do
			printf "$x.0.0.0/$net "
			x=$[x + 1]
		done
	done
	
	printf '"'
	echo
)

echo
echo "Press enter to view the log..."
read
less $LOG
rm -f $LOG
