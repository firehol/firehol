#!/bin/bash

# $Id: get-iana.sh,v 1.6 2004/01/10 18:44:39 ktsaou Exp $
#
# $Log: get-iana.sh,v $
# Revision 1.6  2004/01/10 18:44:39  ktsaou
# Further optimized and reduced PRIVATE_IPS using:
# http://www.vergenet.net/linux/aggregate/
#
# The supplied get-iana.sh uses 'aggregate-flim' if it finds it in the path.
# (aggregate-flim is the name of this program when installed on Gentoo)
#
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

test "$1" = "a" && AGGREGATE="`which aggregate-flim 2>/dev/null`"

printf 'RESERVED_IPS="'

wget -O - --proxy=off "${IPV4_ADDRESS_SPACE_URL}" 2>>$LOG	|\
	grep "${IANA_RESERVED}"					|\
	cut -d ' ' -f 1						|\
(
	
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
			echo "$x.0.0.0/$net"
			x=$[x + 1]
		done
	done
) | \
(
	if [ ! -z "${AGGREGATE}" -a -x "${AGGREGATE}" ]
	then
		"${AGGREGATE}" | (
			while read x
			do
				printf "$x "
			done
		)
	else
		while read x
		do
			printf "$x "
		done
	fi
)
printf '"'
echo

echo
echo "Press enter to view the log..."
read
less $LOG
rm -f $LOG
