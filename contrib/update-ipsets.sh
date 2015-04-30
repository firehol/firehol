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
if [ ! -d "${base}" ]
then
	mkdir -p "${base}" || exit 1
fi

ipset_list_names() {
	( ipset --list -t || ipset --list ) | grep "^Name: " | cut -d ' ' -f 2
}

# find the active ipsets
echo >&2 "Getting list of active ipsets..."
declare -A sets=()
for x in $(ipset_list_names)
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

aggregate_cmd() {
	local cmd="`which aggregate-flim`"
	if [ ! -z "${cmd}" ]
	then
		${cmd}
		return $?
	fi

	cmd="`which aggregate`"
	if [ ! -z "${cmd}" ]
	then
		${cmd} -p 32
		return $?
	fi

	echo >&2 "Warning: Cannot aggregate ip-ranges. Please install 'aggregate'. Working wihout aggregate."
	cat
}

filter_ip4()  { egrep "^[0-9\.]+$"; }
filter_net4() { egrep "^[0-9\.]+/[0-9]+$"; }
filter_all4() { egrep "^[0-9\.]+(/[0-9]+)?$"; }

filter_ip6()  { egrep "^[0-9a-fA-F:]+$"; }
filter_net6() { egrep "^[0-9a-fA-F:]+/[0-9]+$"; }
filter_all6() { egrep "^[0-9a-fA-F:]+(/[0-9]+)?$"; }

remove_slash32() { sed "s|/32$||g"; }
remove_slash128() { sed "s|/128$||g"; }

append_slash32() {
	# this command appends '/32' to all the lines
	# that do not include a slash
	awk '/\// {print $1; next}; // {print $1 "/32" }'	
}

append_slash128() {
	# this command appends '/32' to all the lines
	# that do not include a slash
	awk '/\// {print $1; next}; // {print $1 "/128" }'	
}

filter_invalid4() {
	egrep -v "^(0\.0\.0\.0|0\.0\.0\.0/0|255\.255\.255\.255|255\.255\.255\.255/0)$"
}

download_url() {
	local 	ipset="${1}" mins="${2}" url="${3}" \
		install="${base}/${1}" \
		tmp= now= date=

	tmp="${install}.tmp.$$.${RANDOM}"

	# check if we have to download again
	now=$(date +%s)
	date=$(date -d @$[now - (mins * 60)] +"%y%m%d%H%M.%S")
	touch -t "${date}" "${tmp}"

	if [ -f "${install}.source" -a "${install}.source" -nt "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: should not be downloaded so soon."
		return 0
	fi

	# download it
	test ${SILENT} -ne 1 && echo >&2 "${ipset}: downlading from '${url}'..."
	geturl "${url}" >"${tmp}"
	if [ $? -ne 0 ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: cannot download '${url}'."
		return 1
	fi

	if [ ! -s "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: empty file downloaded from url '${url}'."
		return 2
	fi

	if [ -f "${install}.source" ]
	then
		diff "${install}.source" "${tmp}" >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			# they are the same
			rm "${tmp}"
			test ${SILENT} -ne 1 && echo >&2 "${ipset}: downloaded file is the same with the previous one."
			touch "${install}.source"
			return 0
		fi
	fi

	test ${SILENT} -ne 1 && echo >&2 "${ipset}: saving downloaded file to ${install}.source"
	mv "${tmp}" "${install}.source" || return 1
	touch "${install}.source"
}

update() {
	local 	ipset="${1}" mins="${2}" ipv="${3}" type="${4}" url="${5}" processor="${6-cat}"
		install="${base}/${1}" tmp= error=0 now= date= pre_filter="cat" post_filter="cat" filter="cat"
	shift 6

	case "${ipv}" in
		ipv4)
			post_filter="filter_invalid4"
			case "${type}" in
				ip|ips)		hash="ip"
						type="ip"
						pre_filter="remove_slash32"
						filter="filter_ip4"
						;;

				net|nets)	hash="net"
						type="net"
						filter="filter_net4"
						post_filter="aggregate_cmd"
						;;

				both|all)	hash="net"
						type=""
						filter="filter_all4"
						post_filter="aggregate_cmd"
						;;

				split)		;;

				*)		echo >&2 "${ipset}: unknown type '${type}'."
						return 1
						;;
			esac
			;;
		ipv6)
			case "${type}" in
				ip|ips)		hash="ip"
						type="ip"
						pre_filter="remove_slash128"
						filter="filter_ip6"
						;;

				net|nets)	hash="net"
						type="net"
						filter="filter_net6"
						;;

				both|all)	hash="net"
						type=""
						filter="filter_all6"
						;;

				split)		;;

				*)		echo >&2 "${ipset}: unknown type '${type}'."
						return 1
						;;
			esac
			;;

		*)	echo >&2 "${ipset}: unknown IP version '${ipv}'."
			return 1
			;;
	esac

	echo >&2
	if [ ! -f "${install}.source" ]
	then
		echo >&2 "${ipset}: is disabled."
		echo >&2 "${ipset}: to enable it run: touch -t 0001010000 '${install}.source'"
		return 1
	fi

	# download it
	download_url "${ipset}" "${mins}" "${url}" || return 1

	if [ "${type}" = "split" ]
	then
		test -f "${install}_ip.source" && rm "${install}_ip.source"
		test -f "${install}_net.source" && rm "${install}_net.source"
		ln -s "${install}.source" "${install}_ip.source"
		ln -s "${install}.source" "${install}_net.source"
		update "${ipset}_ip" "${mins}" "${ipv}" ip  "${url}" "${processor}"
		update "${ipset}_net" "${mins}" "${ipv}" net "${url}" "${processor}"
		return $?
	fi

	# if it is newer than our destination
	if [ ! "${install}.source" -nt "${install}.${hash}set" ]
	then
		echo >&2 "${ipset}: not updated - no reason to process it again."
		return 0
	fi

	test ${SILENT} -ne 1 && echo >&2 "${ipset}: converting with processor '${processor}'"

	tmp="${install}.tmp.$$.${RANDOM}"
	${processor} <"${install}.source" |\
		${pre_filter} |\
		${filter} |\
		${post_filter} |\
		sort -u >"${tmp}"

	if [ $? -ne 0 ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: failed to convert file."
		return 1
	fi

	if [ ! -s "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: processed file gave no results."
		test ! -f "${install}.${hash}set" && touch "${install}.${hash}set"
		return 2
	fi

	diff "${install}.${hash}set" "${tmp}" >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		# they are the same
		rm "${tmp}"
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: processed set is the same with the previous one."
		touch "${install}.${hash}set"
		return 0
	fi

	local ipset_opts=
	local entries=$(wc -l "${tmp}" | cut -d ' ' -f 1)
	local size=$[ ( ( entries / 65536 ) + 1 ) * 65536 ]

	if [ -z "${sets[$ipset]}" ]
	then
		if [ ${size} -ne 65536 ]
		then
			echo >&2 "${ipset}: processed file gave ${entries} results - sizing to ${size} entries"
			echo >&2 "${ipset}: remember to append this to your ipset line (in firehol.conf): maxelem ${size}"
			ipset_opts="maxelem ${size}"
		fi

		echo >&2 "${ipset}: creating ipset with ${entries} entries"
		ipset --create ${ipset} "${hash}hash" ${ipset_opts} || return 1
	fi

	firehol ipset_update_from_file ${ipset} ${ipv} ${type} "${tmp}"
	if [ $? -ne 0 ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: failed to update ipset."
		return 1
	fi

	# all is good. keep it.
	mv "${tmp}" "${install}.${hash}set" || return 1

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

remove_comments_semi_colon() {
	# remove:
	# 1. everything on the same line after a ;
	# 2. multiple white space (tabs and spaces)
	# 3. leading spaces
	# 4. trailing spaces
	sed -e "s/;.*$//g" -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g"
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

unzip_and_split_csv() {
	funzip | tr "," "\n"
}

unzip_and_extract() {
	funzip
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

update tor_servers 30 ipv4 ip \
	"https://torstatus.blutmagie.de/ip_list_all.php/Tor_ip_list_ALL.csv?r=${RANDOM}" \
	remove_comments


# -----------------------------------------------------------------------------
# EmergingThreats

# http://doc.emergingthreats.net/bin/view/Main/CompromisedHost
update compromised $[12*60-10] ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/compromised-ips.txt?r=${RANDOM}" \
	remove_comments

# Command & Control botnet servers by www.shadowserver.org
update botnet $[12*60-10] ipv4 ip \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-CC.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4

# This appears to be the SPAMHAUS DROP list, but distributed by EmergingThreats.
update spamhaus $[12*60-10] ipv4 net \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DROP.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4

# Top 20 attackers by www.dshield.org
update dshield $[12*60-10] ipv4 net \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DSHIELD.rules?r=${RANDOM}" \
	pix_deny_rules_to_ipv4

# includes botnet, spamhaus and dshield
update emerging_block $[12*60-10] ipv4 all \
	"http://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt?r=${RANDOM}" \
	remove_comments


# -----------------------------------------------------------------------------
# Spamhaus
# http://www.spamhaus.org

# http://www.spamhaus.org/drop/
# These guys say that this list should be dropped at tier-1 ISPs globaly!
update spamhaus_drop $[12*60-10] ipv4 net \
	"http://www.spamhaus.org/drop/drop.txt?r=${RANDOM}" \
	remove_comments_semi_colon

# extended DROP (EDROP) list.
# Should be used together with their DROP list.
update spamhaus_edrop $[12*60-10] ipv4 net \
	"http://www.spamhaus.org/drop/edrop.txt?r=${RANDOM}" \
	remove_comments_semi_colon


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
# Zeus trojan
# https://zeustracker.abuse.ch/blocklist.php

# This blocklists only includes IPv4 addresses that are used by the ZeuS trojan.
update zeus $[30-5] ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=ipblocklist&r=${RANDOM}" \
	remove_comments


# -----------------------------------------------------------------------------
# malc0de
# http://malc0de.com

# updated daily and populated with the last 30 days of malicious IP addresses.
update malc0de $[24*60-10] ipv4 ip \
	"http://malc0de.com/bl/IP_Blacklist.txt?r=${RANDOM}" \
	remove_comments

# -----------------------------------------------------------------------------
# Stop Forum Spam
# http://www.stopforumspam.com/downloads/

# to use this, create the ipset like this (in firehol.conf):
# >> ipset4 create stop_forum_spam hash:ip maxelem 500000
# -- normally, you don't need this set --
# -- use the hourly and the daily ones instead --
update stop_forum_spam $[24*60-10] ipv4 ip \
	"http://www.stopforumspam.com/downloads/bannedips.zip?r=${RANDOM}" \
	unzip_and_split_csv

# hourly update with IPs from the last 24 hours
update stop_forum_spam_1h $[60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_1.zip" \
	unzip_and_extract

# daily update with IPs from the last 7 days
update stop_forum_spam_7d $[24*60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_7.zip" \
	unzip_and_extract

# daily update with IPs from the last 30 days
update stop_forum_spam_30d $[24*60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_30.zip" \
	unzip_and_extract

# daily update with IPs from the last 90 days
update stop_forum_spam_90d $[24*60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_90.zip" \
	unzip_and_extract

# daily update with IPs from the last 180 days
update stop_forum_spam_180d $[24*60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_180.zip" \
	unzip_and_extract

# daily update with IPs from the last 365 days
update stop_forum_spam_365d $[24*60] ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_365.zip" \
	unzip_and_extract

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

