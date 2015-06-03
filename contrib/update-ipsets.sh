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
#    git to automatically push changes without human action).
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

base="/etc/firehol/ipsets"

# single line flock, from man flock
[ "${UPDATE_IPSETS_LOCKER}" != "${0}" ] && exec env UPDATE_IPSETS_LOCKER="$0" flock -en "${base}/.lock" "${0}" "${@}" || :

PATH="${PATH}:/sbin:/usr/sbin"

LC_ALL=C
umask 077

if [ ! "$UID" = "0" ]
then
	echo >&2 "Please run me as root."
	exit 1
fi
renice 10 $$ >/dev/null 2>/dev/null

require_cmd() {
	local cmd= block=1
	if [ "a${1}" = "a-n" ]
	then
		block=0
		shift
	fi

	unalias ${1} >/dev/null 2>&1
	cmd=`which ${1} 2>/dev/null | head -n 1`
	if [ $? -gt 0 -o ! -x "${cmd}" ]
	then
		if [ ${block} -eq 1 ]
		then
			echo >&2 "ERROR: Command '${1}' not found in the system path."
			exit 1
		fi
		return 1
	fi

	eval "${1^^}_CMD=${cmd}"
	return 0
}

require_cmd curl
require_cmd unzip
require_cmd funzip
require_cmd gzip
require_cmd sed
require_cmd grep
require_cmd sort
require_cmd uniq
require_cmd tail
require_cmd mkdir
require_cmd egrep
require_cmd mkdir
require_cmd awk
require_cmd touch
require_cmd ipset
require_cmd dirname

program_pwd="${PWD}"
program_dir="`dirname ${0}`"
CAN_CONVERT_RANGES_TO_CIDR=0
if [ -x "${program_dir}/ipv4_range_to_cidr.awk" ]
then
	CAN_CONVERT_RANGES_TO_CIDR=1
fi

ipv4_range_to_cidr() {
	cd "${program_pwd}"
	awk -f "${program_dir}/ipv4_range_to_cidr.awk"
	cd "${OLDPWD}"
}

GIT_COMPARE=0
IGNORE_LASTCHECKED=0
PUSH_TO_GIT=0
SILENT=0
while [ ! -z "${1}" ]
do
	case "${1}" in
		silen|-s) SILENT=1;;
		git|-g) PUSH_TO_GIT=1;;
		recheck|-i) IGNORE_LASTCHECKED=1;;
		compare|-c) GIT_COMPARE=1;;
		*) echo >&2 "Unknown parameter '${1}'".; exit 1 ;;
	esac
	shift
done

# create the directory to save the sets
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

# convert a number of minutes to a human readable text
mins_to_text() {
	local days= hours= mins="${1}"

	if [ -z "${mins}" -o $[mins + 0] -eq 0 ]
		then
		echo "none"
		return 0
	fi

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

	return 0
}

syslog() {
	echo >&2 "${@}"
	logger -p daemon.info -t "update-ipsets.sh[$$]" "${@}"
}

# Generate the README.md file and push the repo to the remote server
declare -A UPDATED_DIRS=()
declare -A UPDATED_SETS=()

check_git_committed() {
	git ls-files "${1}" --error-unmatch >/dev/null 2>&1
	if [ $? -ne 0 ]
		then
		git add "${1}"
	fi
}

commit_to_git() {
	if [ -d .git -a ! -z "${!UPDATED_SETS[*]}" ]
	then
		[ ${GIT_COMPARE} -eq 1 ] && compare_all_ipsets

		local d=
		for d in "${!UPDATED_DIRS[@]}"
		do
			[ ! -f ${d}/README-EDIT.md ] && touch ${d}/README-EDIT.md
			(
				cat ${d}/README-EDIT.md
				echo
				echo "The following list was automatically generated on `date -u`."
				echo
				echo "The update frequency is the maximum allowed by internal configuration. A list will never be downloaded sooner than the update frequency stated. A list may also not be downloaded, after this frequency expired, if it has not been modified on the server (as reported by HTTP \`IF_MODIFIED_SINCE\` method)."
				echo
				echo "name|info|type|entries|update|"
				echo ":--:|:--:|:--:|:-----:|:----:|"
				cat ${d}/*.setinfo
			) >${d}/README.md

			UPDATED_SETS[${d}/README.md]="${d}/README.md"
			check_git_committed "${d}/README.md"
		done

		echo >>README.md
		echo "# Comparison of ipsets" >>README.md
		echo >>README.md
		echo "Below we compare each ipset against all other." >>README.md
		echo >>README.md

		for d in `find . -name \*.comparison.md | sort`
		do
			echo >>README.md
			cat "${d}" >>README.md
			rm "${d}"
		done

		echo >&2 
		syslog "Committing ${UPDATED_SETS[@]} to git repository"
		git commit "${UPDATED_SETS[@]}" -m "`date -u` update"

		if [ ${PUSH_TO_GIT} -ne 0 ]
		then
			echo >&2 
			syslog "Pushing git commits to remote server"
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

# touch a file to a relative date in the past
touch_in_the_past() {
	local mins_ago="${1}" file="${2}"

	local now=$(date +%s)
	local date=$(date -d @$[now - (mins_ago * 60)] +"%y%m%d%H%M.%S")
	touch -t "${date}" "${file}"
}
touch_in_the_past $[7 * 24 * 60] ".warn_if_last_downloaded_before_this"

# get all the active ipsets in the system
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


# -----------------------------------------------------------------------------

# check if a file is too old
check_file_too_old() {
	local ipset="${1}" file="${2}"

	if [ -f "${file}" -a ".warn_if_last_downloaded_before_this" -nt "${file}" ]
	then
		syslog "${ipset}: DATA ARE TOO OLD!"
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
			#test ${SILENT} -ne 1 && echo >&2 "${ipset}: merging history file '${x}'"
			cat "${x}"
		else
			rm "${x}"
		fi
	done | sort -u >"${file}"
	rm "history/${ipset}/.reference"

	return 0
}

# fetch a url
# the output file has the last modified timestamp
# of the server
# on the next run, the file is downloaded only
# if it has changed on the server
geturl() {
	local file="${1}" reference="${2}" url="${3}" ret= http_code=

	# copy the timestamp of the reference
	# to our file
	touch -r "${reference}" "${file}"

	http_code=$(curl --connect-timeout 10 --max-time 300 --retry 0 --fail --compressed \
		--user-agent "FireHOL-Update-Ipsets/3.0" \
		--referer "https://github.com/ktsaou/firehol/blob/master/contrib/update-ipsets.sh" \
		-z "${reference}" -o "${file}" -s -L -R -w "%{http_code}" \
		"${url}")

	ret=$?
	
	printf >&2 "HTTP/${http_code} "

	case "${ret}" in
		0)	if [ "${http_code}" = "304" -a ! "${file}" -nt "${reference}" ]
			then
				echo >&2 "Not Modified"
				return 99
			fi
			echo >&2 "OK"
			;;

		1)	echo >&2 "Unsupported Protocol" ;;
		2)	echo >&2 "Failed to initialize" ;;
		3)	echo >&2 "Malformed URL" ;;
		5)	echo >&2 "Can't resolve proxy" ;;
		6)	echo >&2 "Can't resolve host" ;;
		7)	echo >&2 "Failed to connect" ;;
		18)	echo >&2 "Partial Transfer" ;;
		22)	echo >&2 "HTTP Error" ;;
		23)	echo >&2 "Cannot write local file" ;;
		26)	echo >&2 "Read Error" ;;
		28)	echo >&2 "Timeout" ;;
		35)	echo >&2 "SSL Error" ;;
		47)	echo >&2 "Too many redirects" ;;
		52)	echo >&2 "Server did not reply anything" ;;
		55)	echo >&2 "Failed sending network data" ;;
		56)	echo >&2 "Failure in receiving network data" ;;
		61)	echo >&2 "Unrecognized transfer encoding" ;;
		*) echo >&2 "Error ${ret} returned by curl" ;;
	esac

	return ${ret}
}

# download a file if it has not been downloaded in the last $mins
DOWNLOAD_OK=0
DOWNLOAD_FAILED=1
DOWNLOAD_NOT_UPDATED=2
download_url() {
	local 	ipset="${1}" mins="${2}" url="${3}" \
		install="${1}" \
		tmp= now= date= check=

	tmp=`mktemp "${install}.tmp-XXXXXXXXXX"` || return ${DOWNLOAD_FAILED}

	# touch a file $mins + 2 ago
	# we add 2 to let the server update the file
	touch_in_the_past "$[mins + 2]" "${tmp}"

	check="${install}.source"
	[ ${IGNORE_LASTCHECKED} -eq 0 -a -f ".${install}.lastchecked" ] && check=".${install}.lastchecked"

	# check if we have to download again
	if [ "${check}" -nt "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: should not be downloaded so soon."
		return ${DOWNLOAD_NOT_UPDATED}
	fi

	# download it
	test ${SILENT} -ne 1 && printf >&2 "${ipset}: downlading from '${url}'... "
	geturl "${tmp}" "${install}.source" "${url}"
	case $? in
		0)	;;
		99)
			echo >&2 "${ipset}: file on server has not been updated yet"
			rm "${tmp}"
			touch_in_the_past $[mins / 2] ".${install}.lastchecked"
			return ${DOWNLOAD_NOT_UPDATED}
			;;

		*)
			syslog "${ipset}: cannot download '${url}'."
			rm "${tmp}"
			return ${DOWNLOAD_FAILED}
			;;
	esac

	# we downloaded something - remove the lastchecked file
	[ -f ".${install}.lastchecked" ] && rm ".${install}.lastchecked"

	# check if the downloaded file is empty
	if [ ! -s "${tmp}" ]
	then
		# it is empty
		rm "${tmp}"
		syslog "${ipset}: empty file downloaded from url '${url}'."
		return ${DOWNLOAD_FAILED}
	fi

	# check if the downloaded file is the same with the last one
	diff -q "${install}.source" "${tmp}" >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		# they are the same
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: downloaded file is the same with the previous one."

		# copy the timestamp of the downloaded to our file
		touch -r "${tmp}" "${install}.source"
		rm "${tmp}"
		return ${DOWNLOAD_NOT_UPDATED}
	fi

	# move it to its place
	test ${SILENT} -ne 1 && echo >&2 "${ipset}: saving downloaded file to ${install}.source"
	mv "${tmp}" "${install}.source" || return ${DOWNLOAD_FAILED}

	return ${DOWNLOAD_OK}
}

ips_in_set() {
	# the ipset/netset has to be
	# aggregated properly

	if [ -x "${base}/iprange" ]
		then
		# our special version of iprange
		"${base}/iprange" -C
	else
		append_slash32 |\
			cut -d '/' -f 2 |\
			(
				local sum=0;
				while read i
				do
					sum=$[sum + (1 << (32 - i))]
				done
				echo $sum
			)
	fi
}

# -----------------------------------------------------------------------------
# ipsets comparisons

declare -A IPSET_INFO=()
declare -A IPSET_SOURCE=()
declare -A IPSET_URL=()
declare -A IPSET_FILE=()
declare -A IPSET_ENTRIES=()
declare -A IPSET_IPS=()
declare -A IPSET_OVERLAPS=()
cache_save() {
	#echo >&2 "Saving cache"
	declare -p IPSET_SOURCE IPSET_URL IPSET_INFO IPSET_FILE IPSET_ENTRIES IPSET_IPS IPSET_OVERLAPS >"${base}/.cache"
}
if [ -f "${base}/.cache" ]
	then
	echo >&2 "Loading cache"
	source "${base}/.cache"
	cache_save
fi
cache_remove_ipset() {
	local ipset="${1}"

	echo >&2 "${ipset}: removing from cache"

	cache_clean_ipset "${ipset}"

	unset IPSET_INFO[${ipset}]
	unset IPSET_SOURCE[${ipset}]
	unset IPSET_URL[${ipset}]
	unset IPSET_FILE[${ipset}]
	unset IPSET_ENTRIES[${ipset}]
	unset IPSET_IPS[${ipset}]

	cache_save
}
cache_clean_ipset() {
	local ipset="${1}"

	# echo >&2 "${ipset}: Cleaning cache"
	unset IPSET_ENTRIES[${ipset}]
	unset IPSET_IPS[${ipset}]
	local x=
	for x in "${!IPSET_FILE[@]}"
	do
		unset IPSET_OVERLAPS[,${ipset},${x},]
		unset IPSET_OVERLAPS[,${x},${ipset},]
	done
	cache_save
}
cache_update_ipset() {
	local ipset="${1}"
	[ -z "${IPSET_ENTRIES[${ipset}]}" ] && IPSET_ENTRIES[${ipset}]=`cat "${IPSET_FILE[${ipset}]}" | remove_comments | wc -l`
	[ -z "${IPSET_IPS[${ipset}]}"     ] && IPSET_IPS[${ipset}]=`cat "${IPSET_FILE[${ipset}]}" | remove_comments | ips_in_set`
	return 0
}

print_last_digit_decimal() {
	local x="${1}" len= pl=
	len="${#x}"
	while [ ${len} -lt 2 ]
	do
		x="0${x}"
		len="${#x}"
	done
	pl="$[len - 1]"
	echo "${x:0:${pl}}.${x:${pl}:${len}}"
}

compare_ipset() {
	local ipset="${1}" file= readme= info= entries= ips=
	shift

	file="${IPSET_FILE[${ipset}]}"
	info="${IPSET_INFO[${ipset}]}"
	readme="${file/.ipset/}"
	readme="${readme/.netset/}"
	readme="${readme}.comparison.md"

	[[ "${file}" =~ ^geolite2.* ]] && return 1

	if [ -z "${file}" -o ! -f "${file}" ]
		then
		cache_remove_ipset "${ipset}"
		return 1
	fi

	cache_update_ipset "${ipset}"
	entries="${IPSET_ENTRIES[${ipset}]}"
	ips="${IPSET_IPS[${ipset}]}"

	if [ -z "${entries}" -o -z "${ips}" -o ! -f "${IPSET_FILE[${ipset}]}" -o ! -f "${IPSET_SOURCE[${ipset}]}" ]
		then
		cache_remove_ipset "${ipset}"
		return 1
	fi

	printf >&2 "%31.31s: " "${ipset}"

	cat >${readme} <<EOFMD
## ${ipset}

${info}

Source is downloaded from [this link](${IPSET_URL[${ipset}]}).

The last time downloaded was found to be dated: `date -r "${IPSET_SOURCE[${ipset}]}" -u`.

The ipset \`${ipset}\` has **${entries}** entries, **${ips}** unique IPs.

The following table shows the overlaps of \`${ipset}\` with all the other ipsets supported. Only the ipsets that have at least 1 IP overlap are shown. if an ipset is not shown here, it does not have any overlap with \`${ipset}\`.

- \` them % \` is the percentage of IPs of each row ipset (them), found in \`${ipset}\`.
- \` this % \` is the percentage **of this ipset (\`${ipset}\`)**, found in the IPs of each other ipset.

ipset|entries|unique IPs|IPs on both| them % | this % |
:---:|:-----:|:--------:|:---------:|:------:|:------:|
EOFMD

	local oipset=
	for oipset in "${!IPSET_FILE[@]}"
	do
		[ "${ipset}" = "${oipset}" ] && continue

		local ofile="${IPSET_FILE[${oipset}]}"
		if [ ! -f "${ofile}" ]
			then
			cache_remove_ipset "${oipset}"
			continue
		fi

		[[ "${ofile}" =~ ^geolite2.* ]] && continue

		cache_update_ipset "${oipset}"
		local oentries="${IPSET_ENTRIES[${oipset}]}"
		local oips="${IPSET_IPS[${oipset}]}"

		if [ -z "${oentries}" -o -z "${oips}" -o ! -f "${IPSET_FILE[${oipset}]}" -o ! -f "${IPSET_SOURCE[${oipset}]}" ]
			then
			printf >&2 "%s" "-"
			continue
		fi

		# echo >&2 "	Updating overlaps for ${ipset} compared to ${oipset}..."

		if [ -z "${IPSET_OVERLAPS[,${ipset},${oipset},]}${IPSET_OVERLAPS[,${oipset},${ipset},]}" ]
			then
			printf >&2 "+"
			local mips=`cat "${file}" "${ofile}" | remove_comments | append_slash32 | sort -u | aggregate4 | ips_in_set`
			IPSET_OVERLAPS[,${ipset},${oipset},]=$[(ips + oips) - mips]
			#echo "IPSET_OVERLAPS[,${ipset},${oipset},]=${IPSET_OVERLAPS[,${ipset},${oipset},]}" >>"${base}/.cache"
		else
			printf >&2 "."
		fi
		local overlap="${IPSET_OVERLAPS[,${ipset},${oipset},]}${IPSET_OVERLAPS[,${oipset},${ipset},]}"

		[ ${overlap} -gt 0 ] && echo "${overlap}|[${oipset}](#${oipset})|${oentries}|${oips}|${overlap}|$(print_last_digit_decimal $[overlap * 1000 / oips])%|$(print_last_digit_decimal $[overlap * 1000 / ips])%|" >>${readme}.tmp
	done
	cat "${readme}.tmp" | sort -n -r | cut -d '|' -f 2- >>${readme}
	rm "${readme}.tmp"

	echo >&2
	cache_save
}

compare_all_ipsets() {
	local x=
	echo >&2
	echo >&2 "Comparing ipsets..."
	for x in "${!IPSET_FILE[@]}"
	do
		compare_ipset "${x}" "${!IPSET_FILE[@]}"
	done
}

# -----------------------------------------------------------------------------

finalize() {
	local ipset="${1}" tmp="${2}" setinfo="${3}" src="${4}" dst="${5}" mins="${6}" history_mins="${7}" ipv="${8}" type="${9}" hash="${10}" url="${11}" info="${12}"

	# remove the comments from the existing file
	if [ -f "${dst}" ]
	then
		cat "${dst}" | grep -v "^#" > "${tmp}.old"
	else
		echo "# EMPTY SET" >"${tmp}.old"
	fi

	# compare the new and the old
	diff -q "${tmp}.old" "${tmp}" >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		# they are the same
		rm "${tmp}" "${tmp}.old"
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: processed set is the same with the previous one."

		# keep the old set, but make it think it was from this source
		touch -r "${src}" "${dst}"

		check_file_too_old "${ipset}" "${dst}"
		return 0
	fi
	rm "${tmp}.old"

	# calculate how many entries/IPs are in it
	local ipset_opts=
	local entries=$(wc -l "${tmp}" | cut -d ' ' -f 1)
	local size=$[ ( ( (entries * 130 / 100) / 65536 ) + 1 ) * 65536 ]

	# if the ipset is not already in memory
	if [ -z "${sets[$ipset]}" ]
	then
		# if the required size is above 65536
		if [ ${size} -ne 65536 ]
		then
			echo >&2 "${ipset}: processed file gave ${entries} results - sizing to ${size} entries"
			echo >&2 "${ipset}: remember to append this to your ipset line (in firehol.conf): maxelem ${size}"
			ipset_opts="maxelem ${size}"
		fi

		echo >&2 "${ipset}: creating ipset with ${entries} entries"
		ipset --create ${ipset} "${hash}hash" ${ipset_opts} || return 1
	fi

	# call firehol to update the ipset in memory
	firehol ipset_update_from_file ${ipset} ${ipv} ${type} "${tmp}"
	if [ $? -ne 0 ]
	then
		if [ -d errors ]
		then
			mv "${tmp}" "errors/${ipset}.${hash}set"
			syslog "${ipset}: failed to update ipset (error file left for you as 'errors/${ipset}.${hash}set')."
		else
			rm "${tmp}"
			syslog "${ipset}: failed to update ipset."
		fi
		check_file_too_old "${ipset}" "${dst}"
		return 1
	fi

	local ips= quantity=

	# find how many IPs are there
	ips=${entries}
	quantity="${ips} unique IPs"

	if [ "${hash}" = "net" ]
	then
		entries=${ips}
		ips=`cat "${tmp}" | ips_in_set`
		quantity="${entries} subnets, ${ips} unique IPs"
	fi

	# generate the final file
	# we do this on another tmp file
	cat >"${tmp}.wh" <<EOFHEADER
#
# ${ipset}
#
# ${ipv} hash:${hash} ipset
#
`echo "${info}" | fold -w 60 -s | sed "s/^/# /g"`
#
# Source URL: ${url}
#
# Source File Date: `date -r "${src}" -u`
# This File Date  : `date -u`
# Update Frequency: `mins_to_text ${mins}`
# Aggregation     : `mins_to_text ${history_mins}`
# Entries         : ${quantity}
#
# Generated by FireHOL's update-ipsets.sh
#
EOFHEADER

	cat "${tmp}" >>"${tmp}.wh"
	rm "${tmp}"
	touch -r "${src}" "${tmp}.wh"
	mv "${tmp}.wh" "${dst}" || return 1

	cache_clean_ipset "${ipset}"
	IPSET_FILE[${ipset}]="${dst}"
	IPSET_INFO[${ipset}]="${info}"
	IPSET_ENTRIES[${ipset}]="${entries}"
	IPSET_IPS[${ipset}]="${ips}"
	IPSET_URL[${ipset}]="${url}"
	IPSET_SOURCE[${ipset}]="${src}"

	UPDATED_SETS[${ipset}]="${dst}"
	local dir="`dirname "${dst}"`"
	UPDATED_DIRS[${dir}]="${dir}"

	if [ -d .git ]
	then
		echo >"${setinfo}" "[${ipset}](#${ipset})|${info}|${ipv} hash:${hash}|${quantity}|updated every `mins_to_text ${mins}` from [this link](${url})"
		check_git_committed "${dst}"
	fi

	return 0
}

update() {
	local 	ipset="${1}" mins="${2}" history_mins="${3}" ipv="${4}" type="${5}" url="${6}" processor="${7-cat}" info="${8}"
		install="${1}" tmp= error=0 now= date= pre_filter="cat" post_filter="cat" post_filter2="cat" filter="cat"
	shift 8

	case "${ipv}" in
		ipv4)
			post_filter2="filter_invalid4"
			case "${type}" in
				ip|ips)		# output is single ipv4 IPs without /
						hash="ip"
						type="ip"
						pre_filter="cat"
						filter="filter_ip4"
						post_filter="cat"
						;;

				net|nets)	# output is full CIDRs without any single IPs (/32)
						hash="net"
						type="net"
						pre_filter="filter_all4"
						filter="aggregate4"
						post_filter="filter_net4"
						;;

				both|all)	# output is full CIDRs with single IPs in CIDR notation (with /32)
						hash="net"
						type=""
						pre_filter="filter_all4"
						filter="aggregate4"
						post_filter="cat"
						;;

				split)	;;

				*)		echo >&2 "${ipset}: unknown type '${type}'."
						return 1
						;;
			esac
			;;
		ipv6)
			case "${type}" in
				ip|ips)	
						hash="ip"
						type="ip"
						pre_filter="remove_slash128"
						filter="filter_ip6"
						;;

				net|nets)
						hash="net"
						type="net"
						filter="filter_net6"
						;;

				both|all)
						hash="net"
						type=""
						filter="filter_all6"
						;;

				split)	;;

				*)		echo >&2 "${ipset}: unknown type '${type}'."
						return 1
						;;
			esac
			;;

		*)	syslog "${ipset}: unknown IP version '${ipv}'."
			return 1
			;;
	esac

	if [ ! -f "${install}.source" ]
	then
		[ -d .git ] && echo >"${install}.setinfo" "${ipset}|${info}|${ipv} hash:${hash}|disabled|updated every `mins_to_text ${mins}` from [this link](${url})"
		echo >&2 "${ipset}: is disabled, to enable it run: touch -t 0001010000 '${base}/${install}.source'"
		return 1
	fi

	# download it
	download_url "${ipset}" "${mins}" "${url}"
	if [ $? -eq ${DOWNLOAD_FAILED} -o $? -eq ${DOWNLOAD_NOT_UPDATED} ]
		then
		if [ ! -s "${install}.source" ]; then return 1
		elif [ -f "${install}.${hash}set" ]
		then
			check_file_too_old "${ipset}" "${install}.${hash}set"
			return 1
		fi
	fi

	# support for older systems where hash:net cannot get hash:ip entries
	# if the .split file exists, create 2 ipsets, one for IPs and one for subnets
	if [ "${type}" = "split" -o \( -z "${type}" -a -f "${install}.split" \) ]
	then
		echo >&2 "${ipset}: spliting IPs and networks..."
		test -f "${install}_ip.source" && rm "${install}_ip.source"
		test -f "${install}_net.source" && rm "${install}_net.source"
		ln -s "${install}.source" "${install}_ip.source"
		ln -s "${install}.source" "${install}_net.source"
		update "${ipset}_ip" "${mins}" "${history_mins}" "${ipv}" ip  "${url}" "${processor}"
		update "${ipset}_net" "${mins}" "${history_mins}" "${ipv}" net "${url}" "${processor}"
		return $?
	fi

	# check if the source file has been updated
	if [ ! "${install}.source" -nt "${install}.${hash}set" ]
	then
		echo >&2 "${ipset}: not updated - no reason to process it again."
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 0
	fi

	# convert it
	test ${SILENT} -ne 1 && echo >&2 "${ipset}: converting with processor '${processor}'"
	tmp=`mktemp "${install}.tmp-XXXXXXXXXX"` || return 1
	${processor} <"${install}.source" |\
		trim |\
		${pre_filter} |\
		${filter} |\
		${post_filter} |\
		${post_filter2} |\
		sort -u >"${tmp}"

	if [ $? -ne 0 ]
	then
		syslog "${ipset}: failed to convert file."
		rm "${tmp}"
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 1
	fi

	if [ ! -s "${tmp}" ]
	then
		syslog "${ipset}: processed file gave no results."
		rm "${tmp}"

		# keep the old set, but make it think it was from this source
		touch -r "${install}.source" "${install}.${hash}set"
		check_file_too_old "${ipset}" "${install}.${hash}set"
		return 2
	fi

	if [ $[history_mins + 0] -gt 0 ]
	then
		history_manager "${ipset}" "${history_mins}" "${tmp}"
	fi

	finalize "${ipset}" "${tmp}" "${install}.setinfo" "${install}.source" "${install}.${hash}set" "${mins}" "${history_mins}" "${ipv}" "${type}" "${hash}" "${url}" "${info}"
	return $?
}

# FIXME
# Cannot rename ipsets in subdirectories
rename_ipset() {
	local old="${1}" new="${2}"

	local x=
	for x in ipset netset
	do
		if [ -f "${old}.${x}" -a ! -f "${new}.${x}" ]
			then
			if [ -d .git ]
				then
				echo >&2 "GIT Renaming ${old}.${x} to ${new}.${x}..."
				git mv "${old}.${x}" "${new}.${x}" || exit 1
				git commit "${old}.${x}" "${new}.${x}" -m 'renamed from ${old}.${x} to ${new}.${x}'
			fi

			if [ -f "${old}.${x}" -a ! -f "${new}.${x}" ]
				then
				echo >&2 "Renaming ${old}.${x} to ${new}.${x}..."
				mv "${old}.${x}" "${new}.${x}" || exit 1
			fi

			# keep a link for the firewall
			echo >&2 "Linking ${new}.${x} to ${old}.${x}..."
			ln -s "${new}.${x}" "${old}.${x}" || exit 1

			# now delete it, in order to be re-created this run
			rm "${new}.${x}"

			# FIXME:
			# the ipset in memory is wrong and will not be updated.
			# Probably the solution is to create an list:set ipset
			# which will link the old name with the new
		fi
	done

	for x in source split setinfo
	do
		if [ -f "${old}.${x}" -a ! -f "${new}.${x}" ]
			then
			mv "${old}.${x}" "${new}.${x}" || exit 1
		fi
	done

	if [ -d "history/${old}" -a ! -d "history/${new}" ]
		then
		echo "Renaming history/${old} history/${new}"
		mv "history/${old}" "history/${new}"
	fi

	[ -f ".${old}.lastchecked" -a ! -f ".${new}.lastchecked" ] && mv ".${old}.lastchecked" ".${new}.lastchecked"

	return 0
}

# rename the emerging threats ipsets to their right names
rename_ipset tor et_tor
rename_ipset compromised et_compromised
rename_ipset botnet et_botcc
rename_ipset et_botnet et_botcc
rename_ipset emerging_block et_block
rename_ipset rosi_web_proxies ri_web_proxies
rename_ipset rosi_connect_proxies ri_connect_proxies
rename_ipset danmetor dm_tor
rename_ipset autoshun shunlist
rename_ipset tor_servers bm_tor
rename_ipset stop_forum_spam stopforumspam_ever
rename_ipset stop_forum_spam_1h stopforumspam_1d
rename_ipset stop_forum_spam_7d stopforumspam_7d
rename_ipset stop_forum_spam_30d stopforumspam_30d
rename_ipset stop_forum_spam_90d stopforumspam_90d
rename_ipset stop_forum_spam_180d stopforumspam_180d
rename_ipset stop_forum_spam_365d stopforumspam_365d
rename_ipset clean_mx_viruses cleanmx_viruses

# -----------------------------------------------------------------------------
# INTERNAL FILTERS

# the output of aggregate4 always has a /, even if it is /32
aggregate4_warning=0
aggregate4() {
	local cmd=

	if [ -x "${base}/iprange" ]
		then
		"${base}/iprange" -J
		return $?
	fi

	cmd="`which iprange 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		append_slash32 | ${cmd} -J | append_slash32
		return $?
	fi

	cmd="`which aggregate-flim 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		append_slash32 | ${cmd} | append_slash32
		return $?
	fi

	cmd="`which aggregate 2>/dev/null`"
	if [ ! -z "${cmd}" ]
	then
		[ ${aggregate4_warning} -eq 0 ] && echo >&2 "The command aggregate installed is really slow, please install aggregate-flim or iprange (http://www.cs.colostate.edu/~somlo/iprange.c)."
		aggregate4_warning=1

		append_slash32 | ${cmd} -t | append_slash32
		return $?
	fi

	[ ${aggregate4_warning} -eq 0 ] && echo >&2 "Warning: Cannot aggregate ip-ranges. Please install 'aggregate'. Working wihout aggregate (http://www.cs.colostate.edu/~somlo/iprange.c)."
	aggregate4_warning=1

	append_slash32
}

# match a single IPv4 IP
# zero prefix is not permitted 0 - 255, not 000, 010, etc
IP4_MATCH="(((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9]))"

# match a single IPv4 net mask (/32 allowed, /0 not allowed)
MK4_MATCH="(3[12]|[12][0-9]|[1-9])"

# strict checking of IPv4 IPs - all subnets excluded
# we remove /32 before matching
filter_ip4()  { remove_slash32 | egrep "^${IP4_MATCH}$"; }

# strict checking of IPv4 CIDRs, except /32
# this is to support older ipsets that do not accept /32 in hash:net ipsets
filter_net4() { remove_slash32 | egrep "^${IP4_MATCH}/${MK4_MATCH}$"; }

# strict checking of IPv4 IPs or CIDRs
# hosts may or may not have /32
filter_all4() { egrep "^${IP4_MATCH}(/${MK4_MATCH})?$"; }

filter_ip6()  { remove_slash128 | egrep "^([0-9a-fA-F:]+)$"; }
filter_net6() { remove_slash128 | egrep "^([0-9a-fA-F:]+/[0-9]+)$"; }
filter_all6() { egrep "^([0-9a-fA-F:]+(/[0-9]+)?)$"; }

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
	egrep -v "^(0\.0\.0\.0|.*/0)$"
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

parse_rss_proxy() {
	while read_xml_dom
	do
		if [ "${XML_ENTITY}" = "prx:ip" ]
		then
			if [[ "${XML_CONTENT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
			then
				echo "${XML_CONTENT}"
			fi
		fi
	done
}

parse_php_rss() {
	while read_xml_dom
	do
		if [ "${XML_ENTITY}" = "title" ]
		then
			if [[ "${XML_CONTENT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+.*$ ]]
			then
				echo "${XML_CONTENT/|*/}"
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

trim() {
	sed -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g" |\
		grep -v "^$"
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
	remove_comments |\
		grep "^[1-9]" |\
		cut -d ' ' -f 1,3 |\
		while read net mask
		do
			echo "${net}/${mask}"
		done
}

unzip_and_split_csv() {
	funzip | tr ",\r" "\n\n"
}

unzip_and_extract() {
	funzip
}

p2p_gz_proxy() {
	gzip -dc |\
		grep "^Proxy" |\
		cut -d ':' -f 2 |\
		egrep "^${IP4_MATCH}-${IP4_MATCH}$" |\
		ipv4_range_to_cidr
}

p2p_gz() {
	gzip -dc |\
		cut -d ':' -f 2 |\
		egrep "^${IP4_MATCH}-${IP4_MATCH}$" |\
		ipv4_range_to_cidr
}

csv_comma_first_column() {
	grep "^[0-9]" |\
		cut -d ',' -f 1
}

gz_second_word() {
	gzip -dc |\
		tr '\r' '\n' |\
		cut -d ' ' -f 2
}

gz_proxyrss() {
	gzip -dc |\
		remove_comments |\
		cut -d ':' -f 1
}

parse_maxmind_proxy_fraud() {
	grep "a href=\"proxy/" |\
		cut -d '>' -f 2 |\
		cut -d '<' -f 1
}

geolite2_country() {
	local ipset="geolite2_country" type="net" hash="net" ipv="ipv4" \
		mins=$[24 * 60 * 7] history_mins=0 \
		url="http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country-CSV.zip" \
		info="[MaxMind GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/)"

	if [ ! -f "${ipset}.source" ]
	then
		echo >&2 "${ipset}: is disabled, to enable it run: touch -t 0001010000 '${base}/${ipset}.source'"
		return 1
	fi

	# download it
	download_url "${ipset}" "${mins}" "${url}"
	if [ $? -eq ${DOWNLOAD_FAILED} -o $? -eq ${DOWNLOAD_NOT_UPDATED} ]
		then
		[ -d ${ipset} -o ! -s "${ipset}.source" ] && return 1
	fi

	# create a temp dir
	[ -d ${ipset}.tmp ] && rm -rf ${ipset}.tmp
	mkdir ${ipset}.tmp || return 1

	# create the final dir
	if [ ! -d ${ipset} ]
	then
		mkdir ${ipset} || return 1
	fi

	# extract it

	# The country db has the following columns:
	# 1. network 				the subnet
	# 2. geoname_id 			the country code it is used
	# 3. registered_country_geoname_id 	the country code it is registered
	# 4. represented_country_geoname_id 	the country code it belongs to (army bases)
	# 5. is_anonymous_proxy 		boolean: VPN providers, etc
	# 6. is_satellite_provider 		boolean: cross-country providers

	echo >&2 "${ipset}: Extracting country and continent netsets..."
	unzip -jpx "${ipset}.source" "*/GeoLite2-Country-Blocks-IPv4.csv" |\
		awk -F, '
		{
			if( $2 )        { print $1 >"geolite2_country.tmp/country."$2".source.tmp" }
			if( $3 )        { print $1 >"geolite2_country.tmp/country."$3".source.tmp" }
			if( $4 )        { print $1 >"geolite2_country.tmp/country."$4".source.tmp" }
			if( $5 == "1" ) { print $1 >"geolite2_country.tmp/anonymous.source.tmp" }
			if( $6 == "1" ) { print $1 >"geolite2_country.tmp/satellite.source.tmp" }
		}'

	# remove the files created of the header line
	[ -f "${ipset}.tmp/country.geoname_id.source.tmp"                     ] && rm "${ipset}.tmp/country.geoname_id.source.tmp"
	[ -f "${ipset}.tmp/country.registered_country_geoname_id.source.tmp"  ] && rm "${ipset}.tmp/country.registered_country_geoname_id.source.tmp"
	[ -f "${ipset}.tmp/country.represented_country_geoname_id.source.tmp" ] && rm "${ipset}.tmp/country.represented_country_geoname_id.source.tmp"

	# The localization db has the following columns:
	# 1. geoname_id
	# 2. locale_code
	# 3. continent_code
	# 4. continent_name
	# 5. country_iso_code
	# 6. country_name

	echo >&2 "${ipset}: Grouping country and continent netsets..."
	unzip -jpx "${ipset}.source" "*/GeoLite2-Country-Locations-en.csv" |\
	(
		IFS=","
		while read id locale cid cname iso name
		do
			[ "${id}" = "geoname_id" ] && continue

			cname="${cname//\"/}"
			cname="${cname//[/(}"
			cname="${cname//]/)}"
			name="${name//\"/}"
			name="${name//[/(}"
			name="${name//]/)}"

			if [ -f "${ipset}.tmp/country.${id}.source.tmp" ]
			then
				[ ! -z "${cid}" ] && cat "${ipset}.tmp/country.${id}.source.tmp" >>"${ipset}.tmp/continent_${cid,,}.source.tmp"
				[ ! -z "${iso}" ] && cat "${ipset}.tmp/country.${id}.source.tmp" >>"${ipset}.tmp/country_${iso,,}.source.tmp"
				rm "${ipset}.tmp/country.${id}.source.tmp"

				[ ! -f "${ipset}.tmp/continent_${cid,,}.source.tmp.info" ] && printf "%s" "${cname} (${cid}), with countries: " >"${ipset}.tmp/continent_${cid,,}.source.tmp.info"
				printf "%s" "${name} (${iso}), " >>"${ipset}.tmp/continent_${cid,,}.source.tmp.info"
				printf "%s" "${name} (${iso})" >"${ipset}.tmp/country_${iso,,}.source.tmp.info"
			else
				echo >&2 "${ipset}: WARNING: geoname_id ${id} does not exist!"
			fi
		done
	)
	printf "%s" "Anonymous Service Providers" >"${ipset}.tmp/anonymous.source.tmp.info"
	printf "%s" "Satellite Service Providers" >"${ipset}.tmp/satellite.source.tmp.info"

	echo >&2 "${ipset}: Aggregating country and continent netsets..."
	local x=
	for x in ${ipset}.tmp/*.source.tmp
	do
		cat "${x}" |\
			sort -u |\
			filter_all4 |\
			aggregate4 |\
			filter_invalid4 >"${x/.source.tmp/.source}"

		touch -r "${ipset}.source" "${x/.source.tmp/.source}"
		rm "${x}"

		local i=${x/.source.tmp/}
		i=${i/${ipset}.tmp\//}

		local info2="`cat "${x}.info"` -- ${info}"

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${type}" "${hash}" "${url}" "${info2}"
	done

	if [ -d .git ]
	then
		# generate a setinfo for the home page
		echo >"${ipset}.setinfo" "[${ipset}](https://github.com/ktsaou/blocklist-ipsets/tree/master/geolite2_country)|[MaxMind GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/) databases are free IP geolocation databases comparable to, but less accurate than, MaxMind’s GeoIP2 databases. They include IPs per country, IPs per continent, IPs used by anonymous services (VPNs, Proxies, etc) and Satellite Providers.|ipv4 hash:net|All the world|updated every `mins_to_text ${mins}` from [this link](${url})"
	fi

	# remove the temporary dir
	rm -rf "${ipset}.tmp"

	return 0
}

echo >&2

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
# ipv4 ipset create  dm_tor hash:ip
#      ipset addfile dm_tor ipsets/dm_tor.ipset
#
# ipv4 ipset create et_block hash:net
#      ipset addfile et_block ipsets/et_block.netset
#
# ipv4 blacklist full \
#         ipset:openbl \
#         ipset:dm_tor \
#         ipset:et_block
#


# -----------------------------------------------------------------------------
# MaxMind

geolite2_country


# -----------------------------------------------------------------------------
# www.openbl.org

update openbl $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) default blacklist (currently it is the same with 90 days). OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications - **excellent list**"

update openbl_1d $[1*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_1days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 24 hours IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_7d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_7days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 7 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_30d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_30days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 30 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_60d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_60days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 60 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_90d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_90days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 90 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_180d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_180days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 180 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_360d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_360days.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last 360 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."

update openbl_all $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_all.txt" \
	remove_comments \
	"[OpenBL.org](http://www.openbl.org/) last all IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications."


# -----------------------------------------------------------------------------
# www.dshield.org
# https://www.dshield.org/xml.html

# Top 20 attackers (networks) by www.dshield.org
update dshield $[4*60] 0 ipv4 both \
	"http://feeds.dshield.org/block.txt" \
	dshield_parser \
	"[DShield.org](https://dshield.org/) top 20 attacking class C (/24) subnets over the last three days - **excellent list**"


# -----------------------------------------------------------------------------
# TOR lists
# TOR is not necessary hostile, you may need this just for sensitive services.

# https://www.dan.me.uk/tornodes
# This contains a full TOR nodelist (no more than 30 minutes old).
# The page has download limit that does not allow download in less than 30 min.
update dm_tor 30 0 ipv4 ip \
	"https://www.dan.me.uk/torlist/" \
	remove_comments \
	"[dan.me.uk](https://www.dan.me.uk) dynamic list of TOR exit points"

update et_tor $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/emerging-tor.rules" \
	snort_alert_rules_to_ipv4 \
	"[EmergingThreats.net](http://www.emergingthreats.net/) [list](http://doc.emergingthreats.net/bin/view/Main/TorRules) of TOR network IPs"

update bm_tor 30 0 ipv4 ip \
	"https://torstatus.blutmagie.de/ip_list_all.php/Tor_ip_list_ALL.csv" \
	remove_comments \
	"[torstatus.blutmagie.de](https://torstatus.blutmagie.de) list of all TOR network servers"


# -----------------------------------------------------------------------------
# EmergingThreats

# http://doc.emergingthreats.net/bin/view/Main/CompromisedHost
# Includes: openbl, bruteforceblocker and sidreporter
update et_compromised $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/compromised-ips.txt" \
	remove_comments \
	"[EmergingThreats.net compromised hosts](http://doc.emergingthreats.net/bin/view/Main/CompromisedHost) - (this seems to be based on bruteforceblocker)"

# Command & Control servers by shadowserver.org
update et_botcc $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-CC.rules" \
	pix_deny_rules_to_ipv4 \
	"[EmergingThreats.net Command and Control IPs](http://doc.emergingthreats.net/bin/view/Main/BotCC) These IPs are updates every 24 hours and should be considered VERY highly reliable indications that a host is communicating with a known and active Bot or Malware command and control server - (although they say this includes abuse.ch trackers, it does not - most probably it is the shadowserver.org C&C list)"

# This appears to be the SPAMHAUS DROP list
update et_spamhaus $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DROP.rules" \
	pix_deny_rules_to_ipv4 \
	"[EmergingThreats.net](http://www.emergingthreats.net/) spamhaus blocklist"

# Top 20 attackers by www.dshield.org
# disabled - have direct feed above
update et_dshield $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DSHIELD.rules" \
	pix_deny_rules_to_ipv4 \
	"[EmergingThreats.net](http://www.emergingthreats.net/) dshield blocklist"

# includes spamhaus and dshield
update et_block $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt" \
	remove_comments \
	"[EmergingThreats.net](http://www.emergingthreats.net/) default blacklist (at the time of writing includes spamhaus DROP, dshield and abuse.ch trackers, which are available separately too - prefer to use the direct ipsets instead of this, they seem to lag a bit in updates)"


# -----------------------------------------------------------------------------
# Spamhaus
# http://www.spamhaus.org

# http://www.spamhaus.org/drop/
# These guys say that this list should be dropped at tier-1 ISPs globaly!
update spamhaus_drop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/drop.txt" \
	remove_comments_semi_colon \
	"[Spamhaus.org](http://www.spamhaus.org) DROP list (according to their site this list should be dropped at tier-1 ISPs globaly) - **excellent list**"

# extended DROP (EDROP) list.
# Should be used together with their DROP list.
update spamhaus_edrop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/edrop.txt" \
	remove_comments_semi_colon \
	"[Spamhaus.org](http://www.spamhaus.org) EDROP (extended matches that should be used with DROP) - **excellent list**"


# -----------------------------------------------------------------------------
# blocklist.de
# http://www.blocklist.de/en/export.html

# All IP addresses that have attacked one of their servers in the
# last 48 hours. Updated every 30 minutes.
# They also have lists of service specific attacks (ssh, apache, sip, etc).
update blocklist_de 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/all.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) IPs that have been detected by fail2ban in the last 48 hours - **excellent list**"

update blocklist_de_ssh 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/ssh.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service SSH."

update blocklist_de_mail 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/mail.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service Mail, Postfix."

update blocklist_de_apache 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/apache.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service Apache, Apache-DDOS, RFI-Attacks."

update blocklist_de_imap 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/imap.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours for attacks on the Service imap, sasl, pop3, etc."

update blocklist_de_ftp 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/ftp.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours for attacks on the Service FTP."

update blocklist_de_sip 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/sip.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses that tried to login in a SIP, VOIP or Asterisk Server and are included in the IPs list from [infiltrated.net](www.infiltrated.net)"

update blocklist_de_bots 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/bots.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the RFI-Attacks, REG-Bots, IRC-Bots or BadBots (BadBots = he has posted a Spam-Comment on a open Forum or Wiki)."

update blocklist_de_strongips 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/strongips.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IPs which are older then 2 month and have more then 5.000 attacks."

#update blocklist_de_ircbot 30 0 ipv4 ip \
#	"http://lists.blocklist.de/lists/ircbot.txt" \
#	remove_comments \
#	"[Blocklist.de](https://www.blocklist.de/) (no information supplied)"

update blocklist_de_bruteforce 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/bruteforcelogin.txt" \
	remove_comments \
	"[Blocklist.de](https://www.blocklist.de/) All IPs which attacks Joomlas, Wordpress and other Web-Logins with Brute-Force Logins."


# -----------------------------------------------------------------------------
# Zeus trojan
# https://zeustracker.abuse.ch/blocklist.php
# by abuse.ch

# This blocklists only includes IPv4 addresses that are used by the ZeuS trojan.
update zeus_badips 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=badips" \
	remove_comments \
	"[Abuse.ch Zeus tracker](https://zeustracker.abuse.ch) badips includes IPv4 addresses that are used by the ZeuS trojan. It is the recommened blocklist if you want to block only ZeuS IPs. It excludes IP addresses that ZeuS Tracker believes to be hijacked (level 2) or belong to a free web hosting provider (level 3). Hence the false postive rate should be much lower compared to the standard ZeuS IP blocklist. **excellent list**"

# This blocklist contains the same data as the ZeuS IP blocklist (BadIPs)
# but with the slight difference that it doesn't exclude hijacked websites
# (level 2) and free web hosting providers (level 3).
update zeus 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=ipblocklist" \
	remove_comments \
	"[Abuse.ch Zeus tracker](https://zeustracker.abuse.ch) standard, contains the same data as the ZeuS IP blocklist (zeus_badips) but with the slight difference that it doesn't exclude hijacked websites (level 2) and free web hosting providers (level 3). This means that this blocklist contains all IPv4 addresses associated with ZeuS C&Cs which are currently being tracked by ZeuS Tracker. Hence this blocklist will likely cause some false positives. - **excellent list**"


# -----------------------------------------------------------------------------
# Palevo worm
# https://palevotracker.abuse.ch/blocklists.php
# by abuse.ch

# includes IP addresses which are being used as botnet C&C for the Palevo crimeware
update palevo 30 0 ipv4 ip \
	"https://palevotracker.abuse.ch/blocklists.php?download=ipblocklist" \
	remove_comments \
	"[Abuse.ch Palevo tracker](https://palevotracker.abuse.ch) worm includes IPs which are being used as botnet C&C for the Palevo crimeware - **excellent list**"


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
	"[Abuse.ch Feodo tracker](https://feodotracker.abuse.ch) trojan includes IPs which are being used by Feodo (also known as Cridex or Bugat) which commits ebanking fraud - **excellent list**"


# -----------------------------------------------------------------------------
# SSLBL
# https://sslbl.abuse.ch/
# by abuse.ch

# IPs with "bad" SSL certificates identified by abuse.ch to be associated with malware or botnet activities
update sslbl 30 0 ipv4 ip \
	"https://sslbl.abuse.ch/blacklist/sslipblacklist.csv" \
	csv_comma_first_column \
	"[Abuse.ch SSL Blacklist](https://sslbl.abuse.ch/) bad SSL traffic related to malware or botnet activities - **excellent list**"


# -----------------------------------------------------------------------------
# infiltrated.net
# http://www.infiltrated.net/blacklisted

update infiltrated $[12*60] 0 ipv4 ip \
	"http://www.infiltrated.net/blacklisted" \
	remove_comments \
	"[infiltrated.net](http://www.infiltrated.net) (this list seems to be updated frequently, but we found no information about it)"


# -----------------------------------------------------------------------------
# malc0de
# http://malc0de.com

# updated daily and populated with the last 30 days of malicious IP addresses.
update malc0de $[24*60] 0 ipv4 ip \
	"http://malc0de.com/bl/IP_Blacklist.txt" \
	remove_comments \
	"[Malc0de.com](http://malc0de.com) malicious IPs of the last 30 days"


# -----------------------------------------------------------------------------
# Stop Forum Spam
# http://www.stopforumspam.com/downloads/

# to use this, create the ipset like this (in firehol.conf):
# >> ipset4 create stop_forum_spam hash:ip maxelem 500000
# -- normally, you don't need this set --
# -- use the hourly and the daily ones instead --
# IMPORTANT: THIS IS A BIG LIST - you will have to add maxelem to ipset to fit it
update stopforumspam_ever $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/bannedips.zip" \
	unzip_and_split_csv \
	"[StopForumSpam.com](http://www.stopforumspam.com) all IPs used by forum spammers, **ever** (normally you don't want to use this ipset, use the hourly one which includes last 24 hours IPs or the 7 days one)"

# hourly update with IPs from the last 24 hours
update stopforumspam_1d 60 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_1.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers in the last 24 hours - **excellent list**"

# daily update with IPs from the last 7 days
update stopforumspam_7d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_7.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 7 days)"

# daily update with IPs from the last 30 days
update stopforumspam_30d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_30.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 30 days)"

# daily update with IPs from the last 90 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_90d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_90.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 90 days)"

# daily update with IPs from the last 180 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_180d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_180.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 180 days)"

# daily update with IPs from the last 365 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_365d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_365.zip" \
	unzip_and_extract \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 365 days)"


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
update bogons $[24*60] 0 ipv4 both \
	"http://www.team-cymru.org/Services/Bogons/bogon-bn-agg.txt" \
	remove_comments \
	"[Team-Cymru.org](http://www.team-cymru.org) private and reserved addresses defined by RFC 1918, RFC 5735, and RFC 6598 and netblocks that have not been allocated to a regional internet registry - **excellent list - use it only your internet interface**"


# http://www.team-cymru.org/bogon-reference.html
# Fullbogons are a larger set which also includes IP space that has been
# allocated to an RIR, but not assigned by that RIR to an actual ISP or other
# end-user.
update fullbogons $[24*60] 0 ipv4 both \
	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt" \
	remove_comments \
	"[Team-Cymru.org](http://www.team-cymru.org) IP space that has been allocated to an RIR, but not assigned by that RIR to an actual ISP or other end-user - **excellent list - use it only your internet interface**"

#update fullbogons6 $[24*60-10] ipv6 both \
#	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt" \
#	remove_comments \
#	"Team-Cymru.org provided"


# -----------------------------------------------------------------------------
# Open Proxies from rosinstruments
# http://tools.rosinstrument.com/proxy/

update ri_web_proxies 60 $[30*24*60] ipv4 ip \
	"http://tools.rosinstrument.com/proxy/l100.xml" \
	parse_rss_rosinstrument \
	"[rosinstrument.com](http://www.rosinstrument.com) open HTTP proxies (this list is composed using an RSS feed and aggregated for the last 30 days)"

update ri_connect_proxies 60 $[30*24*60] ipv4 ip \
	"http://tools.rosinstrument.com/proxy/plab100.xml" \
	parse_rss_rosinstrument \
	"[rosinstrument.com](http://www.rosinstrument.com) open CONNECT proxies (this list is composed using an RSS feed and aggregated for the last 30 days)"


# -----------------------------------------------------------------------------
# Open Proxies from xroxy.com
# http://www.xroxy.com

update xroxy 60 $[30*24*60] ipv4 ip \
	"http://www.xroxy.com/proxyrss.xml" \
	parse_rss_proxy \
	"[xroxy.com](http://www.xroxy.com) open proxies (this list is composed using an RSS feed and aggregated for the last 30 days)"


# -----------------------------------------------------------------------------
# Open Proxies from proxz.com
# http://www.proxz.com/

update proxz 60 $[30*24*60] ipv4 ip \
	"http://www.proxz.com/proxylists.xml" \
	parse_rss_proxy \
	"[proxz.com](http://www.proxz.com) open proxies (this list is composed using an RSS feed and aggregated for the last 30 days)"


# -----------------------------------------------------------------------------
# Open Proxies from proxyrss.com
# http://www.proxyrss.com/

update proxyrss $[4*60] 0 ipv4 ip \
	"http://www.proxyrss.com/proxylists/all.gz" \
	gz_proxyrss \
	"[proxyrss.com](http://www.proxyrss.com) open proxies syndicated from multiple sources."


# -----------------------------------------------------------------------------
# Anonymous Proxies
# https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list

update maxmind_proxy_fraud $[4*60] $[30*24*60] ipv4 ip \
	"https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list" \
	parse_maxmind_proxy_fraud \
	"[MaxMind.com](https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list) list of anonymous proxy fraudelent IP addresses."


# -----------------------------------------------------------------------------
# Project Honey Pot
# http://www.projecthoneypot.org/?rf=192670

update php_harvesters 60 $[30*24*60] ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=h&rss=1" \
	parse_php_rss \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) harvesters (IPs that surf the internet looking for email addresses) (this list is composed using an RSS feed and aggregated for the last 30 days)"

update php_spammers 60 $[30*24*60] ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=s&rss=1" \
	parse_php_rss \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) spam servers (IPs used by spammers to send messages) (this list is composed using an RSS feed and aggregated for the last 30 days)"

update php_bad 60 $[30*24*60] ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=b&rss=1" \
	parse_php_rss \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) bad web hosts (this list is composed using an RSS feed and aggregated for the last 30 days)"

update php_commenters 60 $[30*24*60] ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=c&rss=1" \
	parse_php_rss \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) comment spammers (this list is composed using an RSS feed and aggregated for the last 30 days)"

update php_dictionary 60 $[30*24*60] ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" \
	parse_php_rss \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) directory attackers (this list is composed using an RSS feed and aggregated for the last 30 days)"


# -----------------------------------------------------------------------------
# Malware Domain List
# All IPs should be considered dangerous

update malwaredomainlist $[12*60] 0 ipv4 ip \
	"http://www.malwaredomainlist.com/hostslist/ip.txt" \
	remove_comments \
	"[malwaredomainlist.com](http://www.malwaredomainlist.com) list of malware active ip addresses"


# -----------------------------------------------------------------------------
# Alien Vault
# Alienvault IP Reputation Database

# IMPORTANT: THIS IS A BIG LIST
# you will have to add maxelem to ipset to fit it
update alienvault_reputation $[6*60] 0 ipv4 ip \
	"https://reputation.alienvault.com/reputation.generic" \
	remove_comments \
	"[AlienVault.com](https://www.alienvault.com/) IP reputation database (this list seems to include port scanning hosts and to be updated regularly, but we found no information about its retention policy)"


# -----------------------------------------------------------------------------
# Clean-MX
# Viruses

update cleanmx_viruses $[12*60] 0 ipv4 ip \
	"http://support.clean-mx.de/clean-mx/xmlviruses.php?sort=id%20desc&response=alive" \
	parse_xml_clean_mx \
	"[Clean-MX.de](http://support.clean-mx.de/clean-mx/viruses.php) IPs with viruses"


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
	"[CIArmy.com](http://ciarmy.com/) IPs with poor Rogue Packet score that have not yet been identified as malicious by the community"


# -----------------------------------------------------------------------------
# Bruteforce Blocker
# http://danger.rulez.sk/projects/bruteforceblocker/

update bruteforceblocker $[3*60] 0 ipv4 ip \
	"http://danger.rulez.sk/projects/bruteforceblocker/blist.php" \
	remove_comments \
	"[danger.rulez.sk](http://danger.rulez.sk/) IPs detected by [bruteforceblocker](http://danger.rulez.sk/index.php/bruteforceblocker/) (fail2ban alternative for SSH on OpenBSD). This is an automatically generated list from users reporting failed authentication attempts. An IP seems to be included if 3 or more users report it. Its retention pocily seems 30 days."


# -----------------------------------------------------------------------------
# Snort ipfilter
# http://labs.snort.org/feeds/ip-filter.blf

update snort_ipfilter $[12*60] 0 ipv4 ip \
	"http://labs.snort.org/feeds/ip-filter.blf" \
	remove_comments \
	"[labs.snort.org](https://labs.snort.org/) supplied IP blacklist (this list seems to be updated frequently, but we found no information about it)"


# -----------------------------------------------------------------------------
# NiX Spam
# http://www.heise.de/ix/NiX-Spam-DNSBL-and-blacklist-for-download-499637.html

update nixspam 15 0 ipv4 ip \
	"http://www.dnsbl.manitu.net/download/nixspam-ip.dump.gz" \
	gz_second_word \
	"[NiX Spam](http://www.heise.de/ix/NiX-Spam-DNSBL-and-blacklist-for-download-499637.html) IP addresses that sent spam in the last hour - automatically generated entries without distinguishing open proxies from relays, dialup gateways, and so on. All IPs are removed after 12 hours if there is no spam from there."


# -----------------------------------------------------------------------------
# VirBL
# http://virbl.bit.nl/

update virbl 60 0 ipv4 ip \
	"http://virbl.bit.nl/download/virbl.dnsbl.bit.nl.txt" \
	remove_comments \
	"[VirBL](http://virbl.bit.nl/) is a project of which the idea was born during the RIPE-48 meeting. The plan was to get reports of virusscanning mailservers, and put the IP-addresses that were reported to send viruses on a blacklist."


# -----------------------------------------------------------------------------
# AutoShun.org
# http://www.autoshun.org/

update shunlist $[4*60] 0 ipv4 ip \
	"http://www.autoshun.org/files/shunlist.csv" \
	csv_comma_first_column \
	"[AutoShun.org](http://autoshun.org/) IPs identified as hostile by correlating logs from distributed snort installations running the autoshun plugin"


# -----------------------------------------------------------------------------
# VoIPBL.org
# http://www.voipbl.org/

update voipbl $[4*60] 0 ipv4 both \
	"http://www.voipbl.org/update/" \
	remove_comments \
	"[VoIPBL.org](http://www.voipbl.org/) a distributed VoIP blacklist that is aimed to protects against VoIP Fraud and minimizing abuse for network that have publicly accessible PBX's. Several algorithms, external sources and manual confirmation are used before they categorize something as an attack and determine the threat level."


# -----------------------------------------------------------------------------
# LashBack Unsubscribe Blacklist
# http://blacklist.lashback.com/
# (this is a big list, more than 500.000 IPs)

update lashback_ubl $[24*60] 0 ipv4 ip \
	"http://www.unsubscore.com/blacklist.txt" \
	remove_comments \
	"[The LashBack UBL](http://blacklist.lashback.com/) The Unsubscribe Blacklist (UBL) is a real-time blacklist of IP addresses which are sending email to names harvested from suppression files (this is a big list, more than 500.000 IPs)"


# -----------------------------------------------------------------------------
# iBlocklist
# https://www.iblocklist.com/lists.php
# http://bluetack.co.uk/forums/index.php?autocom=faq&CODE=02&qid=17

if [ ${CAN_CONVERT_RANGES_TO_CIDR} -eq 1 ]
then
	# open proxies and tor
	# we only keep the proxies IPs (tor IPs are not parsed)
	update ib_bluetack_proxies $[12*60] 0 ipv4 ip \
		"http://list.iblocklist.com/?list=xoebmbyexwuiogmbyprb&fileformat=p2p&archiveformat=gz" \
		p2p_gz_proxy \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) Open Proxies IPs list (without TOR)"


	# This list is a compilation of known malicious SPYWARE and ADWARE IP Address ranges.
	# It is compiled from various sources, including other available Spyware Blacklists,
	# HOSTS files, from research found at many of the top Anti-Spyware forums, logs of
	# Spyware victims and also from the Malware Research Section here at Bluetack.
	update ib_bluetack_spyware $[12*60] 0 ipv4 both \
		"http://list.iblocklist.com/?list=llvtlsjyoyiczbkjsxpf&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) known malicious SPYWARE and ADWARE IP Address ranges"


	# List of people who have been reported for bad deeds in p2p.
	update ib_bluetack_badpeers $[12*60] 0 ipv4 ip \
		"http://list.iblocklist.com/?list=cwworuawihqvocglcoss&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) IPs that have been reported for bad deeds in p2p"


	# Contains hijacked IP-Blocks and known IP-Blocks that are used to deliver Spam. 
	# This list is a combination of lists with hijacked IP-Blocks 
	# Hijacked IP space are IP blocks that are being used without permission by
	# organizations that have no relation to original organization (or its legal
	# successor) that received the IP block. In essence it's stealing of somebody
	# else's IP resources
	update ib_bluetack_hijacked $[12*60] 0 ipv4 both \
		"http://list.iblocklist.com/?list=usrcshglbiilevmyfhse&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) hijacked IP-Blocks Hijacked IP space are IP blocks that are being used without permission"


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
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) web server hack and exploit attempts"


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
	update ib_bluetack_level1 $[12*60] 0 ipv4 both \
		"http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of [BlueTack.co.uk](http://www.bluetack.co.uk/) Level 1 (for use in p2p): Companies or organizations who are clearly involved with trying to stop filesharing (e.g. Baytsp, MediaDefender, Mediasentry a.o.). Companies which anti-p2p activity has been seen from. Companies that produce or have a strong financial interest in copyrighted material (e.g. music, movie, software industries a.o.). Government ranges or companies that have a strong financial interest in doing work for governments. Legal industry ranges. IPs or ranges of ISPs from which anti-p2p activity has been observed. Basically this list will block all kinds of internet connections that most people would rather not have during their internet travels."


	# General corporate ranges. 
	# Ranges used by labs or researchers. 
	# Proxies. 
	update ib_bluetack_level2 $[12*60] 0 ipv4 both \
		"http://list.iblocklist.com/?list=gyisgnzbhppbvsphucsw&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of BlueTack.co.uk Level 2 (for use in p2p). General corporate ranges. Ranges used by labs or researchers. Proxies."


	# Many portal-type websites. 
	# ISP ranges that may be dodgy for some reason. 
	# Ranges that belong to an individual, but which have not been determined to be used by a particular company. 
	# Ranges for things that are unusual in some way. The L3 list is aka the paranoid list.
	update ib_bluetack_level3 $[12*60] 0 ipv4 both \
		"http://list.iblocklist.com/?list=uwnukjqktoggdknzrhgh&fileformat=p2p&archiveformat=gz" \
		p2p_gz \
		"[iBlocklist.com](https://www.iblocklist.com/) free version of BlueTack.co.uk Level 3 (for use in p2p). Many portal-type websites. ISP ranges that may be dodgy for some reason. Ranges that belong to an individual, but which have not been determined to be used by a particular company. Ranges for things that are unusual in some way. The L3 list is aka the paranoid list."

fi

# -----------------------------------------------------------------------------
# BadIPs.com

badipscom() {
	if [ ! -f "badips.source" ]
		then
		[ -d .git ] && echo >"${install}.setinfo" "badips.com categories ipsets|[BadIPs.com](https://www.badips.com) community based IP blacklisting. They score IPs based on the reports they reports.|ipv4 hash:ip|disabled|disabled"
		echo >&2 "badips: is disabled, to enable it run: touch -t 0001010000 '${base}/badips.source'"
		return 0
	fi

	download_url "badips" $[24*60] "https://www.badips.com/get/categories"
	[ ! -s "badips.source" ] && return 0

	local categories="$(cat badips.source |\
		tr "[]{}," "\n\n\n\n\n" |\
		egrep '^"Name":"[a-zA-Z0-9_-]+"$' |\
		cut -d ':' -f 2 |\
		cut -d '"' -f 2 |\
		sort -u)"
	
	local category= file= score= age= i= ipset= url= info= count=0
	for category in ${categories}
	do
		count=0
		# echo >&2 "bi_${category}"

		for file in $(ls 2>/dev/null bi_${category}*.source)
		do
			count=$[count + 1]
			if [[ "${file}" =~ ^bi_${category}_[0-9\.]+_[0-9]+[dwmy].source$ ]]
				then
				# score and age present
				i="$(echo "${file}" | sed "s|^bi_${category}_\([0-9\.]\+\)_\([0-9]\+[dwmy]\)\.source|\1;\2|g")"
				score=${i/;*/}
				age="${i/*;/}"
				ipset="bi_${category}_${score}_${age}"
				url="https://www.badips.com/get/list/${category}/${score}?age=${age}"
				info="[BadIPs.com](https://www.badips.com/) Bad IPs in category ${category} with score above ${score} and age less than ${age}"
				if [ ! -f "${ipset}.source" ]
					then
					echo >&2 "${file}: cannot parse ipset name to find score and age"
					continue
				fi

			elif [[ "${file}" =~ ^bi_${category}_[0-9]+[dwmy].source$ ]]
				then
				# age present
				age="$(echo "${file}" | sed "s|^bi_${category}_\([0-9]\+[dwmy]\)\.source|\1|g")"
				score=0
				ipset="bi_${category}_${age}"
				url="https://www.badips.com/get/list/${category}/${score}?age=${age}"
				info="[BadIPs.com](https://www.badips.com/) Bad IPs in category ${category} with age less than ${age}"
				if [ ! -f "${ipset}.source" ]
					then
					echo >&2 "${file}: cannot parse ipset name to find age"
					continue
				fi

			elif [[ "${file}" =~ ^bi_${category}_[0-9\.]+.source$ ]]
				then
				# score present
				score="$(echo "${file}" | sed "s|^bi_${category}_\([0-9\.]\+\)\.source|\1|g")"
				age=
				ipset="bi_${category}_${score}"
				url="https://www.badips.com/get/list/${category}/${score}"
				info="[BadIPs.com](https://www.badips.com/) Bad IPs in category ${category} with score above ${score}"
				if [ ! -f "${ipset}.source" ]
					then
					echo >&2 "${file}: cannot parse ipset name to find score"
					continue
				fi
			else
				# none present
				echo >&2 "${file}: Cannot find SCORE or AGE in filename. Use numbers."
				continue
			fi

			update "${ipset}" 30 0 ipv4 ip "${url}" remove_comments "${info}"
		done

		if [ ${count} -eq 0 ]
			then
			echo >&2 "bi_${category}_SCORE_AGE: is disabled (SCORE=[0-9\.]+ and AGE=[0-9]+[dwmy]. AGE can be ommitted. To enable it run: touch -t 0001010000 '${base}/bi_${category}_SCORE_AGE.source'"
		fi
	done
}

badipscom

# -----------------------------------------------------------------------------
# TODO List

#merge firehol_level1 \
#	feodo.ipset palevo.ipset sslbl.ipset zeus.ipset dshield.netset spamhaus_drop.netset spamhaus_edrop.netset fullbogons.netset openbl.ipset blocklist.ipset

# TODO
#
# add sets
# - http://www.nothink.org/blacklist/blacklist_ssh_week.txt
# - http://www.nothink.org/blacklist/blacklist_malware_irc.txt
# - http://www.nothink.org/blacklist/blacklist_malware_http.txt
# - http://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=1.1.1.1
# - http://www.ipdeny.com/ipblocks/ geo country db for both ipv4 and ipv6
# - maxmind city geodb
#
# user specific features
# - allow the user to request a merge of 2 or more sets
# - allow the user to request an email if a set increases by a percentage or number of unique IPs
# - allow the user to request an email if a set matches more than X entries of one or more other set
# 
# site specific features
# - find a way to compare ipsets faster, so that maxmind geodbs can be added to comparison
#   and the "git pull" is done faster (now "git pull" waits the comparisons to be completed)
# - save all comparisons in .json to allow generating charts on the site
# - save set quantities in .json to allow monitoring the size of sets with charts

