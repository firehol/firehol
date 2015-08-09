#!/bin/bash
#
# Version
# $Id$
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
#    - it will use compression when possible.
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
#    - generaly, anything that can be converted using shell commands
#
# 3. For all file types it can keep a history of the processed sets
#    that can be merged with the new downloaded one, so that it can
#    populate the generated set with all the IPs of the last X days.
#
# 4. For each set updated, it will:
#    - save it to disk
#    - update a kernel ipset, having the same name
#
# 5. It can commit all successfully updated files to a git repository.
#    Just do 'git init' in /etc/firehol/ipsets to enable it.
#    If it is called with -g it will also push the committed changes
#    to a remote git server (to have this done by cron, please set
#    git to automatically push changes without human action).
#
# 6. It can compare ipsets and keep track of geomaping, history of size,
#    age of IPs listed, retention policy, overlaps with other sets.
#    To enable it, run it with -c.
#
# -----------------------------------------------------------------------------
#
# How to use it:
# 
# This script depends on iprange, found also in firehol.
# It does not depend on firehol. You can use it without firehol.
# 
# 1. Run this script. It will give you instructions on which
#    IP lists are available and what to do to enable them.
# 2. Enable a few lists, following its instructions.
# 3. Run it again to update the lists.
# 4. Put it in a cron job to do the updates automatically.

# -----------------------------------------------------------------------------

# single line flock, from man flock
LOCK_FILE="/var/run/update-ipsets.lock"
[ ! "${UID}" = "0" ] && LOCK_FILE="${HOME}/.update-upsets.lock"
[ "${UPDATE_IPSETS_LOCKER}" != "${0}" ] && exec env UPDATE_IPSETS_LOCKER="$0" flock -en "${LOCK_FILE}" "${0}" "${@}" || :

PATH="${PATH}:/sbin:/usr/sbin"

LC_ALL=C
umask 077

IPSETS_APPLY=1
if [ ! "${UID}" = "0" ]
then
	echo >&2 "I run as a normal user. I'll not be able to load ipsets to the kernel."
	IPSETS_APPLY=0
fi
renice 10 $$ >/dev/null 2>/dev/null

if [ -t 2 -a $[$(tput colors 2>/dev/null)] -ge 8 ]
then
	# Enable colors
	COLOR_RESET="\e[0m"
	COLOR_BLACK="\e[30m"
	COLOR_RED="\e[31m"
	COLOR_GREEN="\e[32m"
	COLOR_YELLOW="\e[33m"
	COLOR_BLUE="\e[34m"
	COLOR_PURPLE="\e[35m"
	COLOR_CYAN="\e[36m"
	COLOR_WHITE="\e[37m"
	COLOR_BGBLACK="\e[40m"
	COLOR_BGRED="\e[41m"
	COLOR_BGGREEN="\e[42m"
	COLOR_BGYELLOW="\e[43m"
	COLOR_BGBLUE="\e[44m"
	COLOR_BGPURPLE="\e[45m"
	COLOR_BGCYAN="\e[46m"
	COLOR_BGWHITE="\e[47m"
	COLOR_BOLD="\e[1m"
	COLOR_DIM="\e[2m"
	COLOR_UNDERLINED="\e[4m"
	COLOR_BLINK="\e[5m"
	COLOR_INVERTED="\e[7m"
fi

# -----------------------------------------------------------------------------
# external commands management

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
require_cmd mktemp

program_pwd="${PWD}"
program_dir="`dirname ${0}`"

# -----------------------------------------------------------------------------
# find a working iprange command

IPRANGE_CMD="$(which iprange 2>&1)"
if [ ! -z "${IPRANGE_CMD}" -a -x "${IPRANGE_CMD}" ]
	then
	"${IPRANGE_CMD}" --has-reduce >/dev/null 2>&1
	[ $? -ne 0 ] && IPRANGE_CMD=
fi

if [ -z "${IPRANGE_CMD}" -a -x "/etc/firehol/iprange" ]
	then
	IPRANGE_CMD="/etc/firehol/iprange"
	"${IPRANGE_CMD}" --has-reduce >/dev/null 2>&1
	[ $? -ne 0 ] && IPRANGE_CMD=
fi

if [ -z "${IPRANGE_CMD}" -a -x "/etc/firehol/ipsets/iprange" ]
	then
	IPRANGE_CMD="/etc/firehol/ipsets/iprange"
	"${IPRANGE_CMD}" --has-reduce >/dev/null 2>&1
	[ $? -ne 0 ] && IPRANGE_CMD=
fi

if [ -z "${IPRANGE_CMD}" -a ! -x "${program_dir}/iprange" -a -f "${program_dir}/iprange.c" ]
	then
	echo >&2 "Attempting to compile FireHOL's iprange..."
	gcc -O3 -o "${program_dir}/iprange" "${program_dir}/iprange.c"
fi

if [ -z "${IPRANGE_CMD}" -a -x "${program_dir}/iprange" ]
	then
	IPRANGE_CMD="${program_dir}/iprange"
	"${IPRANGE_CMD}" --has-reduce >/dev/null 2>&1
	[ $? -ne 0 ] && IPRANGE_CMD=
fi

if [ -z "${IPRANGE_CMD}" ]
	then
	echo >&2 "Cannot find a working iprange command."
	echo >&2 "In the contrib directory of FireHOL, please run 'make install'."
	exit 1
fi

# iprange filter to convert ipv4 range to cidr
ipv4_range_to_cidr() {
	"${IPRANGE_CMD}"
}

# iprange filter to aggregate ipv4 addresses
aggregate4() {
	"${IPRANGE_CMD}"
}

# iprange filter to process ipsets (IPv4 IPs, not subnets)
ipset_uniq4() {
	"${IPRANGE_CMD}" -1
}

# -----------------------------------------------------------------------------
# CONFIGURATION

# where to store the files
BASE_DIR="/etc/firehol/ipsets"

# where to keep the run files
# a subdirectory will be created as RUN_DIR
RUN_PARENT_DIR="/var/run"

# where to keep the history files
HISTORY_DIR="${BASE_DIR}/history"

# where to keep the files we cannot process
# when empty, error files will be deleted
ERRORS_DIR="${BASE_DIR}/errors"

# where to put the CSV files for the web server
WEB_DIR="/var/www/localhost/htdocs/blocklists"

# how to chown web files
WEB_OWNER="apache:apache"

# where to store the web retention detection cache
CACHE_DIR="/var/lib/update-ipsets"

# where is the web url to show info about each ipset
# the ipset name is appended to it
WEB_URL="http://ktsaou.github.io/blocklist-ipsets/?ipset="

# options to be given to iprange for reducing netsets
IPSET_REDUCE_FACTOR="20"
IPSET_REDUCE_ENTRIES="65536"

# if the .git directory is present, push it also
PUSH_TO_GIT=0


# -----------------------------------------------------------------------------
# Command line parsing

ENABLE_ALL=0
IGNORE_LASTCHECKED=0
FORCE_WEB_REBUILD=0
SILENT=0
VERBOSE=0
CONFIG_FILE="/etc/firehol/update-ipsets.conf"
while [ ! -z "${1}" ]
do
	case "${1}" in
		--rebuild|-r) FORCE_WEB_REBUILD=1;;
		--silent|-s) SILENT=1;;
		--push-git|-g) PUSH_TO_GIT=1;;
		--recheck|-i) IGNORE_LASTCHECKED=1;;
		--compare|-c) ;; # obsolete
		--verbose|-v) VERBOSE=1;;
		--config|-f) CONFIG_FILE="${2}"; shift ;;
		--enable-all) ENABLE_ALL=1;;
		--help|-h) echo "${0} [--verbose|-v] [--push-git|-g] [--recheck|-i] [--rebuild|-r] [--enable-all] [--config|-f FILE]"; exit 1 ;;
		*) echo >&2 "Unknown parameter '${1}'".; exit 1 ;;
	esac
	shift
done

if [ -f "${CONFIG_FILE}" ]
	then
	echo >&2 "Loading configuration from ${CONFIG_FILE}"
	source "${CONFIG_FILE}"
fi

# -----------------------------------------------------------------------------
# FIX DIRECTORIES

if [ -z "${BASE_DIR}" ]
	then
	echo >&2 "BASE_DIR cannot be empty."
	exit 1
fi

if [ -z "${RUN_PARENT_DIR}" ]
	then
	echo >&2 "RUN_PARENT_DIR cannot be empty."
	exit 1
fi

if [ ! -z "${WEB_DIR}" -a ! -d "${WEB_DIR}" ]
	then
	echo >&2 "WEB_DIR is invalid. Disabling it."
	WEB_DIR=
fi

for d in "${BASE_DIR}" "${RUN_PARENT_DIR}" "${HISTORY_DIR}" "${ERRORS_DIR}"
do
	[ -z "${d}" -o -d "${d}" ] && continue

	mkdir -p "${d}" || exit 1
	echo >&2 "Created directory '${d}'."
done
cd "${BASE_DIR}" || exit 1

# -----------------------------------------------------------------------------
# CLEANUP

RUN_DIR=$(${MKTEMP_CMD} -d "${RUN_PARENT_DIR}/update-ipsets-XXXXXXXXXX")
if [ $? -ne 0 ]
	then
	echo >&2 "ERROR: Cannot create temporary directory in ${RUN_PARENT_DIR}."
	exit 1
fi

PROGRAM_COMPLETED=0
cleanup() {
	if [ ! -z "${RUN_DIR}" -a -d "${RUN_DIR}" ]
		then
		[ ${VERBOSE} -eq 1 ] && echo >&2 "Cleaning up temporary files in ${RUN_DIR}."
		rm -rf "${RUN_DIR}"
	fi
	trap exit EXIT
	
	if [ ${PROGRAM_COMPLETED} -eq 1 ]
		then
		[ ${VERBOSE} -eq 1 ] && echo >&2 "Completed successfully."
		exit 0
	fi

	[ ${VERBOSE} -eq 1 ] && echo >&2 "Completed with errors."
	exit 1
}
trap cleanup EXIT
trap cleanup SIGHUP
trap cleanup INT

# -----------------------------------------------------------------------------
# other preparations

if [ ! -d ".git" -a ${PUSH_TO_GIT} -ne 0 ]
then
	echo >&2 "Git is not initialized in ${BASE_DIR}. Ignoring git support."
	PUSH_TO_GIT=0
fi


# -----------------------------------------------------------------------------
# COMMON FUNCTIONS

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

# http://stackoverflow.com/questions/3046436/how-do-you-stop-tracking-a-remote-branch-in-git
# to delete a branch on git
# localy only - remote will not be affected
#
# BRANCH_TO_DELETE_LOCALY_ONLY="master"
# git branch -d -r origin/${BRANCH_TO_DELETE_LOCALY_ONLY}
# git config --unset branch.${BRANCH_TO_DELETE_LOCALY_ONLY}.remote
# git config --unset branch.${BRANCH_TO_DELETE_LOCALY_ONLY}.merge
# git gc --aggressive --prune=all --force

declare -A DO_NOT_REDISTRIBUTE=()
commit_to_git() {
	if [ -d .git -a ! -z "${!UPDATED_SETS[*]}" ]
	then
		cd "${BASE}" || return 1

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

		declare -a to_be_pushed=()
		for d in "${UPDATED_SETS[@]}"
		do
			[ ! -z "${DO_NOT_REDISTRIBUTE[${d}]}" ] && continue
			[ ! -f "${d}" ] && continue

			to_be_pushed=("${to_be_pushed[@]}" "${d}")
		done

		echo >&2 "Generating script to fix timestamps..."
		(
			echo "#!/bin/bash"
			echo "[ ! \"\$1\" = \"YES_I_AM_SURE_DO_IT_PLEASE\" ] && echo \"READ ME NOW\" && exit 1"
			for d in $(params_sort "${!IPSET_FILE[@]}")
			do
				echo "[ -f '${IPSET_FILE[${d}]}' ] && touch --date=@${IPSET_SOURCE_DATE[${d}]} '${IPSET_FILE[${d}]}'"
			done
		) | sed "s|'${BASE}/|'|g" >set_file_timestamps.sh
		check_git_committed set_file_timestamps.sh

		echo >&2 
		syslog "Committing ${to_be_pushed[@]} to git repository"
		git commit "${to_be_pushed[@]}" set_file_timestamps.sh -m "`date -u` update"

		if [ ${PUSH_TO_GIT} -ne 0 ]
		then
			echo >&2 
			syslog "Pushing git commits to remote server"
			git push
		fi
	fi
}

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
	if [ ${IPSETS_APPLY} -eq 1 ]
		then
		( ipset --list -t || ipset --list ) | grep "^Name: " | cut -d ' ' -f 2
		return $?
	fi
	return 0
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

history_keep() {
	local ipset="${1}" file="${2}" slot=

	slot="`date -r "${file}" +%s`.set"

	if [ ! -d "${HISTORY_DIR}/${ipset}" ]
	then
		mkdir "${HISTORY_DIR}/${ipset}" || return 2
		chmod 700 "${HISTORY_DIR}/${ipset}"
	fi

	# copy the new file to the history
	cp -p "${file}" "${HISTORY_DIR}/${ipset}/${slot}"
}

history_cleanup() {
	local ipset="${1}" mins="${2}"

	# touch a reference file
	touch_in_the_past ${mins} "${RUN_DIR}/history.reference" || return 3

	for x in ${HISTORY_DIR}/${ipset}/*.set
	do
		if [ ! "${x}" -nt "${RUN_DIR}/history.reference" ]
		then
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: deleting history file '${x}'"
			rm "${x}"
		fi
	done
}

history_get() {
	local ipset="${1}" mins="${2}" \
		tmp= x=

	# touch a reference file
	touch_in_the_past ${mins} "${RUN_DIR}/history.reference" || return 3

	# replace the original file with a concatenation of
	# all the files newer than the reference file
	local -a hfiles=()
	for x in ${HISTORY_DIR}/${ipset}/*.set
	do
		if [ "${x}" -nt "${RUN_DIR}/history.reference" ]
		then
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: merging history file '${x}'"
			hfiles=("${hfiles[@]}" "${x}")
		fi
	done

	"${IPRANGE_CMD}" --union-all "${hfiles[@]}"

	rm "${RUN_DIR}/history.reference"

	return 0
}

# -----------------------------------------------------------------------------
# DOWNLOADERS

# RETURN
# 0 = SUCCESS
# 99 = NOT MODIFIED ON THE SERVER
# ANY OTHER = FAILED

# Fetch a url - the output file has the last modified timestamp of the server.
# On the next run, the file is downloaded only if it has changed on the server.
geturl() {
	local file="${1}" reference="${2}" url="${3}" ret= http_code=

	# copy the timestamp of the reference
	# to our file
	touch -r "${reference}" "${file}"

	test ${SILENT} -ne 1 && printf >&2 "${ipset}: downlading from '%s'... " "${url}"

	http_code=$(curl --connect-timeout 10 --max-time 300 --retry 0 --fail --compressed \
		--user-agent "FireHOL-Update-Ipsets/3.0" \
		--referer "https://github.com/ktsaou/firehol/blob/master/contrib/update-ipsets.sh" \
		-z "${reference}" -o "${file}" -s -L -R -w "%{http_code}" \
		"${url}")

	ret=$?

	test ${SILENT} -ne 1 && printf >&2 "HTTP/${http_code} "

	case "${ret}" in
		0)	if [ "${http_code}" = "304" -a ! "${file}" -nt "${reference}" ]
			then
				test ${SILENT} -ne 1 && echo >&2 "Not Modified"
				return 99
			fi
			test ${SILENT} -ne 1 && echo >&2 "OK"
			;;

		1)	test ${SILENT} -ne 1 && echo >&2 "Unsupported Protocol" ;;
		2)	test ${SILENT} -ne 1 && echo >&2 "Failed to initialize" ;;
		3)	test ${SILENT} -ne 1 && echo >&2 "Malformed URL" ;;
		5)	test ${SILENT} -ne 1 && echo >&2 "Can't resolve proxy" ;;
		6)	test ${SILENT} -ne 1 && echo >&2 "Can't resolve host" ;;
		7)	test ${SILENT} -ne 1 && echo >&2 "Failed to connect" ;;
		18)	test ${SILENT} -ne 1 && echo >&2 "Partial Transfer" ;;
		22)	test ${SILENT} -ne 1 && echo >&2 "HTTP Error" ;;
		23)	test ${SILENT} -ne 1 && echo >&2 "Cannot write local file" ;;
		26)	test ${SILENT} -ne 1 && echo >&2 "Read Error" ;;
		28)	test ${SILENT} -ne 1 && echo >&2 "Timeout" ;;
		35)	test ${SILENT} -ne 1 && echo >&2 "SSL Error" ;;
		47)	test ${SILENT} -ne 1 && echo >&2 "Too many redirects" ;;
		52)	test ${SILENT} -ne 1 && echo >&2 "Server did not reply anything" ;;
		55)	test ${SILENT} -ne 1 && echo >&2 "Failed sending network data" ;;
		56)	test ${SILENT} -ne 1 && echo >&2 "Failure in receiving network data" ;;
		61)	test ${SILENT} -ne 1 && echo >&2 "Unrecognized transfer encoding" ;;
		*) test ${SILENT} -ne 1 && echo >&2 "Error ${ret} returned by curl" ;;
	esac

	return ${ret}
}

# download a file if it has not been downloaded in the last $mins
DOWNLOAD_OK=0
DOWNLOAD_FAILED=1
DOWNLOAD_NOT_UPDATED=2
download_manager() {
	local 	ipset="${1}" mins="${2}" url="${3}" \
		install="${1}" \
		tmp= now= date= check=

	tmp=`mktemp "${RUN_DIR}/download-${ipset}-XXXXXXXXXX"` || return ${DOWNLOAD_FAILED}

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
	#if [ ! -s "${tmp}" ]
	#then
	#	# it is empty
	#	rm "${tmp}"
	#	syslog "${ipset}: empty file downloaded from url '${url}'."
	#	return ${DOWNLOAD_FAILED}
	#fi

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

# -----------------------------------------------------------------------------
# keep a cache of the data about all completed ipsets

declare -A IPSET_INFO=()
declare -A IPSET_SOURCE=()
declare -A IPSET_URL=()
declare -A IPSET_FILE=()
declare -A IPSET_IPV=()
declare -A IPSET_HASH=()
declare -A IPSET_MINS=()
declare -A IPSET_HISTORY_MINS=()
declare -A IPSET_ENTRIES=()
declare -A IPSET_IPS=()
declare -A IPSET_SOURCE_DATE=()
declare -A IPSET_PROCESSED_DATE=()
declare -A IPSET_CATEGORY=()
declare -A IPSET_MAINTAINER=()
declare -A IPSET_MAINTAINER_URL=()

# TODO - FIXME
#declare -A IPSET_PREFIXES=()
#declare -A IPSET_DOWNLOADER=()
#declare -A IPSET_DOWNLOADER_OPTIONS=()

cache_save() {
	#echo >&2 "Saving cache"
	declare -p \
		IPSET_INFO \
		IPSET_SOURCE \
		IPSET_URL \
		IPSET_FILE \
		IPSET_IPV \
		IPSET_HASH \
		IPSET_MINS \
		IPSET_HISTORY_MINS \
		IPSET_ENTRIES \
		IPSET_IPS \
		IPSET_SOURCE_DATE \
		IPSET_PROCESSED_DATE \
		IPSET_CATEGORY \
		IPSET_MAINTAINER \
		IPSET_MAINTAINER_URL \
		>"${BASE_DIR}/.cache"
}

if [ -f "${BASE_DIR}/.cache" ]
	then
	echo >&2 "Loading cache"
	source "${BASE_DIR}/.cache"
fi

cache_remove_ipset() {
	local ipset="${1}"

	echo >&2 "${ipset}: removing from cache"

	unset IPSET_INFO[${ipset}]
	unset IPSET_SOURCE[${ipset}]
	unset IPSET_URL[${ipset}]
	unset IPSET_FILE[${ipset}]
	unset IPSET_IPV[${ipset}]
	unset IPSET_HASH[${ipset}]
	unset IPSET_MINS[${ipset}]
	unset IPSET_HISTORY_MINS[${ipset}]
	unset IPSET_ENTRIES[${ipset}]
	unset IPSET_IPS[${ipset}]
	unset IPSET_SOURCE_DATE[${ipset}]
	unset IPSET_PROCESSED_DATE[${ipset}]
	unset IPSET_CATEGORY[${ipset}]
	unset IPSET_MAINTAINER[${ipset}]
	unset IPSET_MAINTAINER_URL[${ipset}]

	cache_save
}

ipset_json() {
	local ipset="${1}" geolite2= ipdeny= comparison= info=

	if [ -f "${RUN_DIR}/${ipset}_geolite2_country.json" ]
		then
		geolite2="${ipset}_geolite2_country.json"
	fi

	if [ -f "${RUN_DIR}/${ipset}_ipdeny_country.json" ]
		then
		ipdeny="${ipset}_ipdeny_country.json"
	fi

	if [ -f "${RUN_DIR}/${ipset}_comparison.json" ]
		then
		comparison="${ipset}_comparison.json"
	fi

	info="${IPSET_INFO[${ipset}]}"
	info=$(echo "${info}" | sed "s/)/)\n/g" | sed "s|\[\(.*\)\](\(.*\))|<a href=\"\2\">\1</a>|g" | tr "\n" " ") 
	info="${info//\"/\\\"}"

	cat <<EOFJSON
{
	"name": "${ipset}",
	"entries": ${IPSET_ENTRIES[${ipset}]},
	"ips": ${IPSET_IPS[${ipset}]},
	"ipv": "${IPSET_IPV[${ipset}]}",
	"hash": "${IPSET_HASH[${ipset}]}",
	"frequency": ${IPSET_MINS[${ipset}]},
	"aggregation": ${IPSET_HISTORY_MINS[${ipset}]},
	"updated": ${IPSET_SOURCE_DATE[${ipset}]}000,
	"processed": ${IPSET_PROCESSED_DATE[${ipset}]}000,
	"category": "${IPSET_CATEGORY[${ipset}]}",
	"maintainer": "${IPSET_MAINTAINER[${ipset}]}",
	"maintainer_url": "${IPSET_MAINTAINER_URL[${ipset}]}",
	"info": "${info}",
	"source": "${IPSET_URL[${ipset}]}",
	"file": "${IPSET_FILE[${ipset}]}",
	"history": "${ipset}_history.csv",
	"geolite2": "${geolite2}",
	"ipdeny": "${ipdeny}",
	"comparison": "${comparison}"
}
EOFJSON
}

# array to store hourly retention of past IPs
declare -a RETENTION_HISTOGRAM=()

# array to store hourly age of currently listed IPs
declare -a RETENTION_HISTOGRAM_REST=()

# the timestamp we started monitoring this ipset
declare RETENTION_HISTOGRAM_STARTED=

# if set to 0, the ipset has been completely refreshed
# i.e. all IPs have been removed / recycled at least once
declare RETENTION_HISTOGRAM_INCOMPLETE=1

# should only be called from retention_detect()
# because it needs the RETENTION_HISTOGRAM array loaded
retention_print() {
	local ipset="${1}"

	printf "{\n	\"ipset\": \"${ipset}\",\n	\"started\": ${RETENTION_HISTOGRAM_STARTED}000,\n	\"updated\": ${IPSET_SOURCE_DATE[${ipset}]}000,\n	\"incomplete\": ${RETENTION_HISTOGRAM_INCOMPLETE},\n"

	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: calculating retention hours..."
	local x= hours= ips= sum=0 pad="\n\t\t\t"
	for x in "${!RETENTION_HISTOGRAM[@]}"
	do
		(( sum += ${RETENTION_HISTOGRAM[${x}]} ))
		hours="${hours}${pad}${x}"
		ips="${ips}${pad}${RETENTION_HISTOGRAM[${x}]}"
		pad=",\n\t\t\t"
	done
	printf "	\"past\": {\n		\"hours\": [ ${hours} ],\n		\"ips\": [ ${ips} ],\n		\"total\": ${sum}\n	},\n"

	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: calculating current hours..."
	local x= hours= ips= sum=0 pad="\n\t\t\t"
	for x in "${!RETENTION_HISTOGRAM_REST[@]}"
	do
		(( sum += ${RETENTION_HISTOGRAM_REST[${x}]} ))
		hours="${hours}${pad}${x}"
		ips="${ips}${pad}${RETENTION_HISTOGRAM_REST[${x}]}"
		pad=",\n\t\t\t"
	done
	printf "	\"current\": {\n		\"hours\": [ ${hours} ],\n		\"ips\": [ ${ips} ],\n		\"total\": ${sum}\n	}\n}\n"
}

retention_detect() {
	local ipset="${1}"

	# can we do it?
	[ -z "${IPSET_FILE[${ipset}]}" -o -z "${CACHE_DIR}" -o ! -d "${CACHE_DIR}" ] && return 1

	# load the ipset retention histogram
	RETENTION_HISTOGRAM=()
	RETENTION_HISTOGRAM_REST=()
	RETENTION_HISTOGRAM_STARTED=
	RETENTION_HISTOGRAM_INCOMPLETE=1
	if [ -f "${CACHE_DIR}/${ipset}/histogram" ]
		then
		source "${CACHE_DIR}/${ipset}/histogram"
	fi

	ndate=$(date -r "${IPSET_FILE[${ipset}]}" +%s)

	printf >&2 " ${ipset}:"

	# create the cache directory for this ipset
	if [ ! -d "${CACHE_DIR}/${ipset}" ]
		then
		mkdir -p "${CACHE_DIR}/${ipset}" || return 2
	fi

	if [ ! -d "${CACHE_DIR}/${ipset}/new" ]
		then
		mkdir -p "${CACHE_DIR}/${ipset}/new" || return 2
	fi

	if [ ! -f "${CACHE_DIR}/${ipset}/latest" ]
		then
		# we don't have an older version
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${CACHE_DIR}/${ipset}/latest: first time - assuming start from empty"
		touch -r "${IPSET_FILE[${ipset}]}" "${CACHE_DIR}/${ipset}/latest"

		RETENTION_HISTOGRAM_STARTED="${IPSET_SOURCE_DATE[${ipset}]}"

	elif [ ! "${IPSET_FILE[${ipset}]}" -nt "${CACHE_DIR}/${ipset}/latest" ]
		# the new file is older than the latest, return
		then
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${CACHE_DIR}/${ipset}/latest: source file is not newer"
		retention_print "${ipset}"
		return 0
	fi

	if [ -f "${CACHE_DIR}/${ipset}/new/${ndate}" ]
		then
		# we already have a file for this date, return
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${CACHE_DIR}/${ipset}/new/${ndate}: already exists"
		retention_print "${ipset}"
		return 0
	fi

	# find the new ips in this set
	"${IPRANGE_CMD}" "${IPSET_FILE[${ipset}]}" --exclude-next "${CACHE_DIR}/${ipset}/latest" --print-binary >"${CACHE_DIR}/${ipset}/new/${ndate}"
	touch -r "${IPSET_FILE[${ipset}]}" "${CACHE_DIR}/${ipset}/new/${ndate}"

	if [ ! -s "${CACHE_DIR}/${ipset}/new/${ndate}" ]
		then
		# there are no new IPs included
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${CACHE_DIR}/${ipset}/new/${ndate}: nothing new in this"
		rm "${CACHE_DIR}/${ipset}/new/${ndate}"
	fi

	# ok keep it
	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: keeping it..."
	"${IPRANGE_CMD}" "${IPSET_FILE[${ipset}]}" --print-binary >"${CACHE_DIR}/${ipset}/latest"
	touch -r "${IPSET_FILE[${ipset}]}" "${CACHE_DIR}/${ipset}/latest"

	if [ ! -f "${CACHE_DIR}/${ipset}/retention.csv" ]
		then
		echo "date_removed,date_added,hours,ips" >"${CACHE_DIR}/${ipset}/retention.csv"
	fi

	# empty the remaining IPs counters
	# they will be re-calculated below
	RETENTION_HISTOGRAM_REST=()
	RETENTION_HISTOGRAM_INCOMPLETE=0

	local x=
	for x in $(ls "${CACHE_DIR}/${ipset}/new"/*)
	do
		printf >&2 "."

		# find how many hours have passed
		local odate="${x/*\//}"
		local hours=$[ (ndate + 1800 - odate) / 3600 ]
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${x}: ${hours} hours have passed"

		[ ${odate} -le ${RETENTION_HISTOGRAM_STARTED} ] && RETENTION_HISTOGRAM_INCOMPLETE=1

		# are all the IPs of this file still the latest?
		"${IPRANGE_CMD}" --common "${x}" "${CACHE_DIR}/${ipset}/latest" --print-binary >"${x}.stillthere"
		"${IPRANGE_CMD}" "${x}" --exclude-next "${x}.stillthere" --print-binary >"${x}.removed"
		if [ -s "${x}.removed" ]
			then
			# no, something removed, find it
			local removed=$("${IPRANGE_CMD}" -C "${x}.removed")
			rm "${x}.removed"

			# these are the unique IPs removed
			removed="${removed/*,/}"
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${x}: ${removed} IPs removed"

			echo "${ndate},${odate},${hours},${removed}" >>"${CACHE_DIR}/${ipset}/retention.csv"

			# update the histogram
			# only if the date added is after the date we started
			[ ${odate} -gt ${RETENTION_HISTOGRAM_STARTED} ] && RETENTION_HISTOGRAM[${hours}]=$[ ${RETENTION_HISTOGRAM[${hours}]} + removed ]
		else
			# yes, nothing removed from this run
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${x}: nothing removed"
			rm "${x}.removed"
		fi

		# check if there is something still left
		if [ ! -s "${x}.stillthere" ]
			then
			# nothing left for this timestamp, remove files
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${x}: nothing left in this"
			rm "${x}" "${x}.stillthere"
		else
			# there is something left in it
			[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${x}: there is still something in it"
			touch -r "${x}" "${x}.stillthere"
			mv "${x}.stillthere" "${x}"
			local still="$("${IPRANGE_CMD}" -C "${x}")"
			still="${still/*,/}"
			RETENTION_HISTOGRAM_REST[${hours}]=$[ ${RETENTION_HISTOGRAM_REST[${hours}]} + still ]
		fi
	done

	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: cleaning up retention cache..."
	# cleanup empty slots in our arrays
	for x in "${!RETENTION_HISTOGRAM[@]}"
	do
		if [ $[ RETENTION_HISTOGRAM[${x}] ] -eq 0 ]
			then
			unset RETENTION_HISTOGRAM[${x}]
		fi
	done
	for x in "${!RETENTION_HISTOGRAM_REST[@]}"
	do
		if [ $[ RETENTION_HISTOGRAM_REST[${x}] ] -eq 0 ]
			then
			unset RETENTION_HISTOGRAM_REST[${x}]
		fi
	done

	# save the histogram
	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: saving retention cache..."
	declare -p RETENTION_HISTOGRAM_STARTED RETENTION_HISTOGRAM_INCOMPLETE RETENTION_HISTOGRAM RETENTION_HISTOGRAM_REST >"${CACHE_DIR}/${ipset}/histogram"

	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: printing retention..."
	retention_print "${ipset}"

	[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: printed retention histogram"
	return 0
}

params_sort() {
	local x=
	for x in "${@}"
	do
		echo "${x}"
	done | sort
}

update_web() {
	[ -z "${WEB_DIR}" -o ! -d "${WEB_DIR}" ] && return 1
	[ "${#UPDATED_SETS[@]}" -eq 0 -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && return 1

	local x= all=() geolite2_country=() ipdeny_country=() i= to_all=

	echo '<?xml version="1.0" encoding="UTF-8"?>' >${RUN_DIR}/sitemap.xml
	echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' >>${RUN_DIR}/sitemap.xml

	echo >&2
	printf >&2 "updating history... "
	for x in $(params_sort "${!IPSET_FILE[@]}")
	do
		# remove deleted files
		if [ ! -f "${IPSET_FILE[$x]}" ]
			then
			echo >&2 "${x}: file ${IPSET_FILE[$x]} not found - removing it from cache"
			cache_remove_ipset "${x}"

			continue
		fi

		if [ ! -z "${CACHE_DIR}" ]
			then
			if [ ! -d "${CACHE_DIR}/${x}" ]
				then
				mkdir -p "${CACHE_DIR}/${x}"
			fi

			# copy the history from the old location to CACHE_DIR
			if [ -f "${WEB_DIR}/${x}_history.csv" -a ! -f "${CACHE_DIR}/${x}/history.csv" ]
				then
				cp "${WEB_DIR}/${x}_history.csv" "${CACHE_DIR}/${x}/history.csv"
			fi

			# update the history CSV files
			if [ ! -z "${UPDATED_SETS[${x}]}" -o ! -f "${CACHE_DIR}/${x}/history.csv" ]
				then
				if [ ! -f "${CACHE_DIR}/${x}/history.csv" ]
					then
					echo "DateTime,Entries,UniqueIPs" >"${CACHE_DIR}/${x}/history.csv"
					# touch "${CACHE_DIR}/${x}/history.csv"
					chmod 0644 "${CACHE_DIR}/${x}/history.csv"
				fi
				printf " ${x}"
				echo >>"${CACHE_DIR}/${x}/history.csv" "$(date -r "${IPSET_SOURCE[${x}]}" +%s),${IPSET_ENTRIES[${x}]},${IPSET_IPS[${x}]}"
				
				echo >"${WEB_DIR}/${x}_history.csv" "DateTime,Entries,UniqueIPs"
				tail -n 1000 "${CACHE_DIR}/${x}/history.csv" | grep -v "^DateTime" >>"${WEB_DIR}/${x}_history.csv"
			fi
		fi

		to_all=1

		# prepare the parameters for iprange to compare the sets
		if [[ "${IPSET_FILE[$x]}" =~ ^geolite2.* ]]
			then
			to_all=0
			case "${x}" in
				country_*)		i=${x/country_/} ;;
				continent_*)	i= ;;
				anonymous)		to_all=1; i= ;;
				satellite)		to_all=1; i= ;;
				*)				i= ;;
			esac
			[ ! -z "${i}" ] && geolite2_country=("${geolite2_country[@]}" "${IPSET_FILE[$x]}" "as" "${i^^}")
		elif [[ "${IPSET_FILE[$x]}" =~ ^ipdeny_country.* ]]
			then
			to_all=0
			case "${x}" in
				id_country_*)	i=${x/id_country_/} ;;
				id_continent_*)	i= ;;
				*)				i= ;;
			esac
			[ ! -z "${i}" ] && ipdeny_country=("${ipdeny_country[@]}" "${IPSET_FILE[$x]}" "as" "${i^^}")
		fi

		if [ ${to_all} -eq 1 ]
			then
			all=("${all[@]}" "${IPSET_FILE[$x]}" "as" "${x}")

			if [ ! -f "${RUN_DIR}/all-ipsets.json" ]
				then
				printf >"${RUN_DIR}/all-ipsets.json" "[\n	\"${x}\""
			else
				printf >>"${RUN_DIR}/all-ipsets.json" ",\n	\"${x}\""
			fi

cat >>"${RUN_DIR}/sitemap.xml" <<EOFSITEMAP
	<url>
		<loc>${WEB_URL}${x}</loc>
		<lastmod>$(date -I)</lastmod>
		<changefreq>always</changefreq>
	</url>
EOFSITEMAP

		fi
	done
	printf >>"${RUN_DIR}/all-ipsets.json" "\n]\n"
	cp "${RUN_DIR}/all-ipsets.json" "${WEB_DIR}/"
	echo '</urlset>' >>"${RUN_DIR}/sitemap.xml"
	cp "${RUN_DIR}/sitemap.xml" "${WEB_DIR}/"
	echo >&2

	printf >&2 "comparing ipsets... "
	"${IPRANGE_CMD}" --compare "${all[@]}" |\
		sort |\
		while IFS="," read name1 name2 entries1 entries2 ips1 ips2 combined common
		do
			if [ ${common} -gt 0 ]
				then
				if [ ! -f "${RUN_DIR}/${name1}_comparison.json" ]
					then
					printf >"${RUN_DIR}/${name1}_comparison.json" "[\n"
				else
					printf >>"${RUN_DIR}/${name1}_comparison.json" ",\n"
				fi
				printf >>"${RUN_DIR}/${name1}_comparison.json" "	{\n		\"name\": \"${name2}\",\n		\"ips\": ${ips2},\n		\"common\": ${common}\n	}"

				if [ ! -f "${RUN_DIR}/${name2}_comparison.json" ]
					then
					printf >"${RUN_DIR}/${name2}_comparison.json" "[\n"
				else
					printf >>"${RUN_DIR}/${name2}_comparison.json" ",\n"
				fi
				printf >>"${RUN_DIR}/${name2}_comparison.json" "	{\n		\"name\": \"${name1}\",\n		\"ips\": ${ips1},\n		\"common\": ${common}\n	}"
			fi
		done
	echo >&2
	for x in $(find "${RUN_DIR}" -name \*_comparison.json)
	do
		printf "\n]\n" >>${x}
		cp "${x}" "${WEB_DIR}/"
	done

	printf >&2 "comparing geolite2 country... "
	"${IPRANGE_CMD}" "${all[@]}" --compare-next "${geolite2_country[@]}" |\
		sort |\
		while IFS="," read name1 name2 entries1 entries2 ips1 ips2 combined common
		do
			if [ ${common} -gt 0 ]
				then
				if [ ! -f "${RUN_DIR}/${name1}_geolite2_country.json" ]
					then
					printf "[\n" >"${RUN_DIR}/${name1}_geolite2_country.json"
				else
					printf ",\n" >>"${RUN_DIR}/${name1}_geolite2_country.json"
				fi

				printf "	{\n		\"code\": \"${name2}\",\n		\"value\": ${common}\n	}" >>"${RUN_DIR}/${name1}_geolite2_country.json"
			fi
		done
	echo >&2
	for x in $(find "${RUN_DIR}" -name \*_geolite2_country.json)
	do
		printf "\n]\n" >>${x}
		cp "${x}" "${WEB_DIR}/"
	done

	printf >&2 "comparing ipdeny country... "
	"${IPRANGE_CMD}" "${all[@]}" --compare-next "${ipdeny_country[@]}" |\
		sort |\
		while IFS="," read name1 name2 entries1 entries2 ips1 ips2 combined common
		do
			if [ ${common} -gt 0 ]
				then
				if [ ! -f "${RUN_DIR}/${name1}_ipdeny_country.json" ]
					then
					printf "[\n" >"${RUN_DIR}/${name1}_ipdeny_country.json"
				else
					printf ",\n" >>"${RUN_DIR}/${name1}_ipdeny_country.json"
				fi

				printf "	{\n		\"code\": \"${name2}\",\n		\"value\": ${common}\n	}" >>"${RUN_DIR}/${name1}_ipdeny_country.json"
			fi
		done
	echo >&2
	for x in $(find "${RUN_DIR}" -name \*_ipdeny_country.json)
	do
		printf "\n]\n" >>${x}
		cp "${x}" "${WEB_DIR}/"
	done

	printf >&2 "generating javascript info... "
	for x in "${!IPSET_FILE[@]}"
	do
		[ -z "${UPDATED_SETS[${x}]}" -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && continue

		ipset_json "${x}" >"${WEB_DIR}/${x}.json"
	done
	echo >&2

	printf >&2 "generating retention histogram... "
	for x in "${!IPSET_FILE[@]}"
	do
		[ -z "${UPDATED_SETS[${x}]}" -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && continue
		[[ "${IPSET_FILE[$x]}" =~ ^geolite2.* ]] && continue
		[[ "${IPSET_FILE[$x]}" =~ ^ipdeny.* ]] && continue

		retention_detect "${x}" >"${RUN_DIR}/${x}_retention.json" || rm "${RUN_DIR}/${x}_retention.json"
	done
	cp "${RUN_DIR}"/*_retention.json "${WEB_DIR}/"
	echo >&2

	chown ${WEB_OWNER} "${WEB_DIR}"/*
	chmod 0644 "${WEB_DIR}"/*

	if [ ${PUSH_TO_GIT} -eq 1 ]
		then
		cd "${WEB_DIR}" || return 1
		git add *.json *.csv *.xml
		git commit -a -m "$(date -u) update"
		git push origin gh-pages
		cd "${BASE_DIR}" || exit 1
	fi
}

ipset_apply_counter=0
ipset_apply() {
	local ipset="${1}" ipv="${2}" hash="${3}" file="${4}" entries= tmpname= opts= ret= ips=

	if [ ${IPSETS_APPLY} -eq 0 ]
		then
		echo >&2 -e "${ipset}: ${COLOR_BGYELLOW}${COLOR_BLACK}${COLOR_BOLD} SAVED ${COLOR_RESET} I am not allowed to talk to the kernel."
		return 0
	fi

	ipset_apply_counter=$[ipset_apply_counter + 1]
	tmpname="tmp-$$-${RANDOM}-${ipset_apply_counter}"

	if [ "${ipv}" = "ipv4" ]
		then
		if [ -z "${sets[$ipset]}" ]
		then
			echo >&2 -e "${ipset}: ${COLOR_BGYELLOW}${COLOR_BLACK}${COLOR_BOLD} SAVED ${COLOR_RESET} no need to load ipset in kernel"
			# ipset --create ${ipset} "${hash}hash" || return 1
			return 0
		fi

		if [ "${hash}" = "net" ]
			then
			"${IPRANGE_CMD}" "${file}" \
				--ipset-reduce ${IPSET_REDUCE_FACTOR} \
				--ipset-reduce-entries ${IPSET_REDUCE_ENTRIES} \
				--print-prefix "-A ${tmpname} " >"${RUN_DIR}/${tmpname}"
			ret=$?
		elif [ "${hash}" = "ip" ]
			then
			"${IPRANGE_CMD}" -1 "${file}" --print-prefix "-A ${tmpname} " >"${RUN_DIR}/${tmpname}"
			ret=$?
		fi

		if [ ${ret} -ne 0 ]
			then
			echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} iprange failed ${COLOR_RESET}"
			rm "${RUN_DIR}/${tmpname}"
			return 1
		fi

		entries=$(wc -l <"${RUN_DIR}/${tmpname}")
		ips=$(iprange -C "${file}")
		ips=${ips/*,/}

		# this is needed for older versions of ipset
		echo "COMMIT" >>"${RUN_DIR}/${tmpname}"

		echo >&2 "${ipset}: loading to kernel (to temporary ipset)..."

		opts=
		if [ ${entries} -gt 65536 ]
			then
			opts="maxelem ${entries}"
		fi

		ipset create "${tmpname}" ${hash}hash ${opts}
		if [ $? -ne 0 ]
			then
			echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} failed to create temporary ipset ${tmpname} ${COLOR_RESET}"
			rm "${RUN_DIR}/${tmpname}"
			return 1
		fi

		ipset --flush "${tmpname}"
		ipset --restore <"${RUN_DIR}/${tmpname}"
		ret=$?
		rm "${RUN_DIR}/${tmpname}"

		if [ ${ret} -ne 0 ]
			then
			echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} failed to restore ipset from ${tmpname} ${COLOR_RESET}"
			ipset --destroy "${tmpname}"
			return 1
		fi

		echo >&2 "${ipset}: swapping temporary ipset to production..."
		ipset --swap "${tmpname}" "${ipset}"
		ret=$?
		ipset --destroy "${tmpname}"
		if [ $? -ne 0 ]
			then
			echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} failed to destroy temporary ipset ${COLOR_RESET}"
			return 1
		fi

		if [ $ret -ne 0 ]
			then
			echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} failed to swap temporary ipset ${tmpname} ${COLOR_RESET}"
			return 1
		fi

		echo >&2 -e "${ipset}: ${COLOR_BGGREEN}${COLOR_BLACK}${COLOR_BOLD} LOADED ${COLOR_RESET} (${entries} entries, ${ips} unique IPs)"
	else
		echo >&2 -e "${ipset}: ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} CANNOT HANDLE THIS TYPE OF IPSET YET ${COLOR_RESET}"
		return 1
	fi

	return 0
}


# -----------------------------------------------------------------------------
# finalize() is called when a successful download and convertion completes
# to update the ipset in the kernel and possibly commit it to git
finalize() {
	local ipset="${1}" tmp="${2}" setinfo="${3}" src="${4}" dst="${5}" mins="${6}" history_mins="${7}" ipv="${8}" type="${9}" hash="${10}" url="${11}" category="${12}" info="${13}" maintainer="${14}" maintainer_url="${15}"

	# check
	if [ -z "${info}" ]
		then
		echo >&2 "${ipset}: INTERNAL ERROR (finalize): no info supplied"
		info="${category}"
	fi

	# make sure the new file is optimized
	if [ "${hash}" == "ip" ]
		then
		"${IPRANGE_CMD}" -1 "${tmp}" >"${tmp}.final"
	else
		"${IPRANGE_CMD}" "${tmp}" >"${tmp}.final"
	fi
	mv "${tmp}.final" "${tmp}"

	# make sure the old file is optimized
	if [ -f "${dst}" ]
		then
		if [ "${hash}" == "ip" ]
			then
			"${IPRANGE_CMD}" -1 "${dst}" >"${tmp}.old"
		else
			"${IPRANGE_CMD}" "${dst}" >"${tmp}.old"
		fi
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
		test ${SILENT} -ne 1 && echo >&2 "${ipset}: touching ${dst} from ${src}."
		touch -r "${src}" "${dst}"

		check_file_too_old "${ipset}" "${dst}"
		return 0
	fi
	rm "${tmp}.old"

	# calculate how many entries/IPs are in it
	local ipset_opts=
	local entries=$("${IPRANGE_CMD}" -C "${tmp}")
	local ips=${entries/*,/}
	local entries=${entries/,*/}

	ipset_apply ${ipset} ${ipv} ${hash} ${tmp}
	if [ $? -ne 0 ]
	then
		if [ ! -z "${ERRORS_DIR}" -a -d "${ERRORS_DIR}" ]
		then
			mv "${tmp}" "${ERRORS_DIR}/${ipset}.${hash}set"
			syslog "${ipset}: failed to update ipset (error file left for you as '${ERRORS_DIR}/${ipset}.${hash}set')."
		else
			rm "${tmp}"
			syslog "${ipset}: failed to update ipset."
		fi
		check_file_too_old "${ipset}" "${dst}"
		return 1
	fi

	local quantity="${ips} unique IPs"
	[ "${hash}" = "net" ] && quantity="${entries} subnets, ${ips} unique IPs"

	IPSET_FILE[${ipset}]="${dst}"
	IPSET_IPV[${ipset}]="${ipv}"
	IPSET_HASH[${ipset}]="${hash}"
	IPSET_MINS[${ipset}]="${mins}"
	IPSET_HISTORY_MINS[${ipset}]="${history_mins}"
	IPSET_INFO[${ipset}]="${info}"
	IPSET_ENTRIES[${ipset}]="${entries}"
	IPSET_IPS[${ipset}]="${ips}"
	IPSET_URL[${ipset}]="${url}"
	IPSET_SOURCE[${ipset}]="${src}"
	IPSET_SOURCE_DATE[${ipset}]=$(date -r "${src}" +%s)
	IPSET_PROCESSED_DATE[${ipset}]=$(date +%s)
	IPSET_CATEGORY[${ipset}]="${category}"
	IPSET_MAINTAINER[${ipset}]="${maintainer}"
	IPSET_MAINTAINER_URL[${ipset}]="${maintainer_url}"

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
# Category        : ${category}
#
# Maintainer      : ${maintainer}
# Maintainer URL  : ${maintainer_url}
#
# Generated by FireHOL's update-ipsets.sh
#
EOFHEADER

	cat "${tmp}" >>"${tmp}.wh"
	rm "${tmp}"
	touch -r "${src}" "${tmp}.wh"
	mv "${tmp}.wh" "${dst}" || return 1

	UPDATED_SETS[${ipset}]="${dst}"
	local dir="`dirname "${dst}"`"
	UPDATED_DIRS[${dir}]="${dir}"

	if [ -d .git ]
	then
		echo >"${setinfo}" "[${ipset}](${WEB_URL}${ipset})|${info}|${ipv} hash:${hash}|${quantity}|`if [ ! -z "${url}" ]; then echo "updated every $(mins_to_text ${mins}) from [this link](${url})"; fi`"
		check_git_committed "${dst}"
	fi

	cache_save

	return 0
}

# -----------------------------------------------------------------------------

update() {
	local 	ipset="${1}" mins="${2}" history_mins="${3}" ipv="${4}" type="${5}" url="${6}" processor="${7-cat}" category="${8}" info="${9}" maintainer="${10}" maintainer_url="${11}"
		install="${1}" tmp= error=0 now= date= pre_filter="cat" post_filter="cat" post_filter2="cat" filter="cat"
	shift 11

	# check
	if [ -z "${info}" ]
		then
		echo >&2 "${ipset}: INTERNAL ERROR (update): no info supplied"
		info="${category}"
	fi

	case "${ipv}" in
		ipv4)
			post_filter2="filter_invalid4"
			case "${type}" in
				ip|ips)		# output is single ipv4 IPs without /
						hash="ip"
						type="ip"
						pre_filter="cat"
						filter="filter_ip4"	# without this, ipset_uniq4 may output huge number of IPs
						post_filter="ipset_uniq4"
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
			echo >&2 "${ipset}: IPv6 is not yet supported."
			return 1

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
		if [ ${ENABLE_ALL} -eq 1 ]
			then
			touch -t 0001010000 "${BASE_DIR}/${install}.source" || return 1
		else
			[ -d .git ] && echo >"${install}.setinfo" "${ipset}|${info}|${ipv} hash:${hash}|disabled|`if [ ! -z "${url}" ]; then echo "updated every $(mins_to_text ${mins}) from [this link](${url})"; fi`"
			echo >&2 "${ipset}: is disabled, to enable it run: touch -t 0001010000 '${BASE_DIR}/${install}.source'"
			return 1
		fi
	fi

	if [ ! -z "${url}" ]
	then
		# download it
		download_manager "${ipset}" "${mins}" "${url}"
		if [ $? -eq ${DOWNLOAD_FAILED} -o \( $? -eq ${DOWNLOAD_NOT_UPDATED} -a -f "${install}.${hash}net" \) ]
			then
			if [ ! -s "${install}.source" ]; then return 1
			elif [ -f "${install}.${hash}set" ]
			then
				check_file_too_old "${ipset}" "${install}.${hash}set"
				return 1
			fi
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
		update "${ipset}_ip" "${mins}" "${history_mins}" "${ipv}" ip  "" "${processor}" "${category}" "${info}" "${maintainer}" "${maintainer_url}"
		update "${ipset}_net" "${mins}" "${history_mins}" "${ipv}" net "" "${processor}" "${category}" "${info}" "${maintainer}" "${maintainer_url}"
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
	tmp=`mktemp "${RUN_DIR}/${install}.tmp-XXXXXXXXXX"` || return 1
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

	local h= hmax=-1
	[ "${history_mins}" = "0" ] && history_mins=
	
	if [ ! -z "${history_mins}" ]
		then
		history_keep "${ipset}" "${tmp}"
	fi

	for h in 0 ${history_mins/,/ }
	do
		local hmins=${h/\/*/}
		hmins=$[ hmins + 0 ]
		local htag=

		if [ ${hmins} -gt 0 ]
			then
			if [ ${hmins} -gt ${hmax} ]
				then
				hmax=${hmins}
			fi

			if [ ${hmins} -ge $[24 * 60] ]
				then
				local hd=$[ hmins / (24 * 60) ]
				htag="_${hd}d"

				if [ $[ hd * (24 * 60) ] -ne ${hmins} ]
					then
					htag="${htag}$[hmins - (hd * 1440)]h"
				fi
			else
				htag="_$[hmins/60]h"
			fi

			history_get "${ipset}" "${hmins}" >"${tmp}${htag}"

			cp "${tmp}${htag}" "${BASE_DIR}/${install}${htag}.source"
			touch -r "${BASE_DIR}/${install}.source" "${BASE_DIR}/${install}${htag}.source"
		fi

		finalize "${ipset}${htag}" "${tmp}${htag}" "${install}${htag}.setinfo" "${install}${htag}.source" "${install}${htag}.${hash}set" "${mins}" "${hmins}" "${ipv}" "${type}" "${hash}" "${url}" "${category}" "${info}" "${maintainer}" "${maintainer_url}"
 	done

	if [ ! -z "${history_mins}" ]
		then
		history_cleanup "${ipset}" "${hmax}"
	fi

	return $?
}


# -----------------------------------------------------------------------------
# IPSETS RENAMING

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

	if [ -d "${HISTORY_DIR}/${old}" -a ! -d "${HISTORY_DIR}/${new}" ]
		then
		echo "Renaming ${HISTORY_DIR}/${old} ${HISTORY_DIR}/${new}"
		mv "${HISTORY_DIR}/${old}" "${HISTORY_DIR}/${new}"
	fi

	[ -f ".${old}.lastchecked" -a ! -f ".${new}.lastchecked" ] && mv ".${old}.lastchecked" ".${new}.lastchecked"

	if [ ! -z "${CACHE_DIR}" -a -d "${CACHE_DIR}" -a -d "${CACHE_DIR}/${old}" -a ! -d "${CACHE_DIR}/${new}" ]
		then
		mv -f "${CACHE_DIR}/${old}" "${CACHE_DIR}/${new}" || exit 1
	fi

	if [ -d "${WEB_DIR}" ]
		then
		for x in _comparison.json _geolite2_country.json _history.csv _ipdeny_country.json retention.json .json
		do
			if [ -f "${WEB_DIR}/${old}${x}" -a ! -f "${WEB_DIR}/${new}${x}" ]
				then
				mv -f "${WEB_DIR}/${old}${x}" "${WEB_DIR}/${new}${x}"
			fi
		done
	fi

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
# all these should be used with pipes

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


# -----------------------------------------------------------------------------
# XML DOM FILTERS
# all these are to be used in pipes
# they extract IPs from the XML

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

# convert netmask to CIDR format
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

# trim leading, trailing, double spacing, empty lines
trim() {
	sed -e "s/[\t ]\+/ /g" -e "s/^ \+//g" -e "s/ \+$//g" |\
		grep -v "^$"
}

# remove comments starting with ';' and trim()
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

# remove comments starting with '#' and trim()
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

# ungzip and remove comments
gz_remove_comments() {
	gzip -dc | remove_comments
}

# convert snort rules to a list of IPs
snort_alert_rules_to_ipv4() {
	remove_comments |\
		grep ^alert |\
		sed -e "s|^alert .* \[\([0-9/,\.]\+\)\] any -> \$HOME_NET any .*$|\1|g" -e "s|,|\n|g" |\
		grep -v ^alert
}

# extract IPs from PIX access list deny rules
pix_deny_rules_to_ipv4() {
	remove_comments |\
		grep ^access-list |\
		sed -e "s|^access-list .* deny ip \([0-9\.]\+\) \([0-9\.]\+\) any$|\1/\2|g" \
		    -e "s|^access-list .* deny ip host \([0-9\.]\+\) any$|\1|g" |\
		grep -v ^access-list |\
		subnet_to_bitmask
}

# extract CIDRs from the dshield table format
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

# unzip the first file in the zip and convert comma to new lines
unzip_and_split_csv() {
	funzip | tr ",\r" "\n\n"
}

# unzip the first file in the zip
unzip_and_extract() {
	funzip
}

# extract IPs from the P2P blocklist
p2p_gz() {
	gzip -dc |\
		cut -d ':' -f 2 |\
		egrep "^${IP4_MATCH}-${IP4_MATCH}$" |\
		ipv4_range_to_cidr
}

# extract only the lines starting with Proxy from the P2P blocklist
p2p_gz_proxy() {
	gzip -dc |\
		grep "^Proxy" |\
		cut -d ':' -f 2 |\
		egrep "^${IP4_MATCH}-${IP4_MATCH}$" |\
		ipv4_range_to_cidr
}

# get the first column from the csv
csv_comma_first_column() {
	grep "^[0-9]" |\
		cut -d ',' -f 1
}

# get the second word from the compressed file
gz_second_word() {
	gzip -dc |\
		tr '\r' '\n' |\
		cut -d ' ' -f 2
}

# extract IPs for the proxyrss file
gz_proxyrss() {
	gzip -dc |\
		remove_comments |\
		cut -d ':' -f 1
}

# extract IPs from the maxmind proxy fraud page
parse_maxmind_proxy_fraud() {
	grep "a href=\"proxy/" |\
		cut -d '>' -f 2 |\
		cut -d '<' -f 1
}

geolite2_country() {
	local ipset="geolite2_country" type="" hash="net" ipv="ipv4" \
		mins=$[24 * 60 * 7] history_mins=0 \
		url="http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country-CSV.zip" \
		info="[MaxMind GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/)"

	if [ ! -f "${ipset}.source" ]
	then
		if [ ${ENABLE_ALL} -eq 1 ]
			then
			touch -t 0001010000 "${BASE_DIR}/${ipset}.source" || return 1
		else
			echo >&2 "${ipset}: is disabled, to enable it run: touch -t 0001010000 '${BASE_DIR}/${ipset}.source'"
			return 1
		fi
	fi

	# download it
	download_manager "${ipset}" "${mins}" "${url}"
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

	if [ -d "${BASE}/.git" ]
		then
		git checkout ${ipset}/README-EDIT.md
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
			filter_all4 |\
			aggregate4 |\
			filter_invalid4 >"${x/.source.tmp/.source}"

		touch -r "${ipset}.source" "${x/.source.tmp/.source}"
		rm "${x}"

		local i=${x/.source.tmp/}
		i=${i/${ipset}.tmp\//}

		local info2="`cat "${x}.info"` -- ${info}"

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${type}" "${hash}" "${url}" "geolocation" "${info2}" "MaxMind.com" "http://www.maxmind.com/"
	done

	if [ -d .git ]
	then
		# generate a setinfo for the home page
		echo >"${ipset}.setinfo" "[${ipset}](https://github.com/ktsaou/blocklist-ipsets/tree/master/geolite2_country)|[MaxMind GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/) databases are free IP geolocation databases comparable to, but less accurate than, MaxMind’s GeoIP2 databases. They include IPs per country, IPs per continent, IPs used by anonymous services (VPNs, Proxies, etc) and Satellite Providers.|ipv4 hash:net|All the world|`if [ ! -z "${url}" ]; then echo "updated every $(mins_to_text ${mins}) from [this link](${url})"; fi`"
	fi

	# remove the temporary dir
	rm -rf "${ipset}.tmp"

	return 0
}

declare -A IPDENY_COUNTRY_NAMES='([as]="American Samoa" [ge]="Georgia" [ar]="Argentina" [gd]="Grenada" [dm]="Dominica" [kp]="North Korea" [rw]="Rwanda" [gg]="Guernsey" [qa]="Qatar" [ni]="Nicaragua" [do]="Dominican Republic" [gf]="French Guiana" [ru]="Russia" [kr]="Republic of Korea" [aw]="Aruba" [ga]="Gabon" [rs]="Serbia" [no]="Norway" [nl]="Netherlands" [au]="Australia" [kw]="Kuwait" [dj]="Djibouti" [at]="Austria" [gb]="United Kingdom" [dk]="Denmark" [ky]="Cayman Islands" [gm]="Gambia" [ug]="Uganda" [gl]="Greenland" [de]="Germany" [nc]="New Caledonia" [az]="Azerbaijan" [hr]="Croatia" [na]="Namibia" [gn]="Guinea" [kz]="Kazakhstan" [et]="Ethiopia" [ht]="Haiti" [es]="Spain" [gi]="Gibraltar" [nf]="Norfolk Island" [ng]="Nigeria" [gh]="Ghana" [hu]="Hungary" [er]="Eritrea" [ua]="Ukraine" [ne]="Niger" [yt]="Mayotte" [gu]="Guam" [nz]="New Zealand" [om]="Oman" [gt]="Guatemala" [gw]="Guinea-Bissau" [hk]="Hong Kong" [re]="Réunion" [ag]="Antigua and Barbuda" [gq]="Equatorial Guinea" [ke]="Kenya" [gp]="Guadeloupe" [uz]="Uzbekistan" [af]="Afghanistan" [hn]="Honduras" [uy]="Uruguay" [dz]="Algeria" [kg]="Kyrgyzstan" [ae]="United Arab Emirates" [ad]="Andorra" [gr]="Greece" [ki]="Kiribati" [nr]="Nauru" [eg]="Egypt" [kh]="Cambodia" [ro]="Romania" [ai]="Anguilla" [np]="Nepal" [ee]="Estonia" [us]="United States" [ec]="Ecuador" [gy]="Guyana" [ao]="Angola" [km]="Comoros" [am]="Armenia" [ye]="Yemen" [nu]="Niue" [kn]="Saint Kitts and Nevis" [al]="Albania" [si]="Slovenia" [fr]="France" [bf]="Burkina Faso" [mw]="Malawi" [cy]="Cyprus" [vc]="Saint Vincent and the Grenadines" [mv]="Maldives" [bg]="Bulgaria" [pr]="Puerto Rico" [sk]="Slovak Republic" [bd]="Bangladesh" [mu]="Mauritius" [ps]="Palestine" [va]="Vatican City" [cz]="Czech Republic" [be]="Belgium" [mt]="Malta" [zm]="Zambia" [ms]="Montserrat" [bb]="Barbados" [sm]="San Marino" [pt]="Portugal" [io]="British Indian Ocean Territory" [vg]="British Virgin Islands" [sl]="Sierra Leone" [mr]="Mauritania" [la]="Laos" [in]="India" [ws]="Samoa" [mq]="Martinique" [im]="Isle of Man" [lb]="Lebanon" [tz]="Tanzania" [so]="Somalia" [mp]="Northern Mariana Islands" [ve]="Venezuela" [lc]="Saint Lucia" [ba]="Bosnia and Herzegovina" [sn]="Senegal" [pw]="Palau" [il]="Israel" [tt]="Trinidad and Tobago" [bn]="Brunei" [sa]="Saudi Arabia" [bo]="Bolivia" [py]="Paraguay" [bl]="Saint-Barthélemy" [tv]="Tuvalu" [sc]="Seychelles" [vi]="U.S. Virgin Islands" [cr]="Costa Rica" [bm]="Bermuda" [sb]="Solomon Islands" [tw]="Taiwan" [cu]="Cuba" [se]="Sweden" [bj]="Benin" [vn]="Vietnam" [li]="Liechtenstein" [mz]="Mozambique" [sd]="Sudan" [cw]="Curaçao" [ie]="Ireland" [sg]="Singapore" [jp]="Japan" [my]="Malaysia" [tr]="Turkey" [bh]="Bahrain" [mx]="Mexico" [cv]="Cape Verde" [id]="Indonesia" [lk]="Sri Lanka" [za]="South Africa" [bi]="Burundi" [ci]="Ivory Coast" [tl]="East Timor" [mg]="Madagascar" [lt]="Republic of Lithuania" [sy]="Syria" [sx]="Sint Maarten" [pa]="Panama" [mf]="Saint Martin" [lu]="Luxembourg" [ch]="Switzerland" [tm]="Turkmenistan" [bw]="Botswana" [jo]="Hashemite Kingdom of Jordan" [me]="Montenegro" [tn]="Tunisia" [ck]="Cook Islands" [bt]="Bhutan" [lv]="Latvia" [wf]="Wallis and Futuna" [to]="Tonga" [jm]="Jamaica" [sz]="Swaziland" [md]="Republic of Moldova" [br]="Brazil" [mc]="Monaco" [cm]="Cameroon" [th]="Thailand" [pe]="Peru" [cl]="Chile" [bs]="Bahamas" [pf]="French Polynesia" [co]="Colombia" [ma]="Morocco" [lr]="Liberia" [tj]="Tajikistan" [bq]="Bonaire, Sint Eustatius, and Saba" [tk]="Tokelau" [vu]="Vanuatu" [pg]="Papua New Guinea" [cn]="China" [ls]="Lesotho" [ca]="Canada" [is]="Iceland" [td]="Chad" [fj]="Fiji" [mo]="Macao" [ph]="Philippines" [mn]="Mongolia" [zw]="Zimbabwe" [ir]="Iran" [ss]="South Sudan" [mm]="Myanmar (Burma)" [iq]="Iraq" [sr]="Suriname" [je]="Jersey" [ml]="Mali" [tg]="Togo" [pk]="Pakistan" [fi]="Finland" [bz]="Belize" [pl]="Poland" [mk]="Former Yugoslav Republic of Macedonia" [pm]="Saint Pierre and Miquelon" [fo]="Faroe Islands" [st]="São Tomé and Príncipe" [ly]="Libya" [cd]="Congo" [cg]="Republic of the Congo" [sv]="El Salvador" [tc]="Turks and Caicos Islands" [it]="Italy" [fm]="Federated States of Micronesia" [mh]="Marshall Islands" [by]="Belarus" [cf]="Central African Republic" )'
declare -A IPDENY_COUNTRY_CONTINENTS='([as]="oc" [ge]="as" [ar]="sa" [gd]="na" [dm]="na" [kp]="as" [rw]="af" [gg]="eu" [qa]="as" [ni]="na" [do]="na" [gf]="sa" [ru]="eu" [kr]="as" [aw]="na" [ga]="af" [rs]="eu" [no]="eu" [nl]="eu" [au]="oc" [kw]="as" [dj]="af" [at]="eu" [gb]="eu" [dk]="eu" [ky]="na" [gm]="af" [ug]="af" [gl]="na" [de]="eu" [nc]="oc" [az]="as" [hr]="eu" [na]="af" [gn]="af" [kz]="as" [et]="af" [ht]="na" [es]="eu" [gi]="eu" [nf]="oc" [ng]="af" [gh]="af" [hu]="eu" [er]="af" [ua]="eu" [ne]="af" [yt]="af" [gu]="oc" [nz]="oc" [om]="as" [gt]="na" [gw]="af" [hk]="as" [re]="af" [ag]="na" [gq]="af" [ke]="af" [gp]="na" [uz]="as" [af]="as" [hn]="na" [uy]="sa" [dz]="af" [kg]="as" [ae]="as" [ad]="eu" [gr]="eu" [ki]="oc" [nr]="oc" [eg]="af" [kh]="as" [ro]="eu" [ai]="na" [np]="as" [ee]="eu" [us]="na" [ec]="sa" [gy]="sa" [ao]="af" [km]="af" [am]="as" [ye]="as" [nu]="oc" [kn]="na" [al]="eu" [si]="eu" [fr]="eu" [bf]="af" [mw]="af" [cy]="eu" [vc]="na" [mv]="as" [bg]="eu" [pr]="na" [sk]="eu" [bd]="as" [mu]="af" [ps]="as" [va]="eu" [cz]="eu" [be]="eu" [mt]="eu" [zm]="af" [ms]="na" [bb]="na" [sm]="eu" [pt]="eu" [io]="as" [vg]="na" [sl]="af" [mr]="af" [la]="as" [in]="as" [ws]="oc" [mq]="na" [im]="eu" [lb]="as" [tz]="af" [so]="af" [mp]="oc" [ve]="sa" [lc]="na" [ba]="eu" [sn]="af" [pw]="oc" [il]="as" [tt]="na" [bn]="as" [sa]="as" [bo]="sa" [py]="sa" [bl]="na" [tv]="oc" [sc]="af" [vi]="na" [cr]="na" [bm]="na" [sb]="oc" [tw]="as" [cu]="na" [se]="eu" [bj]="af" [vn]="as" [li]="eu" [mz]="af" [sd]="af" [cw]="na" [ie]="eu" [sg]="as" [jp]="as" [my]="as" [tr]="as" [bh]="as" [mx]="na" [cv]="af" [id]="as" [lk]="as" [za]="af" [bi]="af" [ci]="af" [tl]="oc" [mg]="af" [lt]="eu" [sy]="as" [sx]="na" [pa]="na" [mf]="na" [lu]="eu" [ch]="eu" [tm]="as" [bw]="af" [jo]="as" [me]="eu" [tn]="af" [ck]="oc" [bt]="as" [lv]="eu" [wf]="oc" [to]="oc" [jm]="na" [sz]="af" [md]="eu" [br]="sa" [mc]="eu" [cm]="af" [th]="as" [pe]="sa" [cl]="sa" [bs]="na" [pf]="oc" [co]="sa" [ma]="af" [lr]="af" [tj]="as" [bq]="na" [tk]="oc" [vu]="oc" [pg]="oc" [cn]="as" [ls]="af" [ca]="na" [is]="eu" [td]="af" [fj]="oc" [mo]="as" [ph]="as" [mn]="as" [zw]="af" [ir]="as" [ss]="af" [mm]="as" [iq]="as" [sr]="sa" [je]="eu" [ml]="af" [tg]="af" [pk]="as" [fi]="eu" [bz]="na" [pl]="eu" [mk]="eu" [pm]="na" [fo]="eu" [st]="af" [ly]="af" [cd]="af" [cg]="af" [sv]="na" [tc]="na" [it]="eu" [fm]="oc" [mh]="oc" [by]="eu" [cf]="af" )'
declare -A IPDENY_COUNTRIES=()
declare -A IPDENY_CONTINENTS=()
ipdeny_country() {
	local ipset="ipdeny_country" type="" hash="net" ipv="ipv4" \
		mins=$[24 * 60 * 1] history_mins=0 \
		url="http://www.ipdeny.com/ipblocks/data/countries/all-zones.tar.gz" \
		info="[IPDeny.com](http://www.ipdeny.com/)"

	if [ ! -f "${ipset}.source" ]
	then
		if [ ${ENABLE_ALL} -eq 1 ]
			then
			touch -t 0001010000 "${BASE_DIR}/${ipset}.source" || return 1
		else
			echo >&2 "${ipset}: is disabled, to enable it run: touch -t 0001010000 '${BASE_DIR}/${ipset}.source'"
			return 1
		fi
	fi

	# download it
	download_manager "${ipset}" "${mins}" "${url}"
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

	# extract it - in a subshell to do it in the tmp dir
	( cd "${BASE_DIR}/${ipset}.tmp" && tar -zxpf "${BASE_DIR}/${ipset}.source" )

	# move them inside the tmp, and fix continents
	local x=
	for x in $(find "${ipset}.tmp/" -type f -a -name \*.zone)
	do
		x=${x/*\//}
		x=${x/.zone/}
		IPDENY_COUNTRIES[${x}]="1"

		if [ ! -z "${IPDENY_COUNTRY_CONTINENTS[${x}]}" ]
			then
			[ ! -f "${ipset}.tmp/id_continent_${IPDENY_COUNTRY_CONTINENTS[${x}]}.source.tmp.info" ] && printf "%s" "Continent ${IPDENY_COUNTRY_CONTINENTS[${x}]}, with countries: " >"${ipset}.tmp/id_continent_${IPDENY_COUNTRY_CONTINENTS[${x}]}.source.tmp.info"
			printf "%s" "${IPDENY_COUNTRY_NAMES[${x}]} (${x^^}), " >>"${ipset}.tmp/id_continent_${IPDENY_COUNTRY_CONTINENTS[${x}]}.source.tmp.info"
			cat "${ipset}.tmp/${x}.zone" >>"${ipset}.tmp/id_continent_${IPDENY_COUNTRY_CONTINENTS[${x}]}.source.tmp"
			IPDENY_CONTINENTS[${IPDENY_COUNTRY_CONTINENTS[${x}]}]="1"
		else
			echo >&2 "${ipset}: I don't know the continent of country ${x}."
		fi

		printf "%s" "${IPDENY_COUNTRY_NAMES[${x}]} (${x^^})" >"${ipset}.tmp/id_country_${x}.source.tmp.info"
		mv "${ipset}.tmp/${x}.zone" "${ipset}.tmp/id_country_${x}.source.tmp"
	done

	echo >&2 "${ipset}: Aggregating country and continent netsets..."
	for x in ${ipset}.tmp/*.source.tmp
	do
		cat "${x}" |\
			filter_all4 |\
			aggregate4 |\
			filter_invalid4 >"${x/.source.tmp/.source}"

		touch -r "${ipset}.source" "${x/.source.tmp/.source}"
		rm "${x}"

		local i=${x/.source.tmp/}
		i=${i/${ipset}.tmp\//}

		local info2="`cat "${x}.info"` -- ${info}"

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${type}" "${hash}" "${url}" "geolocation" "${info2}" "IPDeny.com" "http://www.ipdeny.com/"
	done

	if [ -d .git ]
	then
		# generate a setinfo for the home page
		echo >"${ipset}.setinfo" "[${ipset}](https://github.com/ktsaou/blocklist-ipsets/tree/master/ipdeny_country)|[IPDeny.com](http://www.ipdeny.com/) geolocation database|ipv4 hash:net|All the world|updated every `mins_to_text ${mins}` from [this link](${url})"
	fi

	# remove the temporary dir
	rm -rf "${ipset}.tmp"

	return 0
}


# -----------------------------------------------------------------------------
# MERGE two or more ipsets

merge() {
	local to="${1}" category="${2}" info="${3}" included=()
	shift 3

	if [ ! -f "${to}.source" ]
		then
		if [ ${ENABLE_ALL} -eq 1 ]
			then
			touch -t 0001010000 "${BASE_DIR}/${to}.source" || return 1
		else
			echo >&2 "${to}: is disabled. To enable it run: touch -t 0001010000 ${BASE_DIR}/${to}.source"
			return 1
		fi
	fi

	local -a files=()
	local found_updated=0 max_date=""
	for x in "${@}"
	do
		if [ ! -z "${IPSET_FILE[${x}]}" -a -f "${IPSET_FILE[${x}]}" ]
			then

			# find the file with max date
			[ -z "${max_date}" ] && max_date="${IPSET_FILE[${x}]}"
			[ "${IPSET_FILE[${x}]}" -nt "${max_date}" ] && max_date="${IPSET_FILE[${x}]}"

			files=("${files[@]}" "${IPSET_FILE[${x}]}")
			included=("${included[@]}" "${x}")

			if [ ! -z "${UPDATED_SETS[${x}]}" -o "${IPSET_FILE[${x}]}" -nt "${to}.source" ]
				then
				found_updated=$[ found_updated + 1 ]
			fi
		else
			echo >&2 "${to}: will be generated without '${x}' - enable it to be included"
			# touch -t 0001010000 "${BASE_DIR}/${x}.source"
		fi
	done

	if [ -z "${files[*]}" ]
		then
		echo >&2 "${to}: no files available to merge."
		return 1
	fi

	if [ ${found_updated} -eq 0 -a -f "${to}.netset" ]
		then
		echo >&2 "${to}: source files have not been updated."
		return 1
	fi

	"${IPRANGE_CMD}" "${files[@]}" >"${RUN_DIR}/${to}.tmp"
	touch -r "${max_date}" "${to}.tmp" "${to}.source"
	finalize "${to}" "${RUN_DIR}/${to}.tmp" "${to}.setinfo" "${to}.source" "${to}.netset" "1" "0" "ipv4" "" "net" "" "${category}" "${info} (includes: ${included[*]})" "FireHOL" "${WEB_URL}${to}"
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
#   ${BASE_DIR} (/etc/firehol/ipsets)

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
# IPDeny.com

ipdeny_country


# -----------------------------------------------------------------------------
# www.openbl.org

update openbl $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) default blacklist (currently it is the same with 90 days). OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications" \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_1d $[1*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_1days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 24 hours IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_7d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_7days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 7 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_30d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_30days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 30 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_60d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_60days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 60 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_90d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_90days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 90 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_180d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_180days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 180 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_360d $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_360days.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last 360 days IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"

update openbl_all $[4*60] 0 ipv4 ip \
	"http://www.openbl.org/lists/base_all.txt" \
	remove_comments \
	"attacks" \
	"[OpenBL.org](http://www.openbl.org/) last all IPs.  OpenBL.org is detecting, logging and reporting various types of internet abuse. Currently they monitor ports 21 (FTP), 22 (SSH), 23 (TELNET), 25 (SMTP), 110 (POP3), 143 (IMAP), 587 (Submission), 993 (IMAPS) and 995 (POP3S) for bruteforce login attacks as well as scans on ports 80 (HTTP) and 443 (HTTPS) for vulnerable installations of phpMyAdmin and other web applications." \
	"OpenBL.org" "http://www.openbl.org/"


# -----------------------------------------------------------------------------
# www.dshield.org
# https://www.dshield.org/xml.html

# Top 20 attackers (networks) by www.dshield.org
update dshield 15 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 both \
	"http://feeds.dshield.org/block.txt" \
	dshield_parser \
	"attacks" \
	"[DShield.org](https://dshield.org/) top 20 attacking class C (/24) subnets over the last three days" \
	"DShield.org" "https://dshield.org/"

# -----------------------------------------------------------------------------
# TOR lists
# TOR is not necessary hostile, you may need this just for sensitive services.

# https://www.dan.me.uk/tornodes
# This contains a full TOR nodelist (no more than 30 minutes old).
# The page has download limit that does not allow download in less than 30 min.
update dm_tor 30 0 ipv4 ip \
	"https://www.dan.me.uk/torlist/" \
	remove_comments \
	"anonymizers" \
	"[dan.me.uk](https://www.dan.me.uk) dynamic list of TOR nodes" \
	"dan.me.uk" "https://www.dan.me.uk/"

update et_tor $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/emerging-tor.rules" \
	snort_alert_rules_to_ipv4 \
	"anonymizers" \
	"[EmergingThreats.net TOR list](http://doc.emergingthreats.net/bin/view/Main/TorRules) of TOR network IPs" \
	"Emerging Threats" "http://www.emergingthreats.net/"

update bm_tor 30 0 ipv4 ip \
	"https://torstatus.blutmagie.de/ip_list_all.php/Tor_ip_list_ALL.csv" \
	remove_comments \
	"anonymizers" \
	"[torstatus.blutmagie.de](https://torstatus.blutmagie.de) list of all TOR network servers" \
	"torstatus.blutmagie.de" "https://torstatus.blutmagie.de/"

torproject_exits() { grep "^ExitAddress " | cut -d ' ' -f 2; }
update tor_exits 30 0 ipv4 ip \
	"https://check.torproject.org/exit-addresses" \
	torproject_exits \
	"anonymizers" \
	"[TorProject.org](https://www.torproject.org) list of all current TOR exit points (TorDNSEL)" \
	"TorProject.org" "https://www.torproject.org/"

# -----------------------------------------------------------------------------
# EmergingThreats

# http://doc.emergingthreats.net/bin/view/Main/CompromisedHost
# Includes: openbl, bruteforceblocker and sidreporter
update et_compromised $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/blockrules/compromised-ips.txt" \
	remove_comments \
	"attacks" \
	"[EmergingThreats.net compromised hosts](http://doc.emergingthreats.net/bin/view/Main/CompromisedHost)" \
	"Emerging Threats" "http://www.emergingthreats.net/"

# Command & Control servers by shadowserver.org
update et_botcc $[12*60] 0 ipv4 ip \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-CC.rules" \
	pix_deny_rules_to_ipv4 \
	"malware" \
	"[EmergingThreats.net Command and Control IPs](http://doc.emergingthreats.net/bin/view/Main/BotCC) These IPs are updates every 24 hours and should be considered VERY highly reliable indications that a host is communicating with a known and active Bot or Malware command and control server - (although they say this includes abuse.ch trackers, it does not - most probably it is the shadowserver.org C&C list)" \
	"Emerging Threats" "http://www.emergingthreats.net/"

# This appears to be the SPAMHAUS DROP list
update et_spamhaus $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DROP.rules" \
	pix_deny_rules_to_ipv4 \
	"attacks" \
	"[EmergingThreats.net](http://www.emergingthreats.net/) spamhaus blocklist" \
	"Emerging Threats" "http://www.emergingthreats.net/"

# Top 20 attackers by www.dshield.org
# disabled - have direct feed above
update et_dshield $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-PIX-DSHIELD.rules" \
	pix_deny_rules_to_ipv4 \
	"attacks" \
	"[EmergingThreats.net](http://www.emergingthreats.net/) dshield blocklist" \
	"Emerging Threats" "http://www.emergingthreats.net/"

# includes spamhaus and dshield
update et_block $[12*60] 0 ipv4 both \
	"http://rules.emergingthreats.net/fwrules/emerging-Block-IPs.txt" \
	remove_comments \
	"attacks" \
	"[EmergingThreats.net](http://www.emergingthreats.net/) default blacklist (at the time of writing includes spamhaus DROP, dshield and abuse.ch trackers, which are available separately too - prefer to use the direct ipsets instead of this, they seem to lag a bit in updates)" \
	"Emerging Threats" "http://www.emergingthreats.net/"


# -----------------------------------------------------------------------------
# Spamhaus
# http://www.spamhaus.org

# http://www.spamhaus.org/drop/
# These guys say that this list should be dropped at tier-1 ISPs globaly!
update spamhaus_drop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/drop.txt" \
	remove_comments_semi_colon \
	"attacks" \
	"[Spamhaus.org](http://www.spamhaus.org) DROP list (according to their site this list should be dropped at tier-1 ISPs globaly)" \
	"Spamhaus" "http://www.spamhaus.org/"

# extended DROP (EDROP) list.
# Should be used together with their DROP list.
update spamhaus_edrop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/edrop.txt" \
	remove_comments_semi_colon \
	"attacks" \
	"[Spamhaus.org](http://www.spamhaus.org) EDROP (extended matches that should be used with DROP)" \
	"Spamhaus" "http://www.spamhaus.org/"


# -----------------------------------------------------------------------------
# blocklist.de
# http://www.blocklist.de/en/export.html

# All IP addresses that have attacked one of their servers in the
# last 48 hours. Updated every 30 minutes.
# They also have lists of service specific attacks (ssh, apache, sip, etc).
update blocklist_de 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/all.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) IPs that have been detected by fail2ban in the last 48 hours" \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_ssh 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/ssh.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service SSH." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_mail 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/mail.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service Mail, Postfix." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_apache 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/apache.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the service Apache, Apache-DDOS, RFI-Attacks." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_imap 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/imap.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours for attacks on the Service imap, sasl, pop3, etc." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_ftp 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/ftp.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours for attacks on the Service FTP." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_sip 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/sip.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses that tried to login in a SIP, VOIP or Asterisk Server and are included in the IPs list from infiltrated.net" \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_bots 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/bots.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IP addresses which have been reported within the last 48 hours as having run attacks on the RFI-Attacks, REG-Bots, IRC-Bots or BadBots (BadBots = he has posted a Spam-Comment on a open Forum or Wiki)." \
	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_strongips 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/strongips.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IPs which are older then 2 month and have more then 5.000 attacks." \
	"Blocklist.de" "https://www.blocklist.de/"

#update blocklist_de_ircbot 30 0 ipv4 ip \
#	"http://lists.blocklist.de/lists/ircbot.txt" \
#	remove_comments \
#	"attacks" \
#	"[Blocklist.de](https://www.blocklist.de/) (no information supplied)" \
#	"Blocklist.de" "https://www.blocklist.de/"

update blocklist_de_bruteforce 30 0 ipv4 ip \
	"http://lists.blocklist.de/lists/bruteforcelogin.txt" \
	remove_comments \
	"attacks" \
	"[Blocklist.de](https://www.blocklist.de/) All IPs which attacks Joomlas, Wordpress and other Web-Logins with Brute-Force Logins." \
	"Blocklist.de" "https://www.blocklist.de/"


# -----------------------------------------------------------------------------
# Zeus trojan
# https://zeustracker.abuse.ch/blocklist.php
# by abuse.ch

# This blocklists only includes IPv4 addresses that are used by the ZeuS trojan.
update zeus_badips 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=badips" \
	remove_comments \
	"malware" \
	"[Abuse.ch Zeus tracker](https://zeustracker.abuse.ch) badips includes IPv4 addresses that are used by the ZeuS trojan. It is the recommened blocklist if you want to block only ZeuS IPs. It excludes IP addresses that ZeuS Tracker believes to be hijacked (level 2) or belong to a free web hosting provider (level 3). Hence the false postive rate should be much lower compared to the standard ZeuS IP blocklist." \
	"Abuse.ch" "https://zeustracker.abuse.ch/"

# This blocklist contains the same data as the ZeuS IP blocklist (BadIPs)
# but with the slight difference that it doesn't exclude hijacked websites
# (level 2) and free web hosting providers (level 3).
update zeus 30 0 ipv4 ip \
	"https://zeustracker.abuse.ch/blocklist.php?download=ipblocklist" \
	remove_comments \
	"malware" \
	"[Abuse.ch Zeus tracker](https://zeustracker.abuse.ch) standard, contains the same data as the ZeuS IP blocklist (zeus_badips) but with the slight difference that it doesn't exclude hijacked websites (level 2) and free web hosting providers (level 3). This means that this blocklist contains all IPv4 addresses associated with ZeuS C&Cs which are currently being tracked by ZeuS Tracker. Hence this blocklist will likely cause some false positives." \
	"Abuse.ch" "https://zeustracker.abuse.ch/"


# -----------------------------------------------------------------------------
# Palevo worm
# https://palevotracker.abuse.ch/blocklists.php
# by abuse.ch

# includes IP addresses which are being used as botnet C&C for the Palevo crimeware
update palevo 30 0 ipv4 ip \
	"https://palevotracker.abuse.ch/blocklists.php?download=ipblocklist" \
	remove_comments \
	"malware" \
	"[Abuse.ch Palevo tracker](https://palevotracker.abuse.ch) worm includes IPs which are being used as botnet C&C for the Palevo crimeware" \
	"Abuse.ch" "https://palevotracker.abuse.ch/"


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
	"malware" \
	"[Abuse.ch Feodo tracker](https://feodotracker.abuse.ch) trojan includes IPs which are being used by Feodo (also known as Cridex or Bugat) which commits ebanking fraud" \
	"Abuse.ch" "https://palevotracker.abuse.ch/"


# -----------------------------------------------------------------------------
# SSLBL
# https://sslbl.abuse.ch/
# by abuse.ch

# IPs with "bad" SSL certificates identified by abuse.ch to be associated with malware or botnet activities
update sslbl 30 0 ipv4 ip \
	"https://sslbl.abuse.ch/blacklist/sslipblacklist.csv" \
	csv_comma_first_column \
	"malware" \
	"[Abuse.ch SSL Blacklist](https://sslbl.abuse.ch/) bad SSL traffic related to malware or botnet activities" \
	"Abuse.ch" "https://sslbl.abuse.ch/"


# -----------------------------------------------------------------------------
# infiltrated.net
# http://www.infiltrated.net/blacklisted

#update infiltrated $[12*60] 0 ipv4 ip \
#	"http://www.infiltrated.net/blacklisted" \
#	remove_comments \
#	"attacks" \
#	"[infiltrated.net](http://www.infiltrated.net) (this list seems to be updated frequently, but we found no information about it)" \
#	"infiltrated.net" "http://www.infiltrated.net/"

# -----------------------------------------------------------------------------
# malc0de
# http://malc0de.com

# updated daily and populated with the last 30 days of malicious IP addresses.
update malc0de $[24*60] 0 ipv4 ip \
	"http://malc0de.com/bl/IP_Blacklist.txt" \
	remove_comments \
	"attacks" \
	"[Malc0de.com](http://malc0de.com) malicious IPs of the last 30 days" \
	"Malc0de.com" "http://malc0de.com/"


# -----------------------------------------------------------------------------
# ASPROX
# http://atrack.h3x.eu/

parse_asprox() { sed -e "s|<div class=code>|\n|g" -e "s|</div>|\n|g" | trim | egrep "^${IP4_MATCH}$"; }

# updated daily and populated with the last 30 days of malicious IP addresses.
update asprox_c2 $[24*60] 0 ipv4 ip \
	"http://atrack.h3x.eu/c2" \
	parse_asprox \
	"malware" \
	"[h3x.eu](http://atrack.h3x.eu/) ASPROX Tracker - Asprox C&C Sites" \
	"h3x.eu" "http://atrack.h3x.eu/"


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
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) all IPs used by forum spammers, ever (normally you don't want to use this ipset, use the hourly one which includes last 24 hours IPs or the 7 days one)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# hourly update with IPs from the last 24 hours
update stopforumspam_1d 60 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_1.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers in the last 24 hours" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# daily update with IPs from the last 7 days
update stopforumspam_7d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_7.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 7 days)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# daily update with IPs from the last 30 days
update stopforumspam_30d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_30.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 30 days)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# daily update with IPs from the last 90 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_90d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_90.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 90 days)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# daily update with IPs from the last 180 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_180d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_180.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 180 days)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"

# daily update with IPs from the last 365 days
# you will have to add maxelem to ipset to fit it
update stopforumspam_365d $[24*60] 0 ipv4 ip \
	"http://www.stopforumspam.com/downloads/listed_ip_365.zip" \
	unzip_and_extract \
	"abuse" \
	"[StopForumSpam.com](http://www.stopforumspam.com) IPs used by forum spammers (last 365 days)" \
	"StopForumSpam.com" "http://www.stopforumspam.com/"


# -----------------------------------------------------------------------------
# sblam.com

update sblam $[24*60] 0 ipv4 ip \
	"http://sblam.com/blacklist.txt" \
	remove_comments \
	"abuse" \
	"[sblam.com](http://sblam.com) IPs used by web form spammers, during the last month" \
	"sblam.com" "http://sblam.com/"


# -----------------------------------------------------------------------------
# myip.ms

update myip $[24*60] 0 ipv4 ip \
	"http://www.myip.ms/files/blacklist/csf/latest_blacklist.txt" \
	remove_comments \
	"abuse" \
	"[myip.ms](http://www.myip.ms/info/about) IPs identified as web bots in the last 10 days, using several sites that require human action" \
	"myip.ms" "http://myip.ms/"


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
	"unroutable" \
	"[Team-Cymru.org](http://www.team-cymru.org) private and reserved addresses defined by RFC 1918, RFC 5735, and RFC 6598 and netblocks that have not been allocated to a regional internet registry" \
	"Team Cymru" "http://www.team-cymru.org/"


# http://www.team-cymru.org/bogon-reference.html
# Fullbogons are a larger set which also includes IP space that has been
# allocated to an RIR, but not assigned by that RIR to an actual ISP or other
# end-user.
update fullbogons $[24*60] 0 ipv4 both \
	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv4.txt" \
	remove_comments \
	"unroutable" \
	"[Team-Cymru.org](http://www.team-cymru.org) IP space that has been allocated to an RIR, but not assigned by that RIR to an actual ISP or other end-user" \
	"Team Cymru" "http://www.team-cymru.org/"

#update fullbogons6 $[24*60-10] ipv6 both \
#	"http://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt" \
#	remove_comments \
#	"unroutable" \
#	"Team-Cymru.org provided" \
#	"Team Cymru" "http://www.team-cymru.org/"


# -----------------------------------------------------------------------------
# Open Proxies from rosinstruments
# http://tools.rosinstrument.com/proxy/

update ri_web_proxies 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://tools.rosinstrument.com/proxy/l100.xml" \
	parse_rss_rosinstrument \
	"anonymizers" \
	"[rosinstrument.com](http://www.rosinstrument.com) open HTTP proxies (this list is composed using an RSS feed)" \
	"RosInstrument.com" "http://www.rosinstrument.com/"

update ri_connect_proxies 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://tools.rosinstrument.com/proxy/plab100.xml" \
	parse_rss_rosinstrument \
	"anonymizers" \
	"[rosinstrument.com](http://www.rosinstrument.com) open CONNECT proxies (this list is composed using an RSS feed)" \
	"RosInstrument.com" "http://www.rosinstrument.com/"


# -----------------------------------------------------------------------------
# Open Proxies from xroxy.com
# http://www.xroxy.com

update xroxy 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.xroxy.com/proxyrss.xml" \
	parse_rss_proxy \
	"anonymizers" \
	"[xroxy.com](http://www.xroxy.com) open proxies (this list is composed using an RSS feed)" \
	"Xroxy.com" "http://www.xroxy.com/"


# -----------------------------------------------------------------------------
# Open Proxies from proxz.com
# http://www.proxz.com/

update proxz 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.proxz.com/proxylists.xml" \
	parse_rss_proxy \
	"anonymizers" \
	"[proxz.com](http://www.proxz.com) open proxies (this list is composed using an RSS feed)" \
	"proxz.com" "http://www.proxz.com/"


# -----------------------------------------------------------------------------
# Open Proxies from proxyspy.net
# http://spys.ru/en/

parse_proxyspy() { remove_comments | cut -d ':' -f 1; }

update proxyspy 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://txt.proxyspy.net/proxy.txt" \
	parse_proxyspy \
	"anonymizers" \
	"[ProxySpy](http://spys.ru/en/) open proxies (updated hourly)" \
	"ProxySpy" "http://spys.ru/en/"


# -----------------------------------------------------------------------------
# Open Proxies from proxyrss.com
# http://www.proxyrss.com/

update proxyrss $[4*60] "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.proxyrss.com/proxylists/all.gz" \
	gz_proxyrss \
	"anonymizers" \
	"[proxyrss.com](http://www.proxyrss.com) open proxies syndicated from multiple sources." \
	"proxyrss.com" "http://www.proxyrss.com/"


# -----------------------------------------------------------------------------
# Anonymous Proxies
# https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list

update maxmind_proxy_fraud $[4*60] "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list" \
	parse_maxmind_proxy_fraud \
	"anonymizers" \
	"[MaxMind.com](https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list) list of anonymous proxy fraudelent IP addresses." \
	"MaxMind" "https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list"


# -----------------------------------------------------------------------------
# Project Honey Pot
# http://www.projecthoneypot.org/?rf=192670

update php_harvesters 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=h&rss=1" \
	parse_php_rss \
	"abuse" \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) harvesters (IPs that surf the internet looking for email addresses) (this list is composed using an RSS feed)" \
	"ProjectHoneypot.org" "http://www.projecthoneypot.org/"

update php_spammers 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=s&rss=1" \
	parse_php_rss \
	"abuse" \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) spam servers (IPs used by spammers to send messages) (this list is composed using an RSS feed)" \
	"ProjectHoneypot.org" "http://www.projecthoneypot.org/"

update php_bad 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=b&rss=1" \
	parse_php_rss \
	"abuse" \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) bad web hosts (this list is composed using an RSS feed)" \
	"ProjectHoneypot.org" "http://www.projecthoneypot.org/"

update php_commenters 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=c&rss=1" \
	parse_php_rss \
	"abuse" \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) comment spammers (this list is composed using an RSS feed)" \
	"ProjectHoneypot.org" "http://www.projecthoneypot.org/"

update php_dictionary 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" \
	parse_php_rss \
	"abuse" \
	"[projecthoneypot.org](http://www.projecthoneypot.org/?rf=192670) directory attackers (this list is composed using an RSS feed)" \
	"ProjectHoneypot.org" "http://www.projecthoneypot.org/"


# -----------------------------------------------------------------------------
# Malware Domain List
# All IPs should be considered dangerous

update malwaredomainlist $[12*60] 0 ipv4 ip \
	"http://www.malwaredomainlist.com/hostslist/ip.txt" \
	remove_comments \
	"malware" \
	"[malwaredomainlist.com](http://www.malwaredomainlist.com) list of malware active ip addresses" \
	"MalwareDomainList.com" "http://www.malwaredomainlist.com/"


# -----------------------------------------------------------------------------
# Alien Vault
# Alienvault IP Reputation Database

# IMPORTANT: THIS IS A BIG LIST
# you will have to add maxelem to ipset to fit it
update alienvault_reputation $[6*60] 0 ipv4 ip \
	"https://reputation.alienvault.com/reputation.generic" \
	remove_comments \
	"reputation" \
	"[AlienVault.com](https://www.alienvault.com/) IP reputation database" \
	"AlienVault" "https://www.alienvault.com/"


# -----------------------------------------------------------------------------
# Clean-MX
# Viruses

update cleanmx_viruses 30 0 ipv4 ip \
	"http://support.clean-mx.de/clean-mx/xmlviruses.php?sort=id%20desc&response=alive" \
	parse_xml_clean_mx \
	"malware" \
	"[Clean-MX.de](http://support.clean-mx.de/clean-mx/viruses.php) IPs with viruses" \
	"Clean-MX.de" "http://support.clean-mx.de/clean-mx/viruses.php"


# -----------------------------------------------------------------------------
# ImproWare
# http://antispam.imp.ch/

antispam_ips() { remove_comments | cut -d ' ' -f 2; }

update iw_spamlist 60 0 ipv4 ip \
	"http://antispam.imp.ch/spamlist" \
	antispam_ips \
	"spam" \
	"[ImproWare Antispam](http://antispam.imp.ch/) IPs sending spam, in the last 3 days" \
	"ImproWare Antispam" "http://antispam.imp.ch/"


update iw_wormlist 60 0 ipv4 ip \
	"http://antispam.imp.ch/wormlist" \
	antispam_ips \
	"spam" \
	"[ImproWare Antispam](http://antispam.imp.ch/) IPs sending emails with viruses or worms, in the last 3 days" \
	"ImproWare Antispam" "http://antispam.imp.ch/"


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
	"reputation" \
	"[CIArmy.com](http://ciarmy.com/) IPs with poor Rogue Packet score that have not yet been identified as malicious by the community" \
	"CINS Score" "http://ciarmy.com/"


# -----------------------------------------------------------------------------
# Bruteforce Blocker
# http://danger.rulez.sk/projects/bruteforceblocker/

update bruteforceblocker $[3*60] 0 ipv4 ip \
	"http://danger.rulez.sk/projects/bruteforceblocker/blist.php" \
	remove_comments \
	"attacks" \
	"[danger.rulez.sk bruteforceblocker](http://danger.rulez.sk/index.php/bruteforceblocker/) (fail2ban alternative for SSH on OpenBSD). This is an automatically generated list from users reporting failed authentication attempts. An IP seems to be included if 3 or more users report it. Its retention pocily seems 30 days." \
	"danger.rulez.sk" "http://danger.rulez.sk/index.php/bruteforceblocker/"


# -----------------------------------------------------------------------------
# Charles Haley
# http://charles.the-haleys.org/ssh_dico_attack_hdeny_format.php/hostsdeny.txt

haley_ssh() { cut -d ':' -f 2; }

update haley_ssh $[4*60] 0 ipv4 ip \
	"http://charles.the-haleys.org/ssh_dico_attack_hdeny_format.php/hostsdeny.txt" \
	haley_ssh \
	"attacks" \
	"[Charles Haley](http://charles.the-haleys.org) IPs launching SSH dictionary attacks." \
	"Charles Haley" "http://charles.the-haleys.org"


# -----------------------------------------------------------------------------
# Snort ipfilter
# http://labs.snort.org/feeds/ip-filter.blf

update snort_ipfilter $[12*60] 0 ipv4 ip \
	"http://labs.snort.org/feeds/ip-filter.blf" \
	remove_comments \
	"attacks" \
	"[labs.snort.org](https://labs.snort.org/) supplied IP blacklist (this list seems to be updated frequently, but we found no information about it)" \
	"Snort Labs" "https://labs.snort.org/"


# -----------------------------------------------------------------------------
# NiX Spam
# http://www.heise.de/ix/NiX-Spam-DNSBL-and-blacklist-for-download-499637.html

update nixspam 15 0 ipv4 ip \
	"http://www.dnsbl.manitu.net/download/nixspam-ip.dump.gz" \
	gz_second_word \
	"spam" \
	"[NiX Spam](http://www.heise.de/ix/NiX-Spam-DNSBL-and-blacklist-for-download-499637.html) IP addresses that sent spam in the last hour - automatically generated entries without distinguishing open proxies from relays, dialup gateways, and so on. All IPs are removed after 12 hours if there is no spam from there." \
	"NiX Spam" "http://www.heise.de/ix/NiX-Spam-DNSBL-and-blacklist-for-download-499637.html"


# -----------------------------------------------------------------------------
# VirBL
# http://virbl.bit.nl/

update virbl 60 0 ipv4 ip \
	"http://virbl.bit.nl/download/virbl.dnsbl.bit.nl.txt" \
	remove_comments \
	"spam" \
	"[VirBL](http://virbl.bit.nl/) is a project of which the idea was born during the RIPE-48 meeting. The plan was to get reports of virusscanning mailservers, and put the IP-addresses that were reported to send viruses on a blacklist." \
	"VirBL" "http://virbl.bit.nl/"


# -----------------------------------------------------------------------------
# AutoShun.org
# http://www.autoshun.org/

update shunlist $[4*60] 0 ipv4 ip \
	"http://www.autoshun.org/files/shunlist.csv" \
	csv_comma_first_column \
	"attacks" \
	"[AutoShun.org](http://autoshun.org/) IPs identified as hostile by correlating logs from distributed snort installations running the autoshun plugin" \
	"AutoShun" "http://autoshun.org/"


# -----------------------------------------------------------------------------
# VoIPBL.org
# http://www.voipbl.org/

update voipbl $[4*60] 0 ipv4 both \
	"http://www.voipbl.org/update/" \
	remove_comments \
	"attacks" \
	"[VoIPBL.org](http://www.voipbl.org/) a distributed VoIP blacklist that is aimed to protects against VoIP Fraud and minimizing abuse for network that have publicly accessible PBX's. Several algorithms, external sources and manual confirmation are used before they categorize something as an attack and determine the threat level." \
	"VoIPBL" "http://www.voipbl.org/"


# -----------------------------------------------------------------------------
# LashBack Unsubscribe Blacklist
# http://blacklist.lashback.com/
# (this is a big list, more than 500.000 IPs)

update lashback_ubl $[24*60] 0 ipv4 ip \
	"http://www.unsubscore.com/blacklist.txt" \
	remove_comments \
	"spam" \
	"[The LashBack UBL](http://blacklist.lashback.com/) The Unsubscribe Blacklist (UBL) is a real-time blacklist of IP addresses which are sending email to names harvested from suppression files (this is a big list, more than 500.000 IPs)" \
	"The LashBack UBL" "http://blacklist.lashback.com/"

# -----------------------------------------------------------------------------
# Dragon Research Group (DRG)
# HTTP report
# http://www.dragonresearchgroup.org/

dragon_column3() { remove_comments | cut -d '|' -f 3 | trim; }

DO_NOT_REDISTRIBUTE[dragon_http.netset]="1"
update dragon_http 60 0 ipv4 both \
	"http://www.dragonresearchgroup.org/insight/http-report.txt" \
	dragon_column3 \
	"attacks" \
	"[Dragon Research Group](http://www.dragonresearchgroup.org/) IPs that have been seen sending HTTP requests to Dragon Research Pods in the last 7 days. This report lists hosts that are highly suspicious and are likely conducting malicious HTTP attacks. LEGITIMATE SEARCH ENGINE BOTS MAY BE IN THIS LIST. This report is informational.  It is not a blacklist, but some operators may choose to use it to help protect their networks and hosts in the forms of automated reporting and mitigation services." \
	"Dragon Research Group (DRG)" "http://www.dragonresearchgroup.org/"

DO_NOT_REDISTRIBUTE[dragon_sshpauth.netset]="1"
update dragon_sshpauth 60 0 ipv4 both \
	"https://www.dragonresearchgroup.org/insight/sshpwauth.txt" \
	dragon_column3 \
	"attacks" \
	"[Dragon Research Group](http://www.dragonresearchgroup.org/) IP address that has been seen attempting to remotely login to a host using SSH password authentication, in the last 7 days. This report lists hosts that are highly suspicious and are likely conducting malicious SSH password authentication attacks." \
	"Dragon Research Group (DRG)" "http://www.dragonresearchgroup.org/"

DO_NOT_REDISTRIBUTE[dragon_vncprobe.netset]="1"
update dragon_vncprobe 60 0 ipv4 both \
	"https://www.dragonresearchgroup.org/insight/vncprobe.txt" \
	dragon_column3 \
	"attacks" \
	"[Dragon Research Group](http://www.dragonresearchgroup.org/) IP address that has been seen attempting to remotely connect to a host running the VNC application service, in the last 7 days. This report lists hosts that are highly suspicious and are likely conducting malicious VNC probes or VNC brute force attacks." \
	"Dragon Research Group (DRG)" "http://www.dragonresearchgroup.org/"


# -----------------------------------------------------------------------------
# Nothink.org

update nt_ssh_7d 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_ssh_week.txt" \
	remove_comments \
	"attacks" \
	"[NoThink](http://www.nothink.org/) Last 7 days SSH attacks" \
	"NoThink" "http://www.nothink.org/"

update nt_malware_irc 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_irc.txt" \
	remove_comments \
	"malware" \
	"[No Think](http://www.nothink.org/) Malware IRC" \
	"NoThink" "http://www.nothink.org/"

update nt_malware_http 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_http.txt" \
	remove_comments \
	"malware" \
	"[No Think](http://www.nothink.org/) Malware HTTP" \
	"NoThink" "http://www.nothink.org/"

update nt_malware_dns 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_dns.txt" \
	remove_comments \
	"malware" \
	"[No Think](http://www.nothink.org/) Malware DNS (the original list includes hostnames and domains, which are ignored)" \
	"NoThink" "http://www.nothink.org/"

# -----------------------------------------------------------------------------
# Bambenek Consulting
# http://osint.bambenekconsulting.com/feeds/

bambenek_filter() { remove_comments | cut -d ',' -f 1; }

update bambenek_c2 30 0 ipv4 ip \
	"http://osint.bambenekconsulting.com/feeds/c2-ipmasterlist.txt" \
	bambenek_filter \
	"malware" \
	"[Bambenek Consulting](http://osint.bambenekconsulting.com/feeds/) master feed of known, active and non-sinkholed C&Cs IP addresses" \
	"Bambenek Consulting" "http://osint.bambenekconsulting.com/feeds/"

for list in banjori bebloh cl cryptowall dircrypt dyre geodo hesperbot matsnu necurs p2pgoz pushdo pykspa qakbot ramnit ranbyus simda suppobox symmi tinba volatile
do
	update bambenek_${list} 30 0 ipv4 ip \
		"http://osint.bambenekconsulting.com/feeds/${list}-iplist.txt" \
		bambenek_filter \
		"malware" \
		"[Bambenek Consulting](http://osint.bambenekconsulting.com/feeds/) feed of current IPs of ${list} C&Cs with 90 minute lookback" \
		"Bambenek Consulting" "http://osint.bambenekconsulting.com/feeds/"
done


# -----------------------------------------------------------------------------
# BotScout
# http://botscout.com/

botscout_filter() {
	while read_xml_dom
	do
		[[ "${XML_ENTITY}" =~ ^a\ .*/ipcheck.htm\?ip=.* ]] && echo "${XML_CONTENT}"
	done
}

update botscout 30 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://botscout.com/last_caught_cache.htm" \
	botscout_filter \
	"abuse" \
	"[BotScout](http://botscout.com/) helps prevent automated web scripts, known as bots, from registering on forums, polluting databases, spreading spam, and abusing forms on web sites. They do this by tracking the names, IPs, and email addresses that bots use and logging them as unique signatures for future reference. They also provide a simple yet powerful API that you can use to test forms when they're submitted on your site. This list is composed of the most recently-caught bots." \
	"BotScout" "http://botscout.com/"

# -----------------------------------------------------------------------------
# GreenSnow
# https://greensnow.co/

update greensnow 30 0 ipv4 ip \
	"http://blocklist.greensnow.co/greensnow.txt" \
	remove_comments \
	"attacks" \
	"[GreenSnow](https://greensnow.co/) is a team harvesting a large number of IPs from different computers located around the world. GreenSnow is comparable with SpamHaus.org for attacks of any kind except for spam. Their list is updated automatically and you can withdraw at any time your IP address if it has been listed. Attacks / bruteforce that are monitored are: Scan Port, FTP, POP3, mod_security, IMAP, SMTP, SSH, cPanel, etc." \
	"GreenSnow" "https://greensnow.co/"


# -----------------------------------------------------------------------------
# BinaryDefense
# https://greensnow.co/

update bds_atif $[24*60] 0 ipv4 ip \
	"https://www.binarydefense.com/banlist.txt" \
	remove_comments \
	"reputation" \
	"[Binary Defense Systems Artillery Threat Intelligence Feed and Banlist Feed](https://www.binarydefense.com/banlist.txt)" \
	"Binary Defense Systems" "https://www.binarydefense.com/"


# -----------------------------------------------------------------------------
# iBlocklist
# https://www.iblocklist.com/lists.php
# http://bluetack.co.uk/forums/index.php?autocom=faq&CODE=02&qid=17

# open proxies and tor
# we only keep the proxies IPs (tor IPs are not parsed)
DO_NOT_REDISTRIBUTE[ib_bluetack_proxies.ipset]="1"
update ib_bluetack_proxies $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=xoebmbyexwuiogmbyprb&fileformat=p2p&archiveformat=gz" \
	p2p_gz_proxy \
	"anonymizers" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Open Proxies IPs list (without TOR)" \
	"iBlocklist" "https://www.iblocklist.com/"


# This list is a compilation of known malicious SPYWARE and ADWARE IP Address ranges.
# It is compiled from various sources, including other available Spyware Blacklists,
# HOSTS files, from research found at many of the top Anti-Spyware forums, logs of
# Spyware victims and also from the Malware Research Section here at Bluetack.
DO_NOT_REDISTRIBUTE[ib_bluetack_spyware.netset]="1"
update ib_bluetack_spyware $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=llvtlsjyoyiczbkjsxpf&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk known malicious SPYWARE and ADWARE IP Address ranges" \
	"iBlocklist" "https://www.iblocklist.com/"


# List of people who have been reported for bad deeds in p2p.
DO_NOT_REDISTRIBUTE[ib_bluetack_badpeers.ipset]="1"
update ib_bluetack_badpeers $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=cwworuawihqvocglcoss&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk IPs that have been reported for bad deeds in p2p" \
	"iBlocklist" "https://www.iblocklist.com/"


# Contains hijacked IP-Blocks and known IP-Blocks that are used to deliver Spam. 
# This list is a combination of lists with hijacked IP-Blocks 
# Hijacked IP space are IP blocks that are being used without permission by
# organizations that have no relation to original organization (or its legal
# successor) that received the IP block. In essence it's stealing of somebody
# else's IP resources
DO_NOT_REDISTRIBUTE[ib_bluetack_hijacked.netset]="1"
update ib_bluetack_hijacked $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=usrcshglbiilevmyfhse&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk hijacked IP-Blocks Hijacked IP space are IP blocks that are being used without permission" \
	"iBlocklist" "https://www.iblocklist.com/"


# IP addresses related to current web server hack and exploit attempts that have been
# logged by us or can be found in and cross referenced with other related IP databases.
# Malicious and other non search engine bots will also be listed here, along with anything
# we find that can have a negative impact on a website or webserver such as proxies being
# used for negative SEO hijacks, unauthorised site mirroring, harvesting, scraping,
# snooping and data mining / spy bot / security & copyright enforcement companies that
# target and continuosly scan webservers.
DO_NOT_REDISTRIBUTE[ib_bluetack_webexploit.ipset]="1"
update ib_bluetack_webexploit $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=ghlzqtqxnzctvvajwwag&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"attacks" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk web server hack and exploit attempts" \
	"iBlocklist" "https://www.iblocklist.com/"


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
DO_NOT_REDISTRIBUTE[ib_bluetack_level1.netset]="1"
update ib_bluetack_level1 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 1 (for use in p2p): Companies or organizations who are clearly involved with trying to stop filesharing (e.g. Baytsp, MediaDefender, Mediasentry a.o.). Companies which anti-p2p activity has been seen from. Companies that produce or have a strong financial interest in copyrighted material (e.g. music, movie, software industries a.o.). Government ranges or companies that have a strong financial interest in doing work for governments. Legal industry ranges. IPs or ranges of ISPs from which anti-p2p activity has been observed. Basically this list will block all kinds of internet connections that most people would rather not have during their internet travels." \
	"iBlocklist" "https://www.iblocklist.com/"


# General corporate ranges. 
# Ranges used by labs or researchers. 
# Proxies. 
DO_NOT_REDISTRIBUTE[ib_bluetack_level2.netset]="1"
update ib_bluetack_level2 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=gyisgnzbhppbvsphucsw&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 2 (for use in p2p). General corporate ranges. Ranges used by labs or researchers. Proxies." \
	"iBlocklist" "https://www.iblocklist.com/"


# Many portal-type websites. 
# ISP ranges that may be dodgy for some reason. 
# Ranges that belong to an individual, but which have not been determined to be used by a particular company. 
# Ranges for things that are unusual in some way. The L3 list is aka the paranoid list.
DO_NOT_REDISTRIBUTE[ib_bluetack_level3.netset]="1"
update ib_bluetack_level3 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=uwnukjqktoggdknzrhgh&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 3 (for use in p2p). Many portal-type websites. ISP ranges that may be dodgy for some reason. Ranges that belong to an individual, but which have not been determined to be used by a particular company. Ranges for things that are unusual in some way. The L3 list is aka the paranoid list." \
	"iBlocklist" "https://www.iblocklist.com/"

# -----------------------------------------------------------------------------
# BadIPs.com

badipscom() {
	if [ ! -f "badips.source" ]
		then
		if [ ${ENABLE_ALL} -eq 1 ]
			then
			local x=
			for x in badips bi_bruteforce_2_30d bi_ftp_2_30d bi_http_2_30d bi_mail_2_30d bi_proxy_2_30d bi_sql_2_30d bi_ssh_2_30d bi_voip_2_30d
			do
				touch -t 0001010000 "${BASE_DIR}/${x}.source" || return 1
			done
		else
			[ -d .git ] && echo >"${install}.setinfo" "badips.com categories ipsets|[BadIPs.com](https://www.badips.com) community based IP blacklisting. They score IPs based on the reports they reports.|ipv4 hash:ip|disabled|disabled"
			echo >&2 "badips: is disabled, to enable it run: touch -t 0001010000 '${BASE_DIR}/badips.source'"
			return 1
		fi
	fi

	download_manager "badips" $[24*60] "https://www.badips.com/get/categories"
	[ ! -s "badips.source" ] && return 0

	local categories="any $(cat badips.source |\
		tr "[]{}," "\n\n\n\n\n" |\
		egrep '^"(Name|Parent)":"[a-zA-Z0-9_-]+"$' |\
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

			local freq=$[7 * 24 * 60]
			if [ ! -z "${age}" ]
				then
				case "${age}" in
					*d) age=$[${age/d/} * 1] ;;
					*w) age=$[${age/w/} * 7] ;;
					*m) age=$[${age/m/} * 30] ;;
					*y) age=$[${age/y/} * 365] ;;
					*)  age=0; echo >&2 "${ipset}: unknown age '${age}'" ;;
				esac

				[ $[age] -eq 0   ] && freq=$[7 * 24 * 60] # invalid age
				[ $[age] -gt 0   ] && freq=$[         30] # 1-2 days of age
				[ $[age] -gt 2   ] && freq=$[     6 * 60] # 3-7 days
				[ $[age] -gt 7   ] && freq=$[1 * 24 * 60] # 8-90 days
				[ $[age] -gt 90  ] && freq=$[2 * 24 * 60] # 91-180 days
				[ $[age] -gt 180 ] && freq=$[4 * 24 * 60] # 181-365 days
				[ $[age] -gt 365 ] && freq=$[7 * 24 * 60] # 366-ever days

				# echo >&2 "${ipset}: update frequency set to ${freq} mins"
			fi

			update "${ipset}" ${freq} 0 ipv4 ip "${url}" remove_comments "attacks" "${info}" "BadIPs.com" "https://www.badips.com/"
		done

		if [ ${count} -eq 0 ]
			then
			echo >&2 "bi_${category}_SCORE_AGE: is disabled (SCORE=X and AGE=Y[dwmy]). To enable it run: touch -t 0001010000 '${BASE_DIR}/bi_${category}_SCORE_AGE.source'"
		fi
	done
}

badipscom

# -----------------------------------------------------------------------------
# SORBS test

# this is a test - it does not work without another script that rsyncs files from sorbs.net

DO_NOT_REDISTRIBUTE[sorbs_dul.netset]="1"
update sorbs_dul 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) DUL, Dynamic User IPs extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_http.netset]="1"
update sorbs_http 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) HTTP proxies, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_misc.netset]="1"
update sorbs_misc 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) MISC proxies, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_smtp.netset]="1"
update sorbs_smtp 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) SMTP Open Relays, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_socks.netset]="1"
update sorbs_socks 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) SOCKS proxies, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_spam.netset]="1"
update sorbs_spam 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) Spam senders, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_new_spam.netset]="1"
update sorbs_new_spam 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) NEW Spam senders, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_recent_spam.netset]="1"
update sorbs_recent_spam 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) RECENT Spam senders, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_web.netset]="1"
update sorbs_web 1 0 ipv4 both "" remove_comments "test" "[Sorbs.net](https://www.sorbs.net/) WEB exploits, extracted from deltas." "Sorbs.net" "https://www.sorbs.net/"


# -----------------------------------------------------------------------------
# FireHOL lists

merge firehol_level1 "attacks" "An ipset made from blocklists that provide the maximum of protection, with the minimum of false positives. Suitable for basic protection on all systems." \
	fullbogons dshield feodo palevo sslbl zeus_badips spamhaus_drop spamhaus_edrop

merge firehol_level2 "attacks" "An ipset made from blocklists that track attacks, during the last one or two days." \
	openbl_1d dshield_1d blocklist_de stopforumspam_1d botscout_1d greensnow

merge firehol_level3 "attacks" "An ipset made from blocklists that track attacks, spyware, viruses. It includes IPs than have been reported or detected in the last 30 days." \
	openbl_30d dshield_30d stopforumspam_30d virbl malc0de shunlist malwaredomainlist bruteforceblocker \
	ciarmy cleanmx_viruses snort_ipfilter ib_bluetack_spyware ib_bluetack_hijacked ib_bluetack_webexploit \
	php_commenters php_dictionary php_harvesters php_spammers iw_wormlist zeus maxmind_proxy_fraud \
	dragon_http dragon_sshpauth dragon_vncprobe bambenek_c2

merge firehol_proxies "anonymizers" "An ipset made from all sources that track open proxies. It includes IPs reported or detected in the last 30 days." \
	ib_bluetack_proxies maxmind_proxy_fraud proxyrss_30d proxz_30d \
	ri_connect_proxies_30d ri_web_proxies_30d xroxy_30d \
	proxyspy_30d

merge firehol_anonymous "anonymizers" "An ipset that includes all the anonymizing IPs of the world." \
	firehol_proxies anonymous bm_tor dm_tor tor_exits



# -----------------------------------------------------------------------------
# TODO
#
# add sets
# - http://www.ipdeny.com/ipblocks/ geo country db for ipv6
# - maxmind city geodb
# - https://github.com/Blueliv/api-python-sdk/wiki/Blueliv-REST-API-Documentation
# - https://atlas.arbor.net/summary/attacks.csv
# - https://atlas.arbor.net/summary/botnets.csv
# - https://atlas.arbor.net/summary/fastflux.csv
# - https://atlas.arbor.net/summary/phishing.csv
# - https://atlas.arbor.net/summary/scans.csv
# - http://www.cyber-ta.org/releases/malware/SOURCES/Attacker.Cumulative.Summary
# - http://www.cyber-ta.org/releases/malware/SOURCES/CandC.Cumulative.Summary
# - http://www.reputationauthority.org/toptens.php
# - https://vmx.yourcmc.ru/BAD_HOSTS.IP4
# - http://www.geopsy.org/blacklist.html
# - https://www.juniper.net/security/auto/spam/
# - http://www.malwaregroup.com/ipaddresses/malicious
# - http://toastedspam.com/deny
# - http://rss.uribl.com/reports/7d/dns_a.html
# - http://spamcop.net/w3m?action=map;net=cmaxcnt;mask=65535;sort=spamcnt;format=text
# - https://gist.github.com/BBcan177/3cbd01b5b39bb3ce216a
# - https://github.com/rshipp/awesome-malware-analysis
#
# user specific features
# - allow the user to request an email if a set increases by a percentage or number of unique IPs
# - allow the user to request an email if a set matches more than X entries of one or more other set


# -----------------------------------------------------------------------------
# updates
update_web

# commit changes to git (does nothing if not enabled)
commit_to_git

# let the cleanup function exit with success
PROGRAM_COMPLETED=1
