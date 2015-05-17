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

# What this program does:
#
# 1. It downloads a number of IP lists
#    - respects network resource: it will download a file only if it has
#      been changed on the server (IF_MODIFIED_SINCE)
#    - it will not attempt to download a file too frequently
#      (it has a maximum frequency per download URL embedded, so that
#      even if a server does not support IF_MODIFIED_SINCE it will not
#      download the IP list too frequently).
#
# 2. Once a file is downloaded, it will convert it either to
#    an ip:hash or a net:hash ipset.
#    It can convert:
#    - text files
#    - snort rules files
#    - PIX rules files
#    - XML files (like RSS feeds)
#    - CSV files
#    - compressed files (zip, gz, etc)
#
# 3. For all file types it can keep a history of the processed sets
#    that can be merged with the new downloaded one, so that it can
#    populate the generated set with all the IPs of the last X days.
#
# 4. For each set updated, it will call firehol to update the ipset
#    in memory, without restarting the firewall.
#    It considers an update successful only if the ipset is updated
#    in kernel successfuly.
#    Keep in mind that firehol will create a new ipset, add all the
#    IPs to it and then swap the right ipset with the temporary one
#    to activate it. This means that the ipset is updated only if
#    it can be parsed completely.
#
# 5. It can commit all successfully updated files to a git repository.
#    If it is called with -g it will also push the committed changes
#    to a remote git server (to have this done by cron, please set
#    git to automatically push changes with human action).
#
#
# -----------------------------------------------------------------------------
#
# How to use it:
# 
# Please make sure the file ipv4_range_to_cidr.awk is in the same directory
# as this script. If it is not, certain lists that need it will be disabled.
# 
# 1. Make sure you have firehol v3 or later installed.
# 2. Run this script. It will give you instructions on which
#    IP lists are available and what to do to enable them.
# 3. Enable a few lists, following its instructions.
# 4. Run it again to update the lists.
# 5. Put it in a cron job to do the updates automatically.

# -----------------------------------------------------------------------------
# At the end of file you can find the configuration for each of the IP lists
# it supports.
# -----------------------------------------------------------------------------

# single line flock, from man flock
# Normally this is not needed since the script is using unique tmp files for all
# operations and moves them to their final place when done.
# However, this is the only protection against very slow downloads and a high
# frequency run from a cron job. It will ensure that a second instance will run
# only if the first has finished.
[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -en "$0" "$0" "$@" || :

PATH="${PATH}:/sbin:/usr/sbin"

LC_ALL=C
umask 077

if [ ! "$UID" = "0" ]
then
	echo >&2 "Please run me as root."
	exit 1
fi

program_pwd="${PWD}"
program_dir="`dirname ${0}`"
awk="$(which awk 2>/dev/null)"
CAN_CONVERT_RANGES_TO_CIDR=0
if [ ! -z "${awk}" -a -x "${program_dir}/ipv4_range_to_cidr.awk" ]
then
	CAN_CONVERT_RANGES_TO_CIDR=1
fi

ipv4_range_to_cidr() {
	cd "${program_pwd}"
	${awk} -f "${program_dir}/ipv4_range_to_cidr.awk"
	cd "${OLDPWD}"
}

PUSH_TO_GIT=0
SILENT=0
while [ ! -z "${1}" ]
do
	case "${1}" in
		-s) SILENT=1;;
		-g) PUSH_TO_GIT=1;;
		*) echo >&2 "Unknown parameter '${1}'".; exit 1 ;;
	esac
	shift
done

# find curl
curl="$(which curl 2>/dev/null)"
if [ -z "${curl}" ]
then
	echo >&2 "Please install curl."
	exit 1
fi

# create the directory to save the sets
base="/etc/firehol/ipsets"
if [ ! -d "${base}" ]
then
	mkdir -p "${base}" || exit 1
fi
cd "${base}" || exit 1

if [ ! -d ".git" -a ${PUSH_TO_GIT} -ne 0 ]
then
	echo >&2 "Git is not initialized in ${base}. Ignoring git support."
	PUSH_TO_GIT=0
fi

mins_to_text() {
	local days= hours= mins="${1}"

	days=$[mins / (24*60)]
	mins=$[mins - (days * 24 * 60)]

	hours=$[mins / 60]
	mins=$[mins - (hours * 60)]

	case ${days} in
		0) ;;
		1) printf "1 day " ;;
		*) printf "%d days " ${days} ;;
	esac
	case ${hours} in
		0) ;;
		1) printf "1 hour " ;;
		*) printf "%d hours " ${hours} ;;
	esac
	case ${mins} in
		0) ;;
		1) printf "1 min " ;;
		*) printf "%d mins " ${mins} ;;
	esac
	printf "\n"
}

commit_to_git() {
	if [ -d .git -a ! -z "${!UPDATED_SETS[*]}" ]
	then
		echo >&2 
		echo >&2 "Committing ${UPDATED_SETS[@]} README.md to git repository"

		[ ! -f README-EDIT.md ] && touch README-EDIT.md
		(
			cat README-EDIT.md
			echo
			echo "The following list was automatically generated on `date -u`."
			echo
			echo "The update frequency is the maximum allowed by internal configuration. A list will never be downloaded sooner than the update frequency stated. A list may also not be downloaded, after this frequency expired, if it has not been modified on the server (as reported by HTTP \`IF_MODIFIED_SINCE\` method)."
			echo
			echo "name|info|type|entries|update|"
			echo ":--:|:--:|:--:|:-----:|:----:|"
			cat *.setinfo
		) >README.md
		
		git commit "${UPDATED_SETS[@]}" README.md -m "`date -u` update"

		if [ ${PUSH_TO_GIT} -ne 0 ]
		then
			echo >&2 
			echo >&2 "Pushing git commits to remote server"
			git push
		fi
	fi

	trap exit EXIT
	exit 0
}
# make sure we commit to git when we exit
trap commit_to_git EXIT
trap commit_to_git SIGHUP
trap commit_to_git INT

touch_in_the_past() {
	local mins_ago="${1}" file="${2}"

	local now=$(date +%s)
	local date=$(date -d @$[now - (mins_ago * 60)] +"%y%m%d%H%M.%S")
	touch -t "${date}" "${file}"
}
touch_in_the_past $[7 * 24 * 60] ".warn_if_last_downloaded_before_this"

ipset_list_names() {
	( ipset --list -t || ipset --list ) | grep "^Name: " | cut -d ' ' -f 2
}

echo
echo "`date`: ${0} ${*}" 
echo

# find the active ipsets
echo >&2 "Getting list of active ipsets..."
declare -A sets=()
for x in $(ipset_list_names)
do
	sets[$x]=1
done
test ${SILENT} -ne 1 && echo >&2 "Found these ipsets active: ${!sets[@]}"

aggregate4() {
	local cmd=

	cmd="`which iprange 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		${cmd} -J
		return $?
	fi
	
	cmd="`which aggregate-flim 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		${cmd}
		return $?
	fi

	cmd="`which aggregate 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		sed "s|^\([0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\\)$|\1/32|g" |\
			${cmd} -t

		return $?
	fi

	echo >&2 "Warning: Cannot aggregate ip-ranges. Please install 'aggregate'. Working wihout aggregate."
	cat
}

filter_ip4()  { egrep "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; }
filter_net4() { egrep "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$"; }
filter_all4() { egrep "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9\.]+(/[0-9]+)?$"; }

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

check_file_too_old() {
	local ipset="${1}" file="${2}"

	if [ -f "${file}" -a ".warn_if_last_downloaded_before_this" -nt "${file}" ]
	then
		echo >&2 "${ipset}: IMPORTANT: SET DATA ARE TOO OLD!"
		return 1
	fi
	return 0
}

history_manager() {
	local ipset="${1}" mins="${2}" file="${3}" \
		tmp= x= slot="`date +%s`.set"

	# make sure the directories exist
	if [ ! -d "history" ]
	then
		mkdir "history" || return 1
		chmod 700 "history"
	fi

	if [ ! -d "history/${ipset}" ]
	then
		mkdir "history/${ipset}" || return 2
		chmod 700 "history/${ipset}"
	fi

	# touch a reference file
	touch_in_the_past ${mins} "history/${ipset}/.reference" || return 3

	# move the new file to the rss history
	mv "${file}" "history/${ipset}/${slot}"
	touch "history/${ipset}/${slot}"

	# replace the original file with a concatenation of
	# all the files newer than the reference file
	for x in history/${ipset}/*.set
	do
		if [ "${x}" -nt "history/${ipset}/.reference" ]
		then
			test ${SILENT} -ne 1 && echo >&2 "${ipset}: merging history file '${x}'"
			cat "${x}"
		else
			rm "${x}"
		fi
	done | sort -u >"${file}"
	rm "history/${ipset}/.reference"

	return 0
}

# fetch a url by either curl or wget
# the output file has the last modified timestamp
# of the server
# on the next run, the file is downloaded only
# if it has changed on the server
geturl() {
	local file="${1}" reference="${2}" url="${3}" ret=

	# copy the timestamp of the reference
	# to our file
	touch -r "${reference}" "${file}"

	${curl} -z "${reference}" -o "${file}" -s -L -R "${url}"
	ret=$?

	if [ ${ret} -eq 0 -a ! "${file}" -nt "${reference}" ]
	then
		return 99
	fi
	return ${ret}
}

download_url() {
	local 	ipset="${1}" mins="${2}" url="${3}" \
		install="${1}" \
		tmp= now= date=

	tmp=`mktemp "${install}.tmp-XXXXXXXXXX"` || return 1

	# check if we have to download again
	touch_in_the_past "${mins}" "${tmp}"
	if [ "${install}.source" -nt "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: should not be downloaded so soon."
		return 0
	fi

	# download it
	test ${SILENT} -ne 1 && echo >&2 "${ipset}: downlading from '${url}'..."
	geturl "${tmp}" "${install}.source" "${url}"
	case $? in
		0)	;;
		99)
			echo >&2 "${ipset}: file on server has not been updated yet"
			rm "${tmp}"
			# we have to return success here, so that the ipset will be
			# created if it does not exist yet
			return 0
			;;

		*)
			echo >&2 "${ipset}: cannot download '${url}'."
			rm "${tmp}"
			return 1
			;;
	esac

	# check if the downloaded file is empty
	if [ ! -s "${tmp}" ]
	then
		# it is empty
		rm "${tmp}"
		echo >&2 "${ipset}: empty file downloaded from url '${url}'."
		return 2
	fi

	# check if the downloaded file is the same with the last one
	diff "${install}.source" "${tmp}" >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		# they are the same
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: downloaded file is the same with the previous one."

		# copy the timestamp of the downloaded to our file
		touch -r "${tmp}" "${install}.source"
		
		rm "${tmp}"

		# return success so that the set will be create
		# if it does not already exist.
		return 0
	fi

	# move it to its place
	test ${SILENT} -ne 1 && echo >&2 "${ipset}: saving downloaded file to ${install}.source"
	mv "${tmp}" "${install}.source" || return 1
}

declare -A UPDATED_SETS=()
update() {
	local 	ipset="${1}" mins="${2}" history_mins="${3}" ipv="${4}" type="${5}" url="${6}" processor="${7-cat}" info="${8}"
		install="${1}" tmp= error=0 now= date= pre_filter="cat" post_filter="cat" post_filter2="cat" filter="cat"
	shift 8

	case "${ipv}" in
		ipv4)
			post_filter2="filter_invalid4"
			case "${type}" in
				ip|ips)		hash="ip"
						type="ip"
						pre_filter="remove_slash32"
						filter="filter_ip4"
						;;

				net|nets)	hash="net"
						type="net"
						filter="filter_net4"
						post_filter="aggregate4"
						;;

				both|all)	hash="net"
						type=""
						filter="filter_all4"
						post_filter="aggregate4"
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
		echo >&2 "${ipset}: to enable it run: touch -t 0001010000 '${base}/${install}.source'"
		return 1
	fi

	# download it
	download_url "${ipset}" "${mins}" "${url}"
	if [ $? -ne 0 ]
	then
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 1
	fi

	if [ "${type}" = "split" -o \( -z "${type}" -a -f "${install}.split" \) ]
	then
		echo >&2 "${ipset}: spliting IPs and networks..."
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
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 0
	fi

	test ${SILENT} -ne 1 && echo >&2 "${ipset}: converting with processor '${processor}'"

	tmp=`mktemp "${install}.tmp-XXXXXXXXXX"` || return 1

	${processor} <"${install}.source" |\
		${pre_filter} |\
		${filter} |\
		${post_filter} |\
		${post_filter2} |\
		sort -u >"${tmp}"
	
	local ret=$?

	# give it the timestamp of the source
	touch -r "${install}.source" "${tmp}"

	if [ ${ret} -ne 0 ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: failed to convert file."
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 1
	fi

	if [ ! -s "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: processed file gave no results."

		# keep the old set, but make it think it was from this source
		touch -r "${install}.source" "${install}.${hash}set"

		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 2
	fi

	if [ $[history_mins + 1 - 1] -gt 0 ]
	then
		history_manager "${ipset}" "${history_mins}" "${tmp}"
	fi

	diff "${install}.${hash}set" "${tmp}" >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		# they are the same
		rm "${tmp}"
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: processed set is the same with the previous one."
		
		# keep the old set, but make it think it was from this source
		touch -r "${install}.source" "${install}.${hash}set"

		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 0
	fi

	local ipset_opts=
	local entries=$(wc -l "${tmp}" | cut -d ' ' -f 1)
	local size=$[ ( ( (entries * 130 / 100) / 65536 ) + 1 ) * 65536 ]

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

	#echo >&2 "${ipset}: calling firehol"
	firehol ipset_update_from_file ${ipset} ${ipv} ${type} "${tmp}"
	ret=$?
	#echo >&2 "${ipset}: firehol completed"

	if [ ${ret} -ne 0 ]
	then
		if [ -d errors ]
		then
			mv "${tmp}" "errors/${ipset}.${hash}set"
		else
			rm "${tmp}"
		fi
		echo >&2 "${ipset}: failed to update ipset."
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 1
	fi

	# all is good. keep it.
	mv "${tmp}" "${install}.${hash}set" || return 1
	UPDATED_SETS[${ipset}]="${install}.${hash}set"

	if [ -d .git ]
	then
		if [ "${hash}" = "net" ]
		then
			local ips=`cat "${install}.${hash}set" | cut -d '/' -f 2 | ( sum=0; while read i; do sum=$[sum + (1 << (32 - i))]; done; echo $sum )`
			echo >"${install}.setinfo" "${ipset}|${info}|${ipv} hash:${hash}|`wc -l "${install}.${hash}set" | cut -d ' ' -f 1` subnets, ${ips} unique IPs|updated every `mins_to_text ${mins}` from [this link](${url})"
		else
			echo >"${install}.setinfo" "${ipset}|${info}|${ipv} hash:${hash}|`wc -l "${install}.${hash}set" | cut -d ' ' -f 1` unique IPs|updated every `mins_to_text ${mins}` from [this link](${url})"
		fi

		git ls-files "${install}.${hash}set" --error-unmatch >/dev/null 2>&1
		if [ $? -ne 0 ]
			then
			echo >&2 "${ipset}: adding it to git"
			git add "${install}.${hash}set"
		fi
	fi

	return 0
}

# -----------------------------------------------------------------------------
# XML DOM PARSER
# excellent article about XML parsing is BASH
# http://stackoverflow.com/questions/893585/how-to-parse-xml-in-bash

XML_ENTITY=
XML_CONTENT=
XML_TAG_NAME=
XML_ATTRIBUTES=
read_xml_dom () {
	local IFS=\>
	read -d \< XML_ENTITY XML_CONTENT
	local ret=$?
	XML_TAG_NAME=${ENTITY%% *}
	XML_ATTRIBUTES=${ENTITY#* }
	return $ret
}

parse_rss_rosinstrument() {
	while read_xml_dom
	do
		if [ "${XML_ENTITY}" = "title" ]
		then
			if [[ "${XML_CONTENT}" =~ ^.*:[0-9]+$ ]]
			then
				local hostname="${XML_CONTENT/:*/}"

				if [[ "${hostname}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
				then
					# it is an IP already
					# echo "${hostname} # from ${XML_CONTENT}"
					echo "${hostname}"
				else
					# it is a hostname - resolve it
					local host=`host "${hostname}" | grep " has address " | cut -d ' ' -f 4`
					if [ $? -eq 0 -a ! -z "${host}" ]
					then
						# echo "${host} # from ${XML_CONTENT}"
						echo "${host}"
					#else
					#	echo "# Cannot resolve ${hostname} taken from ${XML_CONTENT}"
					fi
				fi
			fi
		fi
	done
}

parse_xml_clean_mx() {
	while read_xml_dom
	do
		case "${XML_ENTITY}" in
			ip) echo "${XML_CONTENT}"
		esac
	done
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
	# 1. replace \r with \n
	# 2. everything on the same line after a #
	# 3. multiple white space (tabs and spaces)
	# 4. leading spaces
	# 5. trailing spaces
	# 6. empty lines
	tr "\r" "\n" |\
		sed -e "s/#.*$//g" -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g" |\
		grep -v "^$"
}

gz_remove_comments() {
	gzip -dc | remove_comments
}

remove_comments_semi_colon() {
	# remove:
	# 1. replace \r with \n
	# 2. everything on the same line after a ;
	# 3. multiple white space (tabs and spaces)
	# 4. leading spaces
	# 5. trailing spaces
	# 6. empty lines
	tr "\r" "\n" |\
		sed -e "s/;.*$//g" -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g" |\
		grep -v "^$"
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

dshield_parser() {
	local net= mask=
	remove_comments | grep "^[1-9]" | cut -d ' ' -f 1,3 | while read net mask; do echo "${net}/${mask}"; done
}

unzip_and_split_csv() {
	funzip | tr ",\r" "\n\n"
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

update openbl $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base.txt.gz" \
	gz_remove_comments \
	"OpenBL.org default blacklist (currently it is the same with 90 days)"

update openbl_1d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_1days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 24 hours IPs"

update openbl_7d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_7days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 7 days IPs"

update openbl_30d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_30days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 30 days IPs"

update openbl_60d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_60days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 60 days IPs"

update openbl_90d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_90days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 90 days IPs"

update openbl_180d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_180days.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last 180 days IPs"

update openbl_all $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_all.txt.gz" \
	gz_remove_comments \
	"OpenBL.org last all IPs"

# -----------------------------------------------------------------------------
# www.dshield.org
# https://www.dshield.org/xml.html

# Top 20 attackers (networks) by www.dshield.org
update dshield $[4*60] 0 ipv4 net \
	"http://feeds.dshield.org/block.txt" \
	dshield_parser \
	"DShield.org top 20 attacking networks"


# -----------------------------------------------------------------------------
# TOR lists
# TOR is not necessary hostile, you may need this just for sensitive services.

# https://www.dan.me.uk/tornodes
# This contains a full TOR nodelist (no more than 30 minutes old).
# The page has download limit that does not allow download in less than 30 min.
update danmetor 30 0 ipv4 ip \
	"https://www.dan.me.uk/torlist/" \
	remove_comments \
	"dan.me.uk dynamic list of TOR exit points"

# http://doc.emergingthreats.net/bin/view/Main/TorRules
update tor $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/emerging-tor.rules" \
	snort_alert_rules_to_ipv4 \
	"EmergingThreats.net list of TOR network IPs"

update tor_servers 30 0 ipv4 ip \
	"https://torstatus.blutmagie.de/ip_list_all.php/Tor_ip_list_ALL.csv" \
	remove_comments \
	"torstatus.blutmagie.de list of all TOR network servers"


# -----------------------------------------------------------------------------
# EmergingThreats

# http://doc.emergingthreats.net/bin/view/Main/CompromisedHost
# Includes: openbl, bruteforceblocker and sidreporter
update compromised $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/compromised-ips.txt" \
	remove_comments \
	"EmergingThreats.net distribution of IPs that have beed compromised (at the time of writing includes openbl, bruteforceblocker and sidreporter)"

# Command & Control botnet servers by abuse.ch
update botnet $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-CC.rules" \
	pix_deny_rules_to_ipv4 \
	"EmergingThreats.net botnet IPs (at the time of writing includes all abuse.ch trackers)"

# This appears to be the SPAMHAUS DROP list
# disable - have direct feed
#update spamhaus $[12*60] 0 ipv4 net \
#	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DROP.rules" \
#	pix_deny_rules_to_ipv4

# Top 20 attackers by www.dshield.org
# disabled - have direct feed above
#update dshield $[12*60] 0 ipv4 net \
#	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DSHIELD.rules" \
#	pix_deny_rules_to_ipv4

# includes botnet, spamhaus and dshield
update emerging_block $[12*60] 0 ipv4 all \
	"http://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt" \
	remove_comments \
	"EmergingThreats.net default blacklist (at the time of writing includes spamhaus DROP and dshield)"


# -----------------------------------------------------------------------------
# Spamhaus
# http://www.spamhaus.org

# http://www.spamhaus.org/drop/
# These guys say that this list should be dropped at tier-1 ISPs globaly!
update spamhaus_drop $[12*60] 0 ipv4 net \
	"http://www.spamhaus.org/drop/drop.txt" \
	remove_comments_semi_colon \
	"Spamhaus.org DROP list (according to their site this list should be dropped at tier-1 ISPs globaly)"

# extended DROP (EDROP) list.
# Should be used together with their DROP list.
update spamhaus_edrop $[12*60] 0 ipv4 net \
	"http://www.spamhaus.org/drop/edrop.txt" \
	remove_comments_semi_colon \
	"Spamhaus.org EDROP (should be used with DROP)"


# -----------------------------------------------------------------------------
# blocklist.de
# http://www.blocklist.de/en/export.html

# All IP addresses that have attacked one of their customers/servers in the
# last 48 hours. Updated every 30 minutes.
# They also have lists of service specific attacks (ssh, apache, sip, etc).
update blocklist_de 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/all.txt" \
	remove_comments \
	"Blocklist.de IPs that have attacked their honeypots in the last 48 hours"


# -----------------------------------------------------------------------------
# Zeus trojan
# https://zeustracker.abuse.ch/blocklist.php
# by abuse.ch

# This blocklists only includes IPv4 addresses that are used by the ZeuS trojan.
update zeus_badips 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=badips" \
	remove_comments \
	"Abuse.ch Zeus Tracker includes IPv4 addresses that are used by the ZeuS trojan"

# This blocklist contains the same data as the ZeuS IP blocklist (BadIPs)
# but with the slight difference that it doesn't exclude hijacked websites
# (level 2) and free web hosting providers (level 3).
update zeus 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=ipblocklist" \
	remove_comments \
	"Abuse.ch Zeus Tracker default blocklist including hijacked sites and web hosting providers"

# -----------------------------------------------------------------------------
# Palevo worm
# https://palevotracker.abuse.ch/blocklists.php
# by abuse.ch

# includes IP addresses which are being used as botnet C&C for the Palevo crimeware
update palevo 30 0 ipv4 ip \
	"https://palevotracker.abuse.ch/blocklists.php?download=ipblocklist" \
	remove_comments \
	"Abuse.ch Palevo worm includes IPs which are being used as botnet C&C for the Palevo crimeware"

# -----------------------------------------------------------------------------
# Feodo trojan
# https://feodotracker.abuse.ch/blocklist/
# by abuse.ch

# Feodo (also known as Cridex or Bugat) is a Trojan used to commit ebanking fraud
# and steal sensitive information from the victims computer, such as credit card
# details or credentials.
update feodo 30 0 ipv4 ip \
	"https://feodotracker.abuse.ch/blocklist/?download=ipblocklist" \
	remove_comments \
	"Abuse.ch Feodo trojan includes IPs which are being used by Feodo (also known as Cridex or Bugat) which commits ebanking fraud"


# -----------------------------------------------------------------------------
# infiltrated.net
# http://www.infiltrated.net/blacklisted

update infiltrated $[12*60] 0 ipv4 ip \
	"http://www.infiltrated.net/blacklisted" \
	remove_comments \
	"infiltrated.net list (no more info available)"


# -----------------------------------------------------------------------------
# malc0de
# http://malc0de.com

# updated daily and populated with the last 30 days of malicious IP addresses.
update malc0de $[24*60] 0 ipv4 ip \
	"http://malc0de.com/bl/IP_Blacklist.txt" \
	remove_comments \
	"Malc0de.com malicious IPs of the last 30 days"

# -----------------------------------------------------------------------------
# Stop Forum Spam
# http://www.stopforumspam.com/downloads/

# to use this, create the ipset like this (in firehol.conf):
# >> ipset4 create stop_forum_spam hash:ip maxelem 500000
# -- normally, you don't need this set --
# -- use the hourly and the daily ones instead --
# IMPORTANT: THIS IS A BIG LIST - you will have to add maxelem to ipset to fit it
update stop_forum_spam $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/bannedips.zip" \
	unzip_and_split_csv \
	"StopForumSpam.com all IPs used by forum spammers"

# hourly update with IPs from the last 24 hours
update stop_forum_spam_1h 60 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_1.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 24 hours IPs used by forum spammers"

# daily update with IPs from the last 7 days
update stop_forum_spam_7d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_7.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 7 days IPs used by forum spammers"

# daily update with IPs from the last 30 days
update stop_forum_spam_30d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_30.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 30 days IPs used by forum spammers"


# daily update with IPs from the last 90 days
# you will have to add maxelem to ipset to fit it
update stop_forum_spam_90d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_90.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 90 days IPs used by forum spammers"


# daily update with IPs from the last 180 days
# you will have to add maxelem to ipset to fit it
update stop_forum_spam_180d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_180.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 180 days IPs used by forum spammers"


# daily update with IPs from the last 365 days
# you will have to add maxelem to ipset to fit it
update stop_forum_spam_365d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_365.zip" \
	unzip_and_extract \
	"StopForumSpam.com last 365 days IPs used by forum spammers"


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
update bogons $[24*60] 0 ipv4 net \
	"http://www.team-cymru.org/Services/Bogons/bogon-bn-agg.txt" \
	remove_comments \
	"Team-Cymru.org: private and reserved addresses defined by RFC 1918, RFC 5735, and RFC 6598 and netblocks that have not been allocated to a regional internet registry"


# http://www.team-cymru.org/bogon-reference.html
# Fullbogons are a larger set which also includes IP space that has been
# allocated to an RIR, but not assigned by that RIR to an actual ISP or other
# end-user.
update fullbogons $[24*60] 0 ipv4 net \
	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt" \
	remove_comments \
	"Team-Cymru.org: IP space that has been allocated to an RIR, but not assigned by that RIR to an actual ISP or other end-user"

#update fullbogons6 $[24*60-10] ipv6 net \
#	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt" \
#	remove_comments \
#	"Team-Cymru.org provided"


# -----------------------------------------------------------------------------
# Open Proxies from rosinstruments
# http://tools.rosinstrument.com/proxy/

update rosi_web_proxies $[2*60] $[7*24*60] ipv4 ip \
	"http://tools.rosinstrument.com/proxy/l100.xml" \
	parse_rss_rosinstrument \
	"rosinstrument.com open HTTP proxies distributed via its RSS feed and aggregated for the last 7 days"

update rosi_connect_proxies $[2*60] $[7*24*60] ipv4 ip \
	"http://tools.rosinstrument.com/proxy/plab100.xml" \
	parse_rss_rosinstrument \
	"rosinstrument.com open CONNECT proxies distributed via its RSS feed and aggregated for the last 7 days"


# -----------------------------------------------------------------------------
# Malware Domain List
# All IPs should be considered dangerous

update malwaredomainlist $[12*60] 0 ipv4 ip \
	"http://www.malwaredomainlist.com/hostslist/ip.txt" \
	remove_comments \
	"malwaredomainlist.com list of active ip addresses"


# -----------------------------------------------------------------------------
# Alien Vault
# Alienvault IP Reputation Database

# IMPORTANT: THIS IS A BIG LIST
# you will have to add maxelem to ipset to fit it
update alienvault_reputation $[12*60] 0 ipv4 ip \
	"https://reputation.alienvault.com/reputation.generic" \
	remove_comments \
	"AlienVault.com IP reputation database"


# -----------------------------------------------------------------------------
# Clean-MX
# Viruses

update clean_mx_viruses $[12*60] 0 ipv4 ip \
	"http://support.clean-mx.de/clean-mx/xmlviruses.php?sort=id%20desc&response=alive" \
	parse_xml_clean_mx \
	"Clean-MX.de IPs with viruses"


# -----------------------------------------------------------------------------
# CI Army
# http://ciarmy.com/

# The CI Army list is a subset of the CINS Active Threat Intelligence ruleset,
# and consists of IP addresses that meet two basic criteria:
# 1) The IP's recent Rogue Packet score factor is very poor, and
# 2) The InfoSec community has not yet identified the IP as malicious.
# We think this second factor is important: We don't want to waste peoples'
# time listing thousands of IPs that have already been placed on other reputation
# lists; our list is meant to supplement and enhance the InfoSec community's
# existing efforts by providing IPs that haven't been identified yet.
update ciarmy $[3*60] 0 ipv4 ip \
	"http://cinsscore.com/list/ci-badguys.txt" \
	remove_comments \
	"CIArmy.com IPs with poor Rogue Packet score that have not yet been identified as malicious by the InfoSec community"


# -----------------------------------------------------------------------------
# Bruteforce Blocker
# http://danger.rulez.sk/projects/bruteforceblocker/

update bruteforceblocker $[3*60] 0 ipv4 ip \
	"http://danger.rulez.sk/projects/bruteforceblocker/blist.php" \
	remove_comments \
	"danger.rulez.sk IPs detected by bruteforceblocker (fail2ban alternative for SSH on OpenBSD)"


# -----------------------------------------------------------------------------
# Snort ipfilter
# http://labs.snort.org/feeds/ip-filter.blf

update snort_ipfilter $[12*60] 0 ipv4 ip \
	"http://labs.snort.org/feeds/ip-filter.blf" \
	remove_comments \
	"labs.snort.org supplied IP blacklist"


# -----------------------------------------------------------------------------
# AutoShun.org
# http://www.autoshun.org/

csv_comma_first_column() { grep "^[0-9]" | cut -d ',' -f 1; }

update autoshun $[4*60] 0 ipv4 ip \
	"http://www.autoshun.org/files/shunlist.csv" \
	csv_comma_first_column \
	"AutoShun.org IPs identified as hostile by correlating logs from distributed snort installations running the autoshun plugin"


# -----------------------------------------------------------------------------
# iBlocklist
# https://www.iblocklist.com/lists.php
# http://bluetack.co.uk/forums/index.php?autocom=faq&CODE=02&qid=17

p2p_gz_proxy() { gzip -dc | grep "^Proxy" | cut -d ':' -f 2 | egrep "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | ipv4_range_to_cidr; }
p2p_gz() { gzip -dc | cut -d ':' -f 2 | egrep "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | ipv4_range_to_cidr; }

if [ ${CAN_CONVERT_RANGES_TO_CIDR} -eq 1 ]
then
	# open proxies and tor
	# we only keep the proxies IPs (tor IPs are not parsed)
	update ib_bluetack_proxies $[12*60] 0 ipv4 ip \
		"http://list.iblocklist.com/?list=xoebmbyexwuiogmbyprb&fileformat=p2p&archiveformat=gz" \
		p2p_gz_proxy \
		"iBlocklist.com free version of BlueTack.co.uk Open Proxies IPs (without TOR)"


	# This list is a compilation of known malicious SPYWARE and ADWARE IP Address ranges. 
	# It is compiled from various sources, including other available Spyware Blacklists,
	# HOSTS files, from research found at many of the top Anti-Spyware forums, logs of
	# Spyware victims and also from the Malware Research Section here at Bluetack. 
	update ib_bluetack_spyware $[12*60] 0 ipv4 net \
		"http://list.iblocklist.com/?list=llvtlsjyoyiczbkjsxpf&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk known malicious SPYWARE and ADWARE IP Address ranges"


	# List of people who have been reported for bad deeds in p2p.
	update ib_bluetack_badpeers $[12*60] 0 ipv4 ip \
		"http://list.iblocklist.com/?list=cwworuawihqvocglcoss&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk IPs that have been reported for bad deeds in p2p"


	# Contains hijacked IP-Blocks and known IP-Blocks that are used to deliver Spam. 
	# This list is a combination of lists with hijacked IP-Blocks 
	# Hijacked IP space are IP blocks that are being used without permission by
	# organizations that have no relation to original organization (or its legal
	# successor) that received the IP block. In essence it's stealing of somebody
	# else's IP resources
	update ib_bluetack_hijacked $[12*60] 0 ipv4 net \
		"http://list.iblocklist.com/?list=usrcshglbiilevmyfhse&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk hijacked IP-Blocks Hijacked IP space are IP blocks that are being used without permission"


	# IP addresses related to current web server hack and exploit attempts that have been
	# logged by us or can be found in and cross referenced with other related IP databases.
	# Malicious and other non search engine bots will also be listed here, along with anything
	# we find that can have a negative impact on a website or webserver such as proxies being
	# used for negative SEO hijacks, unauthorised site mirroring, harvesting, scraping,
	# snooping and data mining / spy bot / security & copyright enforcement companies that
	# target and continuosly scan webservers.
	update ib_bluetack_webexploit $[12*60] 0 ipv4 ip \
		"http://list.iblocklist.com/?list=ghlzqtqxnzctvvajwwag&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk web server hack and exploit attempts"


	# Companies or organizations who are clearly involved with trying to stop filesharing
	# (e.g. Baytsp, MediaDefender, Mediasentry a.o.). 
	# Companies which anti-p2p activity has been seen from. 
	# Companies that produce or have a strong financial interest in copyrighted material
	# (e.g. music, movie, software industries a.o.). 
	# Government ranges or companies that have a strong financial interest in doing work
	# for governments. 
	# Legal industry ranges. 
	# IPs or ranges of ISPs from which anti-p2p activity has been observed. Basically this
	# list will block all kinds of internet connections that most people would rather not
	# have during their internet travels. 
	# PLEASE NOTE: The Level1 list is recommended for general P2P users, but it all comes
	# down to your personal choice. 
	# IMPORTANT: THIS IS A BIG LIST
	update ib_bluetack_level1 $[12*60] 0 ipv4 net \
		"http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk Level 1 (for use in p2p)"


	# General corporate ranges. 
	# Ranges used by labs or researchers. 
	# Proxies. 
	update ib_bluetack_level2 $[12*60] 0 ipv4 net \
		"http://list.iblocklist.com/?list=gyisgnzbhppbvsphucsw&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk Level 2 (for use in p2p)"


	# Many portal-type websites. 
	# ISP ranges that may be dodgy for some reason. 
	# Ranges that belong to an individual, but which have not been determined to be used by a particular company. 
	# Ranges for things that are unusual in some way. The L3 list is aka the paranoid list.
	update ib_bluetack_level3 $[12*60] 0 ipv4 net \
		"http://list.iblocklist.com/?list=uwnukjqktoggdknzrhgh&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"iBlocklist.com free version of BlueTack.co.uk Level 3 (for use in p2p)"

fi


# to add
# http://www.nothink.org/blacklist/blacklist_ssh_week.txt
# http://www.nothink.org/blacklist/blacklist_malware_irc.txt
# http://www.nothink.org/blacklist/blacklist_malware_http.txt
# http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1

