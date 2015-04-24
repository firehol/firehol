#!/bin/bash
#
# FireHOL - A firewall for humans...
#
#   Copyright
#
#       Copyright (C) 2003-2014 Costa Tsaousis <costa@tsaousis.gr>
#       Copyright (C) 2012-2014 Phil Whineray <phil@sanewall.org>
#
#   License
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#       See the file COPYING for details.
#

# -- CONFIGURATION IS AT THE END OF THIS SCRIPT --

PATH="${PATH}:/sbin:/usr/sbin"

LC_ALL=C
umask 077

if [ ! "$UID" = "0" ]
then
	echo >&2 "Please run me as root."
	exit 1
fi

SILENT=0
[ "a${1}" = "a-s" ] && SILENT=1

# find a curl or wget
curl="$(which curl 2>/dev/null)"
test -z "${curl}" && wget="$(which wget 2>/dev/null)"
if [ -z "${curl}" -a -z "${wget}" ]
then
	echo >&2 "Please install curl or wget."
	exit 1
fi

# create the directory to save the sets
base="/etc/firehol/ipsets"
test ! -d "${base}" && ( mkdir -p "${base}" || exit 1 )

# find the active ipsets
declare -A sets=()
for x in $(ipset --save | egrep "^(create|-N|--create) " | cut -d ' ' -f 2)
do
	sets[$x]=1
done
test ${SILENT} -ne 1 && echo >&2 "Found these ipsets active: ${!sets[@]}"

# fetch a url by either curl or wget
geturl() {
	if [ ! -z "${curl}" ]
	then
		${curl} -o - -s "${1}"
	elif [ ! -z "${wget}" ]
	then
		${wget} -O - --quiet "${1}"
	else
		echo >&2 "Neither curl, nor wget is present."
		exit 1
	fi
}

update() {
	local 	ipset="${1}" mins="${2}" ipv="${3}" type="${4}" url="${5}" \
		processor="${6-cat}" install="${base}/${1}" \
		tmp= error=0 now= date=
	shift 6

	case "${ipv}" in
		ipv4)
			case "${type}" in
				ip|ips)		hash="ip"
						type="ip"
						filter="^[0-9\.]+$"
						;;

				net|nets)	hash="net"
						type="net"
						filter="^[0-9\./]+$"
						;;

				both|all)	hash="net"
						type=""
						filter="^[0-9\./]+$"
						;;

				*)		echo >&2 "Unknown type '${type}'."
						return 1
						;;
			esac
			;;
		ipv6)
			case "${type}" in
				ip|ips)		hash="ip"
						type="ip"
						filter="^[0-9a-fA-F:]+$"
						;;

				net|nets)	hash="net"
						type="net"
						filter="^[0-9a-fA-F:/]+$"
						;;

				both|all)	hash="net"
						type=""
						filter="^[0-9a-fA-F:/]+$"
						;;

				*)		echo >&2 "Unknown type '${type}'."
						return 1
						;;
			esac
			;;

		*)	echo >&2 "Unknown IP version '${ipv}'."
			return 1
			;;
	esac

	tmp="${install}.tmp.$$.${RANDOM}"

	# check if we have to download again
	now=$(date +%s)
	date=$(date -d @$[now - (mins * 60)] +"%y-%m-%d %H:%M:%S")
	touch -t "${date}" "${tmp}"

	if [ -f "${install}.source" -a "${install}.source" -nt "${tmp}" ]
	then
		rm "${tmp}"
		test ${SILENT} -ne 1 && echo >&2 "Ipset '${ipset}' is already up to date."
		return 2
	fi

	# download it
	test ${SILENT} -ne 1 && echo >&2 "Downlading ipset '${ipset}' from '${url}'..."
	geturl "${url}" >"${tmp}"
	if [ $? -ne 0 ]
	then
		rm "${tmp}"
		echo >&2 "Cannot download '${url}'."
		return 1
	fi

	if [ ! -s "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "Download of '${url}' is empty."
		return 1
	fi

	if [ -f "${install}.source" ]
	then
		diff "${install}.source" "${tmp}" >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			# they are the same
			rm "${tmp}"
			test ${SILENT} -ne 1 && echo >&2 "Downloaded file for ${ipset}, is the same with the previous one."
			return 0
		fi
	fi

	test ${SILENT} -ne 1 && echo >&2 "Saving ${ipset} to ${install}.source"
	mv "${tmp}" "${install}.source" || return 1

	test ${SILENT} -ne 1 && echo >&2 "Converting ${ipset} using processor: ${processor}"
	${processor} <"${install}.source" | egrep "${filter}" | sort -u >"${tmp}" || return 1
	mv "${tmp}" "${install}.${hash}set" || return 1

	if [ -z "${sets[$ipset]}" ]
	then
		echo >&2 "Creating ipset '${ipset}'..."
		ipset --create ${ipset} "${hash}hash" || return 1
	fi

	firehol ipset_update_from_file ${ipset} ${ipv} ${type} "${install}.${hash}set"
	if [ $? -ne 0 ]
	then
		echo >&2 "Failed to update ipset '${ipset}' from url '${url}'."
		return 1
	fi

	return 0
}

# -----------------------------------------------------------------------------
# CONVERTERS
# These functions are used to convert from various sources
# to IP or NET addresses

subnet_to_bitmask() {
	sed	-e "s|/255\.255\.255\.255|/32|g" -e "s|/255\.255\.255\.254|/31|g" -e "s|/255\.255\.255\.252|/30|g" \
		-e "s|/255\.255\.255\.248|/29|g" -e "s|/255\.255\.255\.240|/28|g" -e "s|/255\.255\.255\.224|/27|g" \
		-e "s|/255\.255\.255\.192|/26|g" -e "s|/255\.255\.255\.128|/25|g" -e "s|/255\.255\.255\.0|/24|g" \
		-e "s|/255\.255\.254\.0|/23|g"   -e "s|/255\.255\.252\.0|/22|g"   -e "s|/255\.255\.248\.0|/21|g" \
		-e "s|/255\.255\.240\.0|/20|g"   -e "s|/255\.255\.224\.0|/19|g"   -e "s|/255\.255\.192\.0|/18|g" \
		-e "s|/255\.255\.128\.0|/17|g"   -e "s|/255\.255\.0\.0|/16|g"     -e "s|/255\.254\.0\.0|/15|g" \
		-e "s|/255\.252\.0\.0|/14|g"     -e "s|/255\.248\.0\.0|/13|g"     -e "s|/255\.240\.0\.0|/12|g" \
		-e "s|/255\.224\.0\.0|/11|g"     -e "s|/255\.192\.0\.0|/10|g"     -e "s|/255\.128\.0\.0|/9|g" \
		-e "s|/255\.0\.0\.0|/8|g"        -e "s|/254\.0\.0\.0|/7|g"        -e "s|/252\.0\.0\.0|/6|g" \
		-e "s|/248\.0\.0\.0|/5|g"        -e "s|/240\.0\.0\.0|/4|g"        -e "s|/224\.0\.0\.0|/3|g" \
		-e "s|/192\.0\.0\.0|/2|g"        -e "s|/128\.0\.0\.0|/1|g"        -e "s|/0\.0\.0\.0|/0|g"
}

remove_comments() {
	# remove:
	# 1. everything on the same line after a #
	# 2. multiple white space (tabs and spaces)
	# 3. leading spaces
	# 4. trailing spaces
	sed -e "s/#.*$//g" -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g"
}

# convert snort rules to a list of IPs
snort_alert_rules_to_ipv4() {
	remove_comments |\
		grep ^alert |\
		sed -e "s|^alert .* \[\([0-9/,\.]\+\)\] any -> \$HOME_NET any .*$|\1|g" -e "s|,|\n|g" |\
		grep -v ^alert
}

pix_deny_rules_to_ipv4() {
	remove_comments |\
		grep ^access-list |\
		sed -e "s|^access-list .* deny ip \([0-9\.]\+\) \([0-9\.]\+\) any$|\1/\2|g" \
		    -e "s|^access-list .* deny ip host \([0-9\.]\+\) any$|\1|g" |\
		grep -v ^access-list |\
		subnet_to_bitmask
}


# -----------------------------------------------------------------------------
# CONFIGURATION

# TEMPLATE:
#
# > update NAME TIME_TO_UPDATE ipv4|ipv6 ip|net URL CONVERTER
#
# NAME           the name of the ipset
# TIME_TO_UPDATE minutes to refresh/re-download the URL
# ipv4 or ipv6   the IP version of the ipset
# ip or net      use hash:ip or hash:net ipset
# URL            the URL to download
# CONVERTER      a command to convert the downloaded file to IP addresses

# - It creates the ipset if it does not exist
# - FireHOL will be called to update the ipset
# - both downloaded and converted files are saved in
#   ${base} (/etc/firehol/ipsets)

# RUNNING THIS SCRIPT WILL JUST INSTALL THE IPSETS.
# IT WILL NOT BLOCK OR BLACKLIST ANYTHING.
# YOU HAVE TO UPDATE YOUR firehol.conf TO BLACKLIST ANY OF THESE.
# Check: https://github.com/ktsaou/firehol/wiki/FireHOL-support-for-ipset

# EXAMPLE FOR firehol.conf:
#
# ipv4 ipset create  openbl hash:ip
#      ipset addfile openbl ipsets/openbl.ipset
#
# ipv4 ipset create  tor hash:ip
#      ipset addfile tor ipsets/tor.ipset
#
# ipv4 ipset create  compromised hash:ip
#      ipset addfile compromised ipsets/compromised.ipset
#
# ipv4 ipset create emerging_block hash:net
#      ipset addfile emerging_block ipsets/emerging_block.netset
#
# ipv4 blacklist full \
#         ipset:openbl \
#         ipset:tor \
#         ipset:emerging_block \
#         ipset:compromised \
#

# -----------------------------------------------------------------------------
# www.openbl.org
update openbl $[4*60-10] ipv4 ip \
	"http://www.openbl.org/lists/base.txt?r=${RANDOM}" \
	remove_comments


# -----------------------------------------------------------------------------
# TOR lists
# TOR is not necessary hostile, you may need this just for sensitive services.

# https://www.dan.me.uk/tornodes
# This contains a full TOR nodelist (no more than 30 minutes old).
# The page has download limit that does not allow download in less than 30 min.
update danmetor 30 ipv4 ip \
	"https://www.dan.me.uk/torlist/?r=${RANDOM}" \
	remove_comments

# http://doc.emergingthreats.net/bin/view/Main/TorRules
update tor $[12*60-10] ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/emerging-tor.rules?r=${RANDOM}" \
	snort_alert_rules_to_ipv4


# -----------------------------------------------------------------------------
# EmergingThreats

# http://doc.emergingthreats.net/bin/view/Main/CompromisedHost
update compromised $[12*60-10] ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/compromised-ips.txt?r=${RANDOM}" \
	remove_comments

# includes botnet, spamhaus and dshield
update emerging_block $[12*60-10] ipv4 all \
	"http://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt?r=${RANDOM}" \
	remove_comments

# Command & Control botnet servers by www.shadowserver.org
update botnet $[12*60-10] ipv4 ip \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-CC.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4

# Spam networks identified by www.spamhaus.org
update spamhaus $[12*60-10] ipv4 net \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DROP.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4

# Top 20 attackers by www.dshield.org
update dshield $[12*60-10] ipv4 net \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DSHIELD.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4


# -----------------------------------------------------------------------------
# blocklist.de
# http://www.blocklist.de/en/export.html

# All IP addresses that have attacked one of their customers/servers in the
# last 48 hours. Updated every 30 minutes.
# They also have lists of service specific attacks (ssh, apache, sip, etc).
update blocklist_de $[30-5] ipv4 ip \
	"http://lists.blocklist.de/lists/all.txt?r=${RANDOM}" \
	remove_comments

# -----------------------------------------------------------------------------
# Bogons
# Bogons are IP addresses that should not be routed because they are not
# allocated, or they are allocated for private use.
# IMPORTANT: THESE LISTS INCLUDE ${PRIVATE_IPS}
#            always specify an 'inface' when blacklisting in FireHOL

# http://www.team-cymru.org/bogon-reference.html
# private and reserved addresses defined by RFC 1918, RFC 5735, and RFC 6598
# and netblocks that have not been allocated to a regional internet registry
# (RIR) by the Internet Assigned Numbers Authority.
update bogons $[24*60-10] ipv4 net \
	"http://www.team-cymru.org/Services/Bogons/bogon-bn-agg.txt?r=${RANDOM}" \
	remove_comments

# http://www.team-cymru.org/bogon-reference.html
# Fullbogons are a larger set which also includes IP space that has been
# allocated to an RIR, but not assigned by that RIR to an actual ISP or other
# end-user.
update fullbogons $[24*60-10] ipv4 net \
	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt?r=${RANDOM}" \
	remove_comments

#update fullbogons6 $[24*60-10] ipv6 net \
#	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt?r=${RANDOM}" \
#	remove_comments


