#!/bin/sh

#
# Program that downloads the IPv4 address space allocation by IANA
# and creates a list with all reserved address spaces.
#

IPV4_ADDRESS_SPACE_URL="http://www.iana.org/assignments/ipv4-address-space"
IANA_RESERVED="IANA - Reserved"

LOG="/tmp/log.$$"

wget -O - --proxy=off "${IPV4_ADDRESS_SPACE_URL}" 2>>$LOG	|\
	grep "${RESERVED_IPS}"					|\
	cut -d ' ' -f 1						|\
(
	printf 'IANA_RESERVED="'
	
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
