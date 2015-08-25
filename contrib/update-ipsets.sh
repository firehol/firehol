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
WEB_URL="http://iplists.firehol.org/?ipset="
WEB_URL2="https://ktsaou.github.io/blocklist-ipsets/?ipset="

GITHUB_LOCAL_COPY_URL="https://raw.githubusercontent.com/ktsaou/blocklist-ipsets/master/"
GITHUB_CHANGES_URL="https://github.com/ktsaou/blocklist-ipsets/commits/master/"

# options to be given to iprange for reducing netsets
IPSET_REDUCE_FACTOR="20"
IPSET_REDUCE_ENTRIES="65536"

WEB_CHARTS_ENTRIES="500"

# if the .git directory is present, push it also
PUSH_TO_GIT=0


# -----------------------------------------------------------------------------
# Command line parsing

ENABLE_ALL=0
IGNORE_LASTCHECKED=0
FORCE_WEB_REBUILD=0
REPROCESS_ALL=0
SILENT=0
VERBOSE=0
CONFIG_FILE="/etc/firehol/update-ipsets.conf"

declare -a LISTS_TO_ENABLE=()

while [ ! -z "${1}" ]
do
	case "${1}" in
		enable)
			shift
			LISTS_TO_ENABLE=("${@}")
			break
			;;

		--rebuild|-r) FORCE_WEB_REBUILD=1;;
		--reprocess|-p) REPROCESS_ALL=1;;
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

if [ "${#LISTS_TO_ENABLE[@]}" -gt 0 ]
	then
	for x in "${LISTS_TO_ENABLE[@]}"
	do
		if [ -f "${BASE_DIR}/${x}.source" ]
			then
			echo >&2 "${x}: is already enabled"
		else
			echo "${x}: Enabling ${x}..."
			touch -t 0001010000 "${BASE_DIR}/${x}.source" || exit 1
		fi
	done
	exit 0
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
		local date="$(date -u)"
		# we commit each file alone, to have a clear history per file in github
		for d in "${to_be_pushed[@]}" set_file_timestamps.sh
		do
			echo "${d}..."
			git commit "${d}" -m "${date} update"
		done

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
	#local -a hfiles=()
	#for x in ${HISTORY_DIR}/${ipset}/*.set
	#do
	#	if [ "${x}" -nt "${RUN_DIR}/history.reference" ]
	#	then
	#		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: merging history file '${x}'"
	#		hfiles=("${hfiles[@]}" "${x}")
	#	fi
	#done

	"${IPRANGE_CMD}" --union-all $(find "${HISTORY_DIR}/${ipset}"/*.set -newer "${RUN_DIR}/history.reference")

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

	http_code=$(curl --connect-timeout 10 --max-time 180 --retry 0 --fail --compressed \
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
		tmp= now= date= check= inc=

	tmp=`mktemp "${RUN_DIR}/download-${ipset}-XXXXXXXXXX"` || return ${DOWNLOAD_FAILED}

	# make sure it is numeric
	[ "$[mins + 0]" -eq 0 ] && mins=0

	# add some time (1/100th), to make sure the source is updated
	inc=$[ (mins + 50) / 100 ]

	# if the download period is less than 30min, do not add anything
	[ ${mins} -le 30 ] && inc=0

	# if the added time is above 10min, make it 10 min
	[ ${inc} -gt 10 ] && inc=10

	# touch a file $mins + 2 ago
	# we add 2 to let the server update the file
	touch_in_the_past "$[mins + inc]" "${tmp}"

	check="${install}.source"
	[ ${IGNORE_LASTCHECKED} -eq 0 -a -f ".${install}.lastchecked" ] && check=".${install}.lastchecked"

	# check if we have to download again
	if [ "${check}" -nt "${tmp}" ]
	then
		rm "${tmp}"
		echo >&2 "${ipset}: should not be downloaded so soon (within ${mins} + ${inc} = $[mins + inc] mins)."
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

declare -A IPSET_LICENSE=()
declare -A IPSET_GRADE=()
declare -A IPSET_PROTECTION=()
declare -A IPSET_INTENDED_USE=()
declare -A IPSET_FALSE_POSITIVES=()
declare -A IPSET_POISONING=()
declare -A IPSET_ENTRIES_MIN=()
declare -A IPSET_ENTRIES_MAX=()
declare -A IPSET_IPS_MIN=()
declare -A IPSET_IPS_MAX=()
declare -A IPSET_STARTED_DATE=()

declare -A IPSET_CLOCK_SKEW=()

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
		IPSET_LICENSE \
		IPSET_GRADE \
		IPSET_PROTECTION \
		IPSET_INTENDED_USE \
		IPSET_FALSE_POSITIVES \
		IPSET_POISONING \
		IPSET_ENTRIES_MIN \
		IPSET_ENTRIES_MAX \
		IPSET_IPS_MIN \
		IPSET_IPS_MAX \
		IPSET_STARTED_DATE \
		IPSET_CLOCK_SKEW \
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
	unset IPSET_LICENSE[${ipset}]
	unset IPSET_GRADE[${ipset}]
	unset IPSET_PROTECTION[${ipset}]
	unset IPSET_INTENDED_USE[${ipset}]
	unset IPSET_FALSE_POSITIVES[${ipset}]
	unset IPSET_POISONING[${ipset}]
	unset IPSET_ENTRIES_MIN[${ipset}]
	unset IPSET_ENTRIES_MAX[${ipset}]
	unset IPSET_IPS_MIN[${ipset}]
	unset IPSET_IPS_MAX[${ipset}]
	unset IPSET_STARTED_DATE[${ipset}]
	unset IPSET_CLOCK_SKEW[${ipset}]

	cache_save
}

ipset_json() {
	local ipset="${1}" geolite2= ipdeny= ip2location= comparison= info=

	if [ -f "${RUN_DIR}/${ipset}_geolite2_country.json" ]
		then
		geolite2="${ipset}_geolite2_country.json"
	fi

	if [ -f "${RUN_DIR}/${ipset}_ipdeny_country.json" ]
		then
		ipdeny="${ipset}_ipdeny_country.json"
	fi

	if [ -f "${RUN_DIR}/${ipset}_ip2location_country.json" ]
		then
		ip2location="${ipset}_ip2location_country.json"
	fi

	if [ -f "${RUN_DIR}/${ipset}_comparison.json" ]
		then
		comparison="${ipset}_comparison.json"
	fi

	info="${IPSET_INFO[${ipset}]}"
	info=$(echo "${info}" | sed "s/)/)\n/g" | sed "s|\[\(.*\)\](\(.*\))|<a href=\"\2\">\1</a>|g" | tr "\n" " ") 
	info="${info//\"/\\\"}"

	local file_local=
	local commit_history=
	if [ -z "${DO_NOT_REDISTRIBUTE[${IPSET_FILE[${ipset}]}]}" ]
		then
		file_local="${GITHUB_LOCAL_COPY_URL}${IPSET_FILE[${ipset}]}"
		commit_history="${GITHUB_CHANGES_URL}${IPSET_FILE[${ipset}]}"
	fi

	if [ -z "${IPSET_ENTRIES_MIN[${ipset}]}" ]
		then
		IPSET_ENTRIES_MIN[${ipset}]="${IPSET_ENTRIES[${ipset}]}"
	fi
	if [ -z "${IPSET_ENTRIES_MAX[${ipset}]}" ]
		then
		IPSET_ENTRIES_MAX[${ipset}]="${IPSET_ENTRIES[${ipset}]}"
	fi

	if [ -z "${IPSET_IPS_MIN[${ipset}]}" ]
		then
		IPSET_IPS_MIN[${ipset}]="${IPSET_IPS[${ipset}]}"
	fi
	if [ -z "${IPSET_IPS_MAX[${ipset}]}" ]
		then
		IPSET_IPS_MAX[${ipset}]="${IPSET_IPS[${ipset}]}"
	fi

	if [ -z "${IPSET_STARTED_DATE[${ipset}]}" ]
		then
		IPSET_STARTED_DATE[${ipset}]="${IPSET_SOURCE_DATE[${ipset}]}"
	fi

	if [ -z "${IPSET_CLOCK_SKEW[${ipset}]}" ]
		then
		IPSET_CLOCK_SKEW[${ipset}]=0
	fi

	cat <<EOFJSON
{
	"name": "${ipset}",
	"entries": ${IPSET_ENTRIES[${ipset}]},
	"entries_min": ${IPSET_ENTRIES_MIN[${ipset}]},
	"entries_max": ${IPSET_ENTRIES_MAX[${ipset}]},
	"ips": ${IPSET_IPS[${ipset}]},
	"ips_min": ${IPSET_IPS_MIN[${ipset}]},
	"ips_max": ${IPSET_IPS_MAX[${ipset}]},
	"ipv": "${IPSET_IPV[${ipset}]}",
	"hash": "${IPSET_HASH[${ipset}]}",
	"frequency": ${IPSET_MINS[${ipset}]},
	"aggregation": ${IPSET_HISTORY_MINS[${ipset}]},
	"started": ${IPSET_STARTED_DATE[${ipset}]}000,
	"updated": ${IPSET_SOURCE_DATE[${ipset}]}000,
	"processed": ${IPSET_PROCESSED_DATE[${ipset}]}000,
	"clock_skew": $[ IPSET_CLOCK_SKEW[${ipset}] * 1000 ],
	"category": "${IPSET_CATEGORY[${ipset}]}",
	"maintainer": "${IPSET_MAINTAINER[${ipset}]}",
	"maintainer_url": "${IPSET_MAINTAINER_URL[${ipset}]}",
	"info": "${info}",
	"source": "${IPSET_URL[${ipset}]}",
	"file": "${IPSET_FILE[${ipset}]}",
	"history": "${ipset}_history.csv",
	"geolite2": "${geolite2}",
	"ipdeny": "${ipdeny}",
	"ip2location": "${ip2location}",
	"comparison": "${comparison}",
	"file_local": "${file_local}",
	"commit_history": "${commit_history}",
	"license": "${IPSET_LICENSE[${ipset}]}",
	"grade": "${IPSET_GRADE[${ipset}]}",
	"protection": "${IPSET_PROTECTION[${ipset}]}",
	"intended_use": "${IPSET_INTENDED_USE[${ipset}]}",
	"false_positives": "${IPSET_FALSE_POSITIVES[${ipset}]}",
	"poisoning": "${IPSET_POISONING[${ipset}]}"
}
EOFJSON
}

ipset_json_index() {
	local ipset="${1}"

	if [ -z "${IPSET_CLOCK_SKEW[${ipset}]}" ]
		then
		IPSET_CLOCK_SKEW[${ipset}]=0
	fi

cat <<EOFALL
	{
		"ipset": "${ipset}",
		"category": "${IPSET_CATEGORY[${ipset}]}",
		"maintainer": "${IPSET_MAINTAINER[${ipset}]}",
		"updated": ${IPSET_SOURCE_DATE[${ipset}]}000,
		"clock_skew": $[ IPSET_CLOCK_SKEW[${ipset}] * 1000 ],
		"ips": ${IPSET_IPS[${ipset}]}
EOFALL
printf "	}"
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

		if [ -z "${IPSET_STARTED_DATE[${ipset}]}" -o "${IPSET_STARTED_DATE[${ipset}]}" -gt "${RETENTION_HISTOGRAM_STARTED}" ]
			then
			# this is a bit stupid here
			# but anyway is a way to get the real date we started monitoring this ipset
			IPSET_STARTED_DATE[${ipset}]="${RETENTION_HISTOGRAM_STARTED}"
		fi
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

	local ips_added=0
	if [ ! -s "${CACHE_DIR}/${ipset}/new/${ndate}" ]
		then
		# there are no new IPs included
		[ ${VERBOSE} -eq 1 ] && echo >&2 "${ipset}: ${CACHE_DIR}/${ipset}/new/${ndate}: nothing new in this"
		rm "${CACHE_DIR}/${ipset}/new/${ndate}"
	else
		ips_added=$("${IPRANGE_CMD}" -C "${CACHE_DIR}/${ipset}/new/${ndate}")
		ips_added=${ips_added/*,/}
	fi

	local ips_removed=$("${IPRANGE_CMD}" "${CACHE_DIR}/${ipset}/latest" --exclude-next "${IPSET_FILE[${ipset}]}" | "${IPRANGE_CMD}" -C)
	ips_removed=${ips_removed/*,/}

	[ ! -f "${CACHE_DIR}/${ipset}/changesets.csv" ] && echo >"${CACHE_DIR}/${ipset}/changesets.csv" "DateTime,IPsAdded,IPsRemoved"
	echo >>"${CACHE_DIR}/${ipset}/changesets.csv" "${ndate},${ips_added},${ips_removed}"

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

sitemap_init() {
	local sitemap_date="${1}"

cat >${RUN_DIR}/sitemap.xml <<EOFSITEMAPA
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
	<url>
		<loc>${WEB_URL/\?*/}</loc>
		<lastmod>${sitemap_date}</lastmod>
		<changefreq>always</changefreq>
	</url>
EOFSITEMAPA

if [ ! -z "${WEB_URL2}" ]
then
cat >>"${RUN_DIR}/sitemap.xml" <<EOFSITEMAPB
	<url>
		<loc>${WEB_URL2/\?*/}</loc>
		<lastmod>${sitemap_date}</lastmod>
		<changefreq>always</changefreq>
	</url>
EOFSITEMAPB
fi
}

sitemap_ipset() {
	local ipset="${1}" sitemap_date="${2}"

cat >>"${RUN_DIR}/sitemap.xml" <<EOFSITEMAP1
	<url>
		<loc>${WEB_URL}${ipset}</loc>
		<lastmod>${sitemap_date}</lastmod>
		<changefreq>always</changefreq>
	</url>
EOFSITEMAP1

if [ ! -z "${WEB_URL2}" ]
then
cat >>"${RUN_DIR}/sitemap.xml" <<EOFSITEMAP2
	<url>
		<loc>${WEB_URL2}${ipset}</loc>
		<lastmod>${sitemap_date}</lastmod>
		<changefreq>always</changefreq>
	</url>
EOFSITEMAP2
fi
}

update_web() {
	local sitemap_date="$(date -I)"

	[ -z "${WEB_DIR}" -o ! -d "${WEB_DIR}" ] && return 1
	[ "${#UPDATED_SETS[@]}" -eq 0 -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && return 1

	local x= all=() updated=() geolite2_country=() ipdeny_country=() ip2location_country=() i= to_all=

	sitemap_init "${sitemap_date}"

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
				
				echo >"${RUN_DIR}/${x}_history.csv" "DateTime,Entries,UniqueIPs"
				tail -n ${WEB_CHARTS_ENTRIES} "${CACHE_DIR}/${x}/history.csv" | grep -v "^DateTime" >>"${RUN_DIR}/${x}_history.csv"
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
		
		elif [[ "${IPSET_FILE[$x]}" =~ ^ip2location_country.* ]]
			then
			to_all=0
			case "${x}" in
				ip2location_country_*)		i=${x/ip2location_country_/} ;;
				ip2location_continent_*)	i= ;;
				*)							i= ;;
			esac
			[ ! -z "${i}" ] && ip2location_country=("${ip2location_country[@]}" "${IPSET_FILE[$x]}" "as" "${i^^}")
		fi

		if [ ${to_all} -eq 1 ]
			then
			all=("${all[@]}" "${IPSET_FILE[$x]}" "as" "${x}")
			[ ! -z "${UPDATED_SETS[${x}]}" ] && updated=("${updated[@]}" "${IPSET_FILE[$x]}" "as" "${x}")

			if [ ! -f "${RUN_DIR}/all-ipsets.json" ]
				then
				printf >"${RUN_DIR}/all-ipsets.json" "[\n"
			else
				printf >>"${RUN_DIR}/all-ipsets.json" ",\n"
			fi
			ipset_json_index "${x}" >>"${RUN_DIR}/all-ipsets.json"

			sitemap_ipset "${x}" "${sitemap_date}"
		fi
	done
	printf >>"${RUN_DIR}/all-ipsets.json" "\n]\n"
	echo '</urlset>' >>"${RUN_DIR}/sitemap.xml"
	echo >&2

	#echo >&2 "ALL: ${all[@]}"
	#echo >&2 "UPDATED: ${updated[@]}"

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
				printf >>"${RUN_DIR}/${name1}_comparison.json" "	{\n		\"name\": \"${name2}\",\n		\"category\": \"${IPSET_CATEGORY[${name2}]}\",\n		\"ips\": ${ips2},\n		\"common\": ${common}\n	}"

				if [ ! -f "${RUN_DIR}/${name2}_comparison.json" ]
					then
					printf >"${RUN_DIR}/${name2}_comparison.json" "[\n"
				else
					printf >>"${RUN_DIR}/${name2}_comparison.json" ",\n"
				fi
				printf >>"${RUN_DIR}/${name2}_comparison.json" "	{\n		\"name\": \"${name1}\",\n		\"category\": \"${IPSET_CATEGORY[${name1}]}\",\n		\"ips\": ${ips1},\n		\"common\": ${common}\n	}"
			fi
		done
	echo >&2
	for x in $(find "${RUN_DIR}" -name \*_comparison.json)
	do
		printf "\n]\n" >>${x}
	done

	printf >&2 "comparing geolite2 country... "
	"${IPRANGE_CMD}" "${updated[@]}" --compare-next "${geolite2_country[@]}" |\
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
	done

	printf >&2 "comparing ipdeny country... "
	"${IPRANGE_CMD}" "${updated[@]}" --compare-next "${ipdeny_country[@]}" |\
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
	done

	printf >&2 "comparing ip2location country... "
	"${IPRANGE_CMD}" "${updated[@]}" --compare-next "${ip2location_country[@]}" |\
		sort |\
		while IFS="," read name1 name2 entries1 entries2 ips1 ips2 combined common
		do
			if [ ${common} -gt 0 ]
				then
				if [ ! -f "${RUN_DIR}/${name1}_ip2location_country.json" ]
					then
					printf "[\n" >"${RUN_DIR}/${name1}_ip2location_country.json"
				else
					printf ",\n" >>"${RUN_DIR}/${name1}_ip2location_country.json"
				fi

				printf "	{\n		\"code\": \"${name2}\",\n		\"value\": ${common}\n	}" >>"${RUN_DIR}/${name1}_ip2location_country.json"
			fi
		done
	echo >&2
	for x in $(find "${RUN_DIR}" -name \*_ip2location_country.json)
	do
		printf "\n]\n" >>${x}
	done

	printf >&2 "generating javascript info... "
	for x in "${!IPSET_FILE[@]}"
	do
		[ -z "${UPDATED_SETS[${x}]}" -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && continue

		ipset_json "${x}" >"${RUN_DIR}/${x}.json"
	done
	echo >&2

	printf >&2 "generating retention histogram... "
	for x in "${!IPSET_FILE[@]}"
	do
		[ -z "${UPDATED_SETS[${x}]}" -a ! ${FORCE_WEB_REBUILD} -eq 1 ] && continue
		
		[[ "${IPSET_FILE[$x]}" =~ ^geolite2.* ]] && continue
		[[ "${IPSET_FILE[$x]}" =~ ^ipdeny.* ]] && continue
		[[ "${IPSET_FILE[$x]}" =~ ^ip2location.* ]] && continue

		retention_detect "${x}" >"${RUN_DIR}/${x}_retention.json" || rm "${RUN_DIR}/${x}_retention.json"

		# this has to be done after retention_detect()
		echo >"${RUN_DIR}"/${x}_changesets.csv "DateTime,AddedIPs,RemovedIPs"
		tail -n $[ WEB_CHARTS_ENTRIES + 1] "${CACHE_DIR}/${x}/changesets.csv" | grep -v "^DateTime" | tail -n +2 >>"${RUN_DIR}/${x}_changesets.csv"
	done
	echo >&2

	mv -f "${RUN_DIR}"/*.{json,csv,xml} "${WEB_DIR}/"
	chown ${WEB_OWNER} "${WEB_DIR}"/*
	chmod 0644 "${WEB_DIR}"/*.{json,csv,xml}

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

ipset_attributes() {
	local ipset="${1}"
	shift

	while [ ! -z "${1}" ]
	do
		case "${1}" in
			category)			IPSET_CATEGORY[${ipset}]="${2}" ;;
			maintainer)			IPSET_MAINTAINER[${ipset}]="${2}" ;;
			maintainer_url)		IPSET_MAINTAINER_URL[${ipset}]="${2}" ;;
			license)			IPSET_LICENSE[${ipset}]="${2}" ;;
			grade)				IPSET_GRADE[${ipset}]="${2}" ;;
			protection)			IPSET_PROTECTION[${ipset}]="${2}" ;;
			intended_use)		IPSET_INTENDED_USE[${ipset}]="${2}" ;;
			false_positives)	IPSET_FALSE_POSITIVES[${ipset}]="${2}" ;;
			poisoning)			IPSET_POISONING[${ipset}]="${2}" ;;
			*)	echo >&2 "${ipset}: Unknown ipset option '${1}' with value '${2}'." ;;
		esac

		shift 2
	done

	[ -z "${IPSET_LICENSE[${ipset}]}"         ] && IPSET_LICENSE[${ipset}]="unknown"
	[ -z "${IPSET_GRADE[${ipset}]}"           ] && IPSET_GRADE[${ipset}]="unknown"
	[ -z "${IPSET_PROTECTION[${ipset}]}"      ] && IPSET_PROTECTION[${ipset}]="unknown"
	[ -z "${IPSET_INTENDED_USE[${ipset}]}"    ] && IPSET_INTENDED_USE[${ipset}]="unknown"
	[ -z "${IPSET_FALSE_POSITIVES[${ipset}]}" ] && IPSET_FALSE_POSITIVES[${ipset}]="unknown"
	[ -z "${IPSET_POISONING[${ipset}]}"       ] && IPSET_POISONING[${ipset}]="unknown"

	return 0
}

# -----------------------------------------------------------------------------
# finalize() is called when a successful download and convertion completes
# to update the ipset in the kernel and possibly commit it to git
finalize() {
	local 	ipset="${1}" tmp="${2}" setinfo="${3}" \
			src="${4}" dst="${5}" \
			mins="${6}" history_mins="${7}" \
			ipv="${8}" limit="${9}" hash="${10}" \
			url="${11}" category="${12}" info="${13}" \
			maintainer="${14}" maintainer_url="${15}"
	shift 15

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
	if [ $? -eq 0 -a ${REPROCESS_ALL} -eq 0 ]
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

	if [ ${ips} -eq 0 ]
		then
		syslog "${ipset}: processed file has no valid entries (zero unique IPs)"
	fi

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

	[ -z "${IPSET_ENTRIES_MIN[${ipset}]}" ] && IPSET_ENTRIES_MIN[${ipset}]="${IPSET_ENTRIES[${ipset}]}"
	[ "${IPSET_ENTRIES_MIN[${ipset}]}" -gt "${IPSET_ENTRIES[${ipset}]}" ] && IPSET_ENTRIES_MIN[${ipset}]="${IPSET_ENTRIES[${ipset}]}"

	[ -z "${IPSET_ENTRIES_MAX[${ipset}]}" ] && IPSET_ENTRIES_MAX[${ipset}]="${IPSET_ENTRIES[${ipset}]}"
	[ "${IPSET_ENTRIES_MAX[${ipset}]}" -lt "${IPSET_ENTRIES[${ipset}]}" ] && IPSET_ENTRIES_MAX[${ipset}]="${IPSET_ENTRIES[${ipset}]}"

	[ -z "${IPSET_IPS_MIN[${ipset}]}" ] && IPSET_IPS_MIN[${ipset}]="${IPSET_IPS[${ipset}]}"
	[ "${IPSET_IPS_MIN[${ipset}]}" -gt "${IPSET_IPS[${ipset}]}" ] && IPSET_IPS_MIN[${ipset}]="${IPSET_IPS[${ipset}]}"

	[ -z "${IPSET_IPS_MAX[${ipset}]}" ] && IPSET_IPS_MAX[${ipset}]="${IPSET_IPS[${ipset}]}"
	[ "${IPSET_IPS_MAX[${ipset}]}" -lt "${IPSET_IPS[${ipset}]}" ] && IPSET_IPS_MAX[${ipset}]="${IPSET_IPS[${ipset}]}"

	[ -z "${IPSET_STARTED_DATE[${ipset}]}" ] && IPSET_STARTED_DATE[${ipset}]="${IPSET_SOURCE_DATE[${ipset}]}"

	local now="$(date +%s)"
	if [ "${now}" -lt "${IPSET_SOURCE_DATE[${ipset}]}" ]
		then
		IPSET_CLOCK_SKEW[${ipset}]=$[ IPSET_SOURCE_DATE[${ipset}] - now ]
	else
		IPSET_CLOCK_SKEW[${ipset}]=0
	fi

	ipset_attributes "${ipset}" "${@}"

	# generate the final file
	# we do this on another tmp file
	cat >"${tmp}.wh" <<EOFHEADER
#
# ${ipset}
#
# ${ipv} hash:${hash} ipset
#
`echo "${info}" | sed "s|](|] (|g" | fold -w 60 -s | sed "s/^/# /g"`
#
# Maintainer      : ${maintainer}
# Maintainer URL  : ${maintainer_url}
# List source URL : ${url}
# Source File Date: `date -r "${src}" -u`
#
# Category        : ${category}
#
# This File Date  : `date -u`
# Update Frequency: `mins_to_text ${mins}`
# Aggregation     : `mins_to_text ${history_mins}`
# Entries         : ${quantity}
#
# Full list analysis, including geolocation map, history,
# retention policy, overlaps with other lists, etc.
# available at:
#
#  ${WEB_URL}${ipset}
#
# Generated by FireHOL's update-ipsets.sh
# Processed with FireHOL's iprange
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
	local 	ipset="${1}" mins="${2}" history_mins="${3}" ipv="${4}" limit="${5}" \
			url="${6}" \
			processor="${7-cat}" \
			category="${8}" \
			info="${9}" \
			maintainer="${10}" maintainer_url="${11}"
	shift 11

	local	install="${ipset}" tmp= error=0 now= date= \
			pre_filter="cat" post_filter="cat" post_filter2="cat" filter="cat"

	# check
	if [ -z "${info}" ]
		then
		echo >&2 "${ipset}: INTERNAL ERROR (update): no info supplied"
		info="${category}"
	fi

	case "${ipv}" in
		ipv4)
			post_filter2="filter_invalid4"
			case "${limit}" in
				ip|ips)		# output is single ipv4 IPs without /
						hash="ip"
						limit="ip"
						pre_filter="cat"
						filter="filter_ip4"	# without this, ipset_uniq4 may output huge number of IPs
						post_filter="ipset_uniq4"
						;;

				net|nets)	# output is full CIDRs without any single IPs (/32)
						hash="net"
						limit="net"
						pre_filter="filter_all4"
						filter="aggregate4"
						post_filter="filter_net4"
						;;

				both|all)	# output is full CIDRs with single IPs in CIDR notation (with /32)
						hash="net"
						limit=""
						pre_filter="filter_all4"
						filter="aggregate4"
						post_filter="cat"
						;;

				split)	;;

				*)		echo >&2 "${ipset}: unknown limit '${limit}'."
						return 1
						;;
			esac
			;;
		ipv6)
			echo >&2 "${ipset}: IPv6 is not yet supported."
			return 1
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
			elif [ -f "${install}.${hash}set" -a ${REPROCESS_ALL} -eq 0 ]
			then
				check_file_too_old "${ipset}" "${install}.${hash}set"
				return 1
			fi
		fi
	fi

	# support for older systems where hash:net cannot get hash:ip entries
	# if the .split file exists, create 2 ipsets, one for IPs and one for subnets
	if [ "${limit}" = "split" -o \( -z "${limit}" -a -f "${install}.split" \) ]
	then
		echo >&2 "${ipset}: spliting IPs and networks..."
		test -f "${install}_ip.source" && rm "${install}_ip.source"
		test -f "${install}_net.source" && rm "${install}_net.source"
		ln -s "${install}.source" "${install}_ip.source"
		ln -s "${install}.source" "${install}_net.source"
		
		update "${ipset}_ip" "${mins}" "${history_mins}" "${ipv}" ip  \
			"" \
			"${processor}" \
			"${category}" \
			"${info}" \
			"${maintainer}" "${maintainer_url}"
		
		update "${ipset}_net" "${mins}" "${history_mins}" "${ipv}" net \
			"" \
			"${processor}" \
			"${category}" \
			"${info}" \
			"${maintainer}" "${maintainer_url}"
		
		return $?
	fi

	# check if the source file has been updated
	if [ ${REPROCESS_ALL} -eq 0 -a ! "${install}.source" -nt "${install}.${hash}set" ]
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
		${post_filter2} >"${tmp}"

	if [ $? -ne 0 ]
	then
		syslog "${ipset}: failed to convert file (processor: ${processor}, pre_filter: ${pre_filter}, filter: ${filter}, post_filter: ${post_filter}, post_filter2: ${post_filter2})."
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

		finalize "${ipset}${htag}" "${tmp}${htag}" "${install}${htag}.setinfo" \
			"${install}${htag}.source" "${install}${htag}.${hash}set" \
			"${mins}" "${hmins}" "${ipv}" "${limit}" "${hash}" \
			"${url}" \
			"${category}" \
			"${info}" \
			"${maintainer}" "${maintainer_url}"
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
		for x in _comparison.json _geolite2_country.json _ipdeny_country.json _ip2location_country.json _history.csv retention.json .json
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

# grep and egrep return 1 if they match nothing
# this will break the filters if the source is empty
# so we make them return 0 always

# match a single IPv4 IP
# zero prefix is not permitted 0 - 255, not 000, 010, etc
IP4_MATCH="(((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9]))"

# match a single IPv4 net mask (/32 allowed, /0 not allowed)
MK4_MATCH="(3[12]|[12][0-9]|[1-9])"

# strict checking of IPv4 IPs - all subnets excluded
# we remove /32 before matching
filter_ip4()  { remove_slash32 | egrep "^${IP4_MATCH}$"; return 0; }

# strict checking of IPv4 CIDRs, except /32
# this is to support older ipsets that do not accept /32 in hash:net ipsets
filter_net4() { remove_slash32 | egrep "^${IP4_MATCH}/${MK4_MATCH}$"; return 0; }

# strict checking of IPv4 IPs or CIDRs
# hosts may or may not have /32
filter_all4() { egrep "^${IP4_MATCH}(/${MK4_MATCH})?$"; return 0; }

filter_ip6()  { remove_slash128 | egrep "^([0-9a-fA-F:]+)$"; return 0; }
filter_net6() { remove_slash128 | egrep "^([0-9a-fA-F:]+/[0-9]+)$"; return 0; }
filter_all6() { egrep "^([0-9a-fA-F:]+(/[0-9]+)?)$"; return 0; }

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
	grep "href=\"proxy" |\
		cut -d '>' -f 2 |\
		cut -d '<' -f 1
}

extract_ipv4_from_any_file() {
	grep -oP "${IP4_MATCH}"
}

# convert hphosts file to IPs, by resolving all IPs
hphosts2ips() {
	tr "\t\r" "  " |\
		trim |\
		cut -d ' ' -f 2- |\
		tr " " "\n" |\
		sort -u |\
		grep -v "^$" |\
		grep -v "^localhost$" |\
		adnshost --pipe 2>/dev/null |\
		grep " A INET " |\
		cut -d ' ' -f 4
}

geolite2_country() {
	local ipset="geolite2_country" limit="" hash="net" ipv="ipv4" \
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
		[ ! -s "${ipset}.source" ] && return 1
		[ -d ${ipset} -a ${REPROCESS_ALL} -eq 0 ] && return 1
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

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${limit}" "${hash}" "${url}" "geolocation" "${info2}" "MaxMind.com" "http://www.maxmind.com/"
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
	local ipset="ipdeny_country" limit="" hash="net" ipv="ipv4" \
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
		[ ! -s "${ipset}.source" ] && return 1
		[ -d ${ipset} -a ${REPROCESS_ALL} -eq 0 ] && return 1
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

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${limit}" "${hash}" "${url}" "geolocation" "${info2}" "IPDeny.com" "http://www.ipdeny.com/"
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

declare -A IP2LOCATION_COUNTRY_NAMES=()
declare -A IP2LOCATION_COUNTRY_CONTINENTS='([um]="na" [fk]="sa" [ax]="eu" [as]="oc" [ge]="as" [ar]="sa" [gd]="na" [dm]="na" [kp]="as" [rw]="af" [gg]="eu" [qa]="as" [ni]="na" [do]="na" [gf]="sa" [ru]="eu" [kr]="as" [aw]="na" [ga]="af" [rs]="eu" [no]="eu" [nl]="eu" [au]="oc" [kw]="as" [dj]="af" [at]="eu" [gb]="eu" [dk]="eu" [ky]="na" [gm]="af" [ug]="af" [gl]="na" [de]="eu" [nc]="oc" [az]="as" [hr]="eu" [na]="af" [gn]="af" [kz]="as" [et]="af" [ht]="na" [es]="eu" [gi]="eu" [nf]="oc" [ng]="af" [gh]="af" [hu]="eu" [er]="af" [ua]="eu" [ne]="af" [yt]="af" [gu]="oc" [nz]="oc" [om]="as" [gt]="na" [gw]="af" [hk]="as" [re]="af" [ag]="na" [gq]="af" [ke]="af" [gp]="na" [uz]="as" [af]="as" [hn]="na" [uy]="sa" [dz]="af" [kg]="as" [ae]="as" [ad]="eu" [gr]="eu" [ki]="oc" [nr]="oc" [eg]="af" [kh]="as" [ro]="eu" [ai]="na" [np]="as" [ee]="eu" [us]="na" [ec]="sa" [gy]="sa" [ao]="af" [km]="af" [am]="as" [ye]="as" [nu]="oc" [kn]="na" [al]="eu" [si]="eu" [fr]="eu" [bf]="af" [mw]="af" [cy]="eu" [vc]="na" [mv]="as" [bg]="eu" [pr]="na" [sk]="eu" [bd]="as" [mu]="af" [ps]="as" [va]="eu" [cz]="eu" [be]="eu" [mt]="eu" [zm]="af" [ms]="na" [bb]="na" [sm]="eu" [pt]="eu" [io]="as" [vg]="na" [sl]="af" [mr]="af" [la]="as" [in]="as" [ws]="oc" [mq]="na" [im]="eu" [lb]="as" [tz]="af" [so]="af" [mp]="oc" [ve]="sa" [lc]="na" [ba]="eu" [sn]="af" [pw]="oc" [il]="as" [tt]="na" [bn]="as" [sa]="as" [bo]="sa" [py]="sa" [bl]="na" [tv]="oc" [sc]="af" [vi]="na" [cr]="na" [bm]="na" [sb]="oc" [tw]="as" [cu]="na" [se]="eu" [bj]="af" [vn]="as" [li]="eu" [mz]="af" [sd]="af" [cw]="na" [ie]="eu" [sg]="as" [jp]="as" [my]="as" [tr]="as" [bh]="as" [mx]="na" [cv]="af" [id]="as" [lk]="as" [za]="af" [bi]="af" [ci]="af" [tl]="oc" [mg]="af" [lt]="eu" [sy]="as" [sx]="na" [pa]="na" [mf]="na" [lu]="eu" [ch]="eu" [tm]="as" [bw]="af" [jo]="as" [me]="eu" [tn]="af" [ck]="oc" [bt]="as" [lv]="eu" [wf]="oc" [to]="oc" [jm]="na" [sz]="af" [md]="eu" [br]="sa" [mc]="eu" [cm]="af" [th]="as" [pe]="sa" [cl]="sa" [bs]="na" [pf]="oc" [co]="sa" [ma]="af" [lr]="af" [tj]="as" [bq]="na" [tk]="oc" [vu]="oc" [pg]="oc" [cn]="as" [ls]="af" [ca]="na" [is]="eu" [td]="af" [fj]="oc" [mo]="as" [ph]="as" [mn]="as" [zw]="af" [ir]="as" [ss]="af" [mm]="as" [iq]="as" [sr]="sa" [je]="eu" [ml]="af" [tg]="af" [pk]="as" [fi]="eu" [bz]="na" [pl]="eu" [mk]="eu" [pm]="na" [fo]="eu" [st]="af" [ly]="af" [cd]="af" [cg]="af" [sv]="na" [tc]="na" [it]="eu" [fm]="oc" [mh]="oc" [by]="eu" [cf]="af" )'
declare -A IP2LOCATION_COUNTRIES=()
declare -A IP2LOCATION_CONTINENTS=()
ip2location_country() {
	local ipset="ip2location_country" limit="" hash="net" ipv="ipv4" \
		mins=$[24 * 60 * 1] history_mins=0 \
		url="http://download.ip2location.com/lite/IP2LOCATION-LITE-DB1.CSV.ZIP" \
		info="[IP2Location.com](http://lite.ip2location.com/database-ip-country)"

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
		[ ! -s "${ipset}.source" ] && return 1
		[ -d ${ipset} -a ${REPROCESS_ALL} -eq 0 ] && return 1
	fi

	# create a temp dir
	[ -d ${ipset}.tmp ] && rm -rf ${ipset}.tmp
	mkdir ${ipset}.tmp || return 1

	# extract it - in a subshell to do it in the tmp dir
	( cd "${BASE_DIR}/${ipset}.tmp" && unzip -x "${BASE_DIR}/${ipset}.source" )
	local file="${ipset}.tmp/IP2LOCATION-LITE-DB1.CSV"

	if [ ! -f "${file}" ]
		then
		echo >&2 "${ipset}: failed to find file ${file/*\//} in downloaded archive"
		rm -rf "${ipset}.tmp"
		return 1
	fi

	# create the final dir
	if [ ! -d ${ipset} ]
	then
		mkdir ${ipset} || return 1
	fi

	# find all the countries in the file

	echo >&2 "${ipset}: Finding included countries..."
	cat "${file}" | cut -d ',' -f 3,4 | sort -u | sed 's/","/|/g' | tr '"\r' '  ' | trim >"${ipset}.tmp/countries"
	local code= name=
	while IFS="|" read code name
	do
		if [ "a${code}" = "a-" ]
			then
			name="IPs that do not belong to any country"
		fi

		IP2LOCATION_COUNTRY_NAMES[${code}]="${name}"
	done <"${ipset}.tmp/countries"

	echo >&2 "${ipset}: Extracting countries..."
	local x=
	for x in ${!IP2LOCATION_COUNTRY_NAMES[@]}
	do
		if [ "a${x}" = "a-" ]
			then
			code="countryless"
			name="IPs that do not belong to any country"
		else
			code="${x,,}"
			name=${IP2LOCATION_COUNTRY_NAMES[${x}]}
		fi

		echo >&2 "${ipset}: extracting country '${x}' (code='${code}', name='${name}')..."
		cat "${file}" 			|\
			grep ",\"${x}\"," 	|\
			cut -d ',' -f 1,2 	|\
			sed 's/","/ - /g' 	|\
			tr '"' ' ' 			|\
			"${IPRANGE_CMD}" 	|\
			filter_invalid4 >"${ipset}.tmp/ip2location_country_${code}.source.tmp"

		if [ ! -z "${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}" ]
			then
			[ ! -f "${ipset}.tmp/id_continent_${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}.source.tmp.info" ] && printf "%s" "Continent ${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}, with countries: " >"${ipset}.tmp/id_continent_${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}.source.tmp.info"
			printf "%s" "${IP2LOCATION_COUNTRY_NAMES[${x}]} (${code^^}), " >>"${ipset}.tmp/ip2location_continent_${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}.source.tmp.info"
			cat "${ipset}.tmp/ip2location_country_${code}.source.tmp" >>"${ipset}.tmp/ip2location_continent_${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}.source.tmp"
			IP2LOCATION_CONTINENTS[${IP2LOCATION_COUNTRY_CONTINENTS[${code}]}]="1"
		else
			echo >&2 "${ipset}: I don't know the continent of country ${code}."
		fi

		printf "%s" "${IP2LOCATION_COUNTRY_NAMES[${x}]} (${code^^})" >"${ipset}.tmp/ip2location_country_${code}.source.tmp.info"
	done

	echo >&2 "${ipset}: Aggregating country and continent netsets..."
	for x in ${ipset}.tmp/*.source.tmp
	do
		mv "${x}" "${x/.source.tmp/.source}"
		touch -r "${ipset}.source" "${x/.source.tmp/.source}"

		local i=${x/.source.tmp/}
		i=${i/${ipset}.tmp\//}

		local info2="`cat "${x}.info"` -- ${info}"

		finalize "${i}" "${x/.source.tmp/.source}" "${ipset}/${i}.setinfo" "${ipset}.source" "${ipset}/${i}.netset" "${mins}" "${history_mins}" "${ipv}" "${limit}" "${hash}" "${url}" "geolocation" "${info2}" "IP2Location.com" "http://lite.ip2location.com/database-ip-country"
	done

	if [ -d .git ]
	then
		# generate a setinfo for the home page
		echo >"${ipset}.setinfo" "[${ipset}](https://github.com/ktsaou/blocklist-ipsets/tree/master/ip2location_country)|[IP2Location.com](http://lite.ip2location.com/database-ip-country) geolocation database|ipv4 hash:net|All the world|updated every `mins_to_text ${mins}` from [this link](${url})"
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
	local found_updated=0 max_date=0
	for x in "${@}"
	do
		if [ ! -z "${IPSET_FILE[${x}]}" -a -f "${IPSET_FILE[${x}]}" ]
			then

			# check if it is newer
			if [ "$[ IPSET_SOURCE_DATE[${x}] - IPSET_CLOCK_SKEW[${x}] ]" -gt "${max_date}" ]
				then
				max_date="$[ IPSET_SOURCE_DATE[${x}] - IPSET_CLOCK_SKEW[${x}] ]"
			fi

			files=("${files[@]}" "${IPSET_FILE[${x}]}")
			included=("${included[@]}" "${x}")

			if [ ! -z "${UPDATED_SETS[${x}]}" -o "$[ IPSET_SOURCE_DATE[${x}] - IPSET_CLOCK_SKEW[${x}] ]" -gt "$[ IPSET_SOURCE_DATE[${to}] - IPSET_CLOCK_SKEW[${to}] ]" ]
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
	touch --date=@${max_date} "${to}.tmp" "${to}.source"
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
# IP2Location.com

ip2location_country


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
update tor_exits 5 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"https://check.torproject.org/exit-addresses" \
	torproject_exits \
	"anonymizers" \
	"[TorProject.org](https://www.torproject.org) list of all current TOR exit points (TorDNSEL)" \
	"TorProject.org" "https://www.torproject.org/"

update darklist_de $[24 * 60] 0 ipv4 both \
	"http://www.darklist.de/raw.php" \
	remove_comments \
	"attacks" \
	"[darklist.de](http://www.darklist.de/) ssh fail2ban reporting" \
	"darklist.de" "http://www.darklist.de/"

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
	"reputation" \
	"[EmergingThreats.net Command and Control IPs](http://doc.emergingthreats.net/bin/view/Main/BotCC) These IPs are updates every 24 hours and should be considered VERY highly reliable indications that a host is communicating with a known and active Bot or Malware command and control server - (although they say this includes abuse.ch trackers, it does not - check its overlaps)" \
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
# These guys say that this list should be dropped at tier-1 ISPs globally!
update spamhaus_drop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/drop.txt" \
	remove_comments_semi_colon \
	"reputation" \
	"[Spamhaus.org](http://www.spamhaus.org) DROP list (according to their site this list should be dropped at tier-1 ISPs globally)" \
	"Spamhaus.org" "http://www.spamhaus.org/"

# extended DROP (EDROP) list.
# Should be used together with their DROP list.
update spamhaus_edrop $[12*60] 0 ipv4 both \
	"http://www.spamhaus.org/drop/edrop.txt" \
	remove_comments_semi_colon \
	"reputation" \
	"[Spamhaus.org](http://www.spamhaus.org) EDROP (extended matches that should be used with DROP)" \
	"Spamhaus.org" "http://www.spamhaus.org/"


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
	"Abuse.ch" "https://feodotracker.abuse.ch/"


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

# The aggressive version of the SSL IP Blacklist contains all IPs that SSLBL ever detected being associated with a malicious SSL certificate. Since IP addresses can be reused (e.g. when the customer changes), this blacklist may cause false positives. Hence I highly recommend you to use the standard version instead of the aggressive one.
update sslbl_aggressive 30 0 ipv4 ip \
	"https://sslbl.abuse.ch/blacklist/sslipblacklist_aggressive.csv" \
	csv_comma_first_column \
	"malware" \
	"[Abuse.ch SSL Blacklist](https://sslbl.abuse.ch/) The aggressive version of the SSL IP Blacklist contains all IPs that SSLBL ever detected being associated with a malicious SSL certificate. Since IP addresses can be reused (e.g. when the customer changes), this blacklist may cause false positives. Hence I highly recommend you to use the standard version instead of the aggressive one." \
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
	"malware" \
	"[Malc0de.com](http://malc0de.com) malicious IPs of the last 30 days" \
	"malc0de.com" "http://malc0de.com/"


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
	"MyIP.ms" "http://myip.ms/"


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
# Free Proxy List

# http://www.sslproxies.org/
update sslproxies 10 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.sslproxies.org/" \
	extract_ipv4_from_any_file \
	"anonymizers" \
	"[SSLProxies.org](http://www.sslproxies.org/) open SSL proxies" \
	"Free Proxy List" "http://free-proxy-list.net/"

# http://www.socks-proxy.net/
update socks_proxy 10 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.socks-proxy.net/" \
	extract_ipv4_from_any_file \
	"anonymizers" \
	"[socks-proxy.net](http://www.socks-proxy.net/) open SOCKS proxies" \
	"Free Proxy List" "http://free-proxy-list.net/"

# -----------------------------------------------------------------------------
# Open Proxies from proxz.com
# http://www.proxz.com/

update proxz 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.proxz.com/proxylists.xml" \
	parse_rss_proxy \
	"anonymizers" \
	"[proxz.com](http://www.proxz.com) open proxies (this list is composed using an RSS feed)" \
	"ProxZ.com" "http://www.proxz.com/"


# -----------------------------------------------------------------------------
# Open Proxies from proxylists.net
# http://www.proxylists.net/proxylists.xml

update proxylists 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.proxylists.net/proxylists.xml" \
	parse_rss_proxy \
	"anonymizers" \
	"[proxylists.net](http://www.proxylists.net/) open proxies (this list is composed using an RSS feed)" \
	"ProxyLists.net" "http://www.proxylists.net/"


# -----------------------------------------------------------------------------
# Open Proxies from proxyspy.net
# http://spys.ru/en/

parse_proxyspy() { remove_comments | cut -d ':' -f 1; }

update proxyspy 60 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://txt.proxyspy.net/proxy.txt" \
	parse_proxyspy \
	"anonymizers" \
	"[ProxySpy](http://spys.ru/en/) open proxies (updated hourly)" \
	"ProxySpy (spys.ru)" "http://spys.ru/en/"


# -----------------------------------------------------------------------------
# Open Proxies from proxyrss.com
# http://www.proxyrss.com/

update proxyrss $[4*60] "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"http://www.proxyrss.com/proxylists/all.gz" \
	gz_proxyrss \
	"anonymizers" \
	"[proxyrss.com](http://www.proxyrss.com) open proxies syndicated from multiple sources." \
	"ProxyRSS.com" "http://www.proxyrss.com/"


# -----------------------------------------------------------------------------
# Anonymous Proxies
# https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list

update maxmind_proxy_fraud $[4*60] 0 ipv4 ip \
	"https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list" \
	parse_maxmind_proxy_fraud \
	"anonymizers" \
	"[MaxMind.com](https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list) list of anonymous proxy fraudelent IP addresses." \
	"MaxMind.com" "https://www.maxmind.com/en/anonymous-proxy-fraudulent-ip-address-list"


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
# blocklist.net.ua
# https://blocklist.net.ua

update blocklist_net_ua $[10] 0 ipv4 ip \
	"https://blocklist.net.ua/blocklist.csv" \
	remove_comments_semi_colon \
	"abuse" \
	"[blocklist.net.ua](https://blocklist.net.ua) The BlockList project was created to become protection against negative influence of the harmful and potentially dangerous events on the Internet. First of all this service will help internet and hosting providers to protect subscribers sites from being hacked. BlockList will help to stop receiving a large amount of spam from dubious SMTP relays or from attempts of brute force passwords to servers and network equipment." \
	"blocklist.net.ua" "https://blocklist.net.ua"


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
	"Alien Vault" "https://www.alienvault.com/"


# -----------------------------------------------------------------------------
# Clean-MX
# Viruses

update cleanmx_viruses 30 0 ipv4 ip \
	"http://support.clean-mx.de/clean-mx/xmlviruses.php?response=alive&fields=ip" \
	parse_xml_clean_mx \
	"spam" \
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
	"Collective Intelligence Network Security" "http://ciarmy.com/"


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
# PacketMail
# https://www.packetmail.net/iprep.txt

parse_packetmail() { remove_comments | cut -d ';' -f 1; }

update packetmail $[4*60] 0 ipv4 ip \
	"https://www.packetmail.net/iprep.txt" \
	 parse_packetmail \
	"reputation" \
	"[PacketMail.net](https://www.packetmail.net/iprep.txt) IP addresses have been detected performing TCP SYN to 206.82.85.196/30 to a non-listening service or daemon. No assertion is made, nor implied, that any of the below listed IP addresses are accurate, malicious, hostile, or engaged in nefarious acts. Use this list at your own risk." \
	"PacketMail.net" "https://www.packetmail.net/iprep.txt"


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
	"Snort.org Labs" "https://labs.snort.org/"


# -----------------------------------------------------------------------------
# TalosIntel
# http://talosintel.com

update talosintel_ipfilter $[4*60] 0 ipv4 ip \
	"http://talosintel.com/files/additional_resources/ips_blacklist/ip-filter.blf" \
	remove_comments \
	"attacks" \
	"[TalosIntel.com](http://talosintel.com/additional-resources/) List of known malicious network threats" \
	"TalosIntel.com" "http://talosintel.com/"

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
	"VirBL.bit.nl" "http://virbl.bit.nl/"


# -----------------------------------------------------------------------------
# AutoShun.org
# http://www.autoshun.org/

update shunlist $[4*60] 0 ipv4 ip \
	"http://www.autoshun.org/files/shunlist.csv" \
	csv_comma_first_column \
	"attacks" \
	"[AutoShun.org](http://autoshun.org/) IPs identified as hostile by correlating logs from distributed snort installations running the autoshun plugin" \
	"AutoShun.org" "http://autoshun.org/"


# -----------------------------------------------------------------------------
# VoIPBL.org
# http://www.voipbl.org/

update voipbl $[4*60] 0 ipv4 both \
	"http://www.voipbl.org/update/" \
	remove_comments \
	"attacks" \
	"[VoIPBL.org](http://www.voipbl.org/) a distributed VoIP blacklist that is aimed to protects against VoIP Fraud and minimizing abuse for network that have publicly accessible PBX's. Several algorithms, external sources and manual confirmation are used before they categorize something as an attack and determine the threat level." \
	"VoIPBL.org" "http://www.voipbl.org/"


# -----------------------------------------------------------------------------
# Stefan Gofferje
# http://stefan.gofferje.net/

update gofferje_sip $[6*60] 0 ipv4 both \
	"http://stefan.gofferje.net/sipblocklist.zone" \
	remove_comments \
	"attacks" \
	"[Stefan Gofferje](http://stefan.gofferje.net/it-stuff/sipfraud/sip-attacker-blacklist) A personal blacklist of networks and IPs of SIP attackers. To end up here, the IP or network must have been the origin of considerable and repeated attacks on my PBX and additionally, the ISP didn't react to any complaint. Note from the author: I don't give any guarantees of accuracy, completeness or even usability! USE AT YOUR OWN RISK! Also note that I block complete countries, namely China, Korea and Palestine with blocklists from ipdeny.com, so some attackers will never even get the chance to get noticed by me to be put on this blacklist. I also don't accept any liabilities related to this blocklist. If you're an ISP and don't like your IPs being listed here, too bad! You should have done something about your customers' behavior and reacted to my complaints. This blocklist is nothing but an expression of my personal opinion and exercising my right of free speech." \
	"Stefan Gofferje" "http://stefan.gofferje.net/it-stuff/sipfraud/sip-attacker-blacklist"


# -----------------------------------------------------------------------------
# LashBack Unsubscribe Blacklist
# http://blacklist.lashback.com/
# (this is a big list, more than 500.000 IPs)

update lashback_ubl $[24*60] 0 ipv4 ip \
	"http://www.unsubscore.com/blacklist.txt" \
	remove_comments \
	"spam" \
	"[The LashBack UBL](http://blacklist.lashback.com/) The Unsubscribe Blacklist (UBL) is a real-time blacklist of IP addresses which are sending email to names harvested from suppression files (this is a big list, more than 500.000 IPs)" \
	"The LashBack Unsubscribe Blacklist" "http://blacklist.lashback.com/"

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
	"NoThink.org" "http://www.nothink.org/"

update nt_malware_irc 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_irc.txt" \
	remove_comments \
	"attacks" \
	"[No Think](http://www.nothink.org/) Malware IRC" \
	"NoThink.org" "http://www.nothink.org/"

update nt_malware_http 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_http.txt" \
	remove_comments \
	"attacks" \
	"[No Think](http://www.nothink.org/) Malware HTTP" \
	"NoThink.org" "http://www.nothink.org/"

update nt_malware_dns 60 0 ipv4 ip \
	"http://www.nothink.org/blacklist/blacklist_malware_dns.txt" \
	remove_comments \
	"attacks" \
	"[No Think](http://www.nothink.org/) Malware DNS (the original list includes hostnames and domains, which are ignored)" \
	"NoThink.org" "http://www.nothink.org/"

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
	"BotScout.com" "http://botscout.com/"

# -----------------------------------------------------------------------------
# GreenSnow
# https://greensnow.co/

update greensnow 30 0 ipv4 ip \
	"http://blocklist.greensnow.co/greensnow.txt" \
	remove_comments \
	"attacks" \
	"[GreenSnow](https://greensnow.co/) is a team harvesting a large number of IPs from different computers located around the world. GreenSnow is comparable with SpamHaus.org for attacks of any kind except for spam. Their list is updated automatically and you can withdraw at any time your IP address if it has been listed. Attacks / bruteforce that are monitored are: Scan Port, FTP, POP3, mod_security, IMAP, SMTP, SSH, cPanel, etc." \
	"GreenSnow.co" "https://greensnow.co/"


# -----------------------------------------------------------------------------
# http://cybercrime-tracker.net/fuckerz.php

update cybercrime $[12 * 60] 0 ipv4 ip \
	"http://cybercrime-tracker.net/fuckerz.php" \
	extract_ipv4_from_any_file \
	"malware" \
	"[CyberCrime](http://cybercrime-tracker.net/) A project tracking Command and Control." \
	"CyberCrime" "http://cybercrime-tracker.net/"


# -----------------------------------------------------------------------------
# http://vxvault.net/ViriList.php?s=0&m=100

update vxvault $[12 * 60] 0 ipv4 ip \
	"http://vxvault.net/ViriList.php?s=0&m=100" \
	extract_ipv4_from_any_file \
	"malware" \
	"[VxVault](http://vxvault.net) The latest 100 additions of VxVault." \
	"VxVault" "http://vxvault.net"

# -----------------------------------------------------------------------------
# Bitcoin connected hosts

update bitcoin_blockchain_info 10 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"https://blockchain.info/en/connected-nodes" \
	extract_ipv4_from_any_file \
	"reputation" \
	"[Blockchain.info](https://blockchain.info/en/connected-nodes) Bitcoin nodes connected to Blockchain.info." \
	"Blockchain.info" "https://blockchain.info/en/connected-nodes"

update bitcoin_nodes 10 "$[24*60] $[7*24*60] $[30*24*60]" ipv4 ip \
	"https://getaddr.bitnodes.io/api/v1/snapshots/latest/" \
	extract_ipv4_from_any_file \
	"reputation" \
	"[BitNodes](https://getaddr.bitnodes.io/) Bitcoin connected nodes, globally." \
	"BitNodes" "https://getaddr.bitnodes.io/"


# -----------------------------------------------------------------------------
# BinaryDefense
# https://www.binarydefense.com/

update bds_atif $[24*60] 0 ipv4 ip \
	"https://www.binarydefense.com/banlist.txt" \
	remove_comments \
	"reputation" \
	"[Binary Defense Systems Artillery Threat Intelligence Feed and Banlist Feed](https://www.binarydefense.com/banlist.txt)" \
	"Binary Defense Systems" "https://www.binarydefense.com/"


# -----------------------------------------------------------------------------
# Pushing Inertia
# https://github.com/pushinginertia/ip-blacklist

parse_pushing_inertia() { grep "^deny from " | cut -d ' ' -f 3-; }

update pushing_inertia_blocklist $[24*60] 0 ipv4 both \
	"https://raw.githubusercontent.com/pushinginertia/ip-blacklist/master/ip_blacklist.conf" \
	parse_pushing_inertia \
	"reputation" \
	"[Pushing Inertia](https://github.com/pushinginertia/ip-blacklist) IPs of hosting providers that are known to host various bots, spiders, scrapers, etc. to block access from these providers to web servers." \
	"Pushing Inertia" "https://github.com/pushinginertia/ip-blacklist" \
	license "MIT" \
	intended_use "firewall_block_service" \
	protection "inbound" \
	grade "unknown" \
	false_positives "none" \
	poisoning "not_possible"

# -----------------------------------------------------------------------------
# iBlocklist
# https://www.iblocklist.com/lists.php
# http://bluetack.co.uk/forums/index.php?autocom=faq&CODE=02&qid=17

# we only keep the proxies IPs (tor IPs are not parsed)
DO_NOT_REDISTRIBUTE[ib_bluetack_proxies.ipset]="1"
update ib_bluetack_proxies $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=xoebmbyexwuiogmbyprb&fileformat=p2p&archiveformat=gz" \
	p2p_gz_proxy \
	"anonymizers" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Open Proxies IPs list (without TOR)" \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_spyware.netset]="1"
update ib_bluetack_spyware $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=llvtlsjyoyiczbkjsxpf&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk known malicious SPYWARE and ADWARE IP Address ranges. It is compiled from various sources, including other available Spyware Blacklists, HOSTS files, from research found at many of the top Anti-Spyware forums, logs of Spyware victims and also from the Malware Research Section here at Bluetack." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_badpeers.ipset]="1"
update ib_bluetack_badpeers $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=cwworuawihqvocglcoss&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk IPs that have been reported for bad deeds in p2p." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_hijacked.netset]="1"
update ib_bluetack_hijacked $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=usrcshglbiilevmyfhse&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk hijacked IP-Blocks. # Contains hijacked IP-Blocks and known IP-Blocks that are used to deliver Spam. This list is a combination of lists with hijacked IP-Blocks. Hijacked IP space are IP blocks that are being used without permission by organizations that have no relation to original organization (or its legal successor) that received the IP block. In essence it's stealing of somebody else's IP resources." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_webexploit.ipset]="1"
update ib_bluetack_webexploit $[12*60] 0 ipv4 ip \
	"http://list.iblocklist.com/?list=ghlzqtqxnzctvvajwwag&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk web server hack and exploit attempts. IP addresses related to current web server hack and exploit attempts that have been logged by Bluetack or can be found in and cross referenced with other related IP databases. Malicious and other non search engine bots will also be listed here, along with anything found that can have a negative impact on a website or webserver such as proxies being used for negative SEO hijacks, unauthorised site mirroring, harvesting, scraping, snooping and data mining / spy bot / security & copyright enforcement companies that target and continuosly scan webservers." \
	"iBlocklist.com" "https://www.iblocklist.com/"

# The Level1 list is recommended for general P2P users, but it all comes
# down to your personal choice.
DO_NOT_REDISTRIBUTE[ib_bluetack_level1.netset]="1"
update ib_bluetack_level1 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 1 (for use in p2p): Companies or organizations who are clearly involved with trying to stop filesharing (e.g. Baytsp, MediaDefender, Mediasentry a.o.). Companies which anti-p2p activity has been seen from. Companies that produce or have a strong financial interest in copyrighted material (e.g. music, movie, software industries a.o.). Government ranges or companies that have a strong financial interest in doing work for governments. Legal industry ranges. IPs or ranges of ISPs from which anti-p2p activity has been observed. Basically this list will block all kinds of internet connections that most people would rather not have during their internet travels." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_level2.netset]="1"
update ib_bluetack_level2 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=gyisgnzbhppbvsphucsw&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 2 (for use in p2p). General corporate ranges. Ranges used by labs or researchers. Proxies." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_level3.netset]="1"
update ib_bluetack_level3 $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=uwnukjqktoggdknzrhgh&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk Level 3 (for use in p2p). Many portal-type websites. ISP ranges that may be dodgy for some reason. Ranges that belong to an individual, but which have not been determined to be used by a particular company. Ranges for things that are unusual in some way. The L3 list is aka the paranoid list." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_edu.netset]="1"
update ib_bluetack_edu $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=imlmncgrkbnacgcwfjvh&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk IP list with all known Educational Institutions." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_rangetest.netset]="1"
update ib_bluetack_rangetest $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=plkehquoahljmyxjixpu&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk suspicious IPs that are under investigation." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_bogons.netset]="1"
update ib_bluetack_bogons $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=gihxqmhyunbxhbmgqrla&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"unroutable" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk unallocated address space." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_ads.netset]="1"
update ib_bluetack_ads $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=dgxtneitpuvgqqcpfulq&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk IPs advertising trackers and a short list of bad/intrusive porn sites." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_ms.netset]="1"
update ib_bluetack_ms $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=xshktygkujudfnjfioro&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk with all the known Microsoft ranges." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_spider.netset]="1"
update ib_bluetack_spider $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=mcvxsnihddgutbjfbghy&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, intended to be used by webmasters to block hostile spiders from their web sites." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_dshield.netset]="1"
update ib_bluetack_dshield $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=xpbqleszmajjesnzddhv&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, Contains known Hackers and such people in it." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_iana_reserved.netset]="1"
update ib_bluetack_iana_reserved $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=bcoepfyewziejvcqyhqo&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"unroutable" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, IANA Reserved IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_iana_private.netset]="1"
update ib_bluetack_iana_private $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=cslpybexmxyuacbyuvib&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"unroutable" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, IANA Private IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_iana_multicast.netset]="1"
update ib_bluetack_iana_multicast $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=pwqnlynprfgtjbgqoizj&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"unroutable" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, IANA Multicast IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_fornonlancomputers.netset]="1"
update ib_bluetack_fornonlancomputers $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=jhaoawihmfxgnvmaqffp&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, IP blocklist for non-LAN computers." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_exclusions.netset]="1"
update ib_bluetack_exclusions $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=mtxmiireqmjzazcsoiem&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, exclusions." \
	"iBlocklist.com" "https://www.iblocklist.com/"

DO_NOT_REDISTRIBUTE[ib_bluetack_forumspam.netset]="1"
update ib_bluetack_forumspam $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ficutxiwawokxlcyoeye&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"abuse" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, forum spam." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_pedophiles $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=dufcxgnbjsdwmwctgfuj&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of BlueTack.co.uk, IP ranges of people who we have found to be sharing child pornography in the p2p community." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_cruzit_web_attacks $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=czvaehmjpsnwwttrdoyl&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"attacks" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of CruzIT list with individual IP addresses of compromised machines scanning for vulnerabilities and DDOS attacks." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_yoyo_adservers $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=zhogegszwduurnvsyhdf&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of pgl.yoyo.org ad servers" \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_spamhaus_drop $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=zbdlwrqkabxbcppvrnos&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of spamhaus.org DROP (Don't Route Or Peer) list." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_abuse_zeus $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ynkdjqsjyfmilsgbogqf&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of zeustracker.abuse.ch IP blocklist that contains IP addresses which are currently beeing tracked on the abuse.ch ZeuS Tracker." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_abuse_spyeye $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=zvjxsfuvdhoxktpeiokq&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of spyeyetracker.abuse.ch IP blocklist." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_abuse_palevo $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=erqajhwrxiuvjxqrrwfj&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of palevotracker.abuse.ch IP blocklist." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_ciarmy_malicious $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=npkuuhuxcsllnhoamkvm&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"reputation" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of ciarmy.com IP blocklist. Based on information from a network of Sentinel devices deployed around the world, they compile a list of known bad IP addresses. Sentinel devices are uniquely positioned to pick up traffic from bad guys without requiring any type of signature-based or rate-based identification. If an IP is identified in this way by a significant number of Sentinels, the IP is malicious and should be blocked." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_malc0de $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=pbqcylkejciyhmwttify&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"malware" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of malc0de.com IP blocklist. Addresses that have been indentified distributing malware during the past 30 days." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_cidr_report_bogons $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=lujdnbasfaaixitgmxpp&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"unroutable" \
	"[iBlocklist.com](https://www.iblocklist.com/) version of cidr-report.org IP list of Unallocated address space." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_onion_router $[12*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=togdoptykrlolpddwbvz&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"anonymizers" \
	"[iBlocklist.com](https://www.iblocklist.com/) The Onion Router IP addresses." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_apple $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=aphcqvpxuqgrkgufjruj&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Apple IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_logmein $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=tgbankumtwtrzllndbmb&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) LogMeIn IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_steam $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=cnxkgiklecdaihzukrud&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Steam IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_xfire $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ppqqnyihmcrryraaqsjo&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) XFire IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_blizzard $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ercbntshuthyykfkmhxc&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Blizzard IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_ubisoft $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=etmcrglomupyxtaebzht&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Ubisoft IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_nintendo $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=pevkykuhgaegqyayzbnr&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Nintendo IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_activision $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=gfnxlhxsijzrcuxwzebb&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Activision IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_sony_online $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=tukpvrvlubsputmkmiwg&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Sony Online Entertainment IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_crowd_control $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=eveiyhgmusglurfmjyag&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Crowd Control Productions IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_linden_lab $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=qnjdimxnaupjmpqolxcv&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Linden Lab IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_electronic_arts $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=ejqebpcdmffinaetsvxj&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Electronic Arts IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_square_enix $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=odyaqontcydnodrlyina&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Square Enix IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_ncsoft $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=mwjuwmebrnzyyxpbezxu&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) NCsoft IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_riot_games $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=sdlvfabdjvrdttfjotcy&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Riot Games IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_punkbuster $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=zvwwndvzulqcltsicwdg&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Punkbuster IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_joost $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=alxugfmeszbhpxqfdits&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Joost IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_pandora $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=aevzidimyvwybzkletsg&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Pandora IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_org_pirate_bay $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=nzldzlpkgrcncdomnttb&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) The Pirate Bay IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_aol $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=toboaiysofkflwgrttmb&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) AOL IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_comcast $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=rsgyxvuklicibautguia&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Comcast IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_cablevision $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=dwwbsmzirrykdlvpqozb&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Cablevision IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_verizon $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=cdmdbprvldivlqsaqjol&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Verizon IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_att $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=grbtkzijgrowvobvessf&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) AT&T IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_twc $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=aqtsnttnqmcucwrjmohd&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Time Warner Cable IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_charter $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=htnzojgossawhpkbulqw&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Charter IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_qwest $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=jezlifrpefawuoawnfez&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Qwest IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_embarq $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=twdblifaysaqtypevvdp&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Embarq IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_suddenlink $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=psaoblrwylfrdsspfuiq&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Suddenlink IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

update ib_isp_sprint $[24*60] 0 ipv4 both \
	"http://list.iblocklist.com/?list=hngtqrhhuadlceqxbrob&fileformat=p2p&archiveformat=gz" \
	p2p_gz \
	"organizations" \
	"[iBlocklist.com](https://www.iblocklist.com/) Sprint IPs." \
	"iBlocklist.com" "https://www.iblocklist.com/"

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
# we don't have yet the license to add this script here
# (the script is ours, but sorbs.net is very sceptical about this)

DO_NOT_REDISTRIBUTE[sorbs_dul.netset]="1"
update sorbs_dul 1 0 ipv4 both "" \
	cat \
	"spam" "[Sorbs.net](https://www.sorbs.net/) Dynamic IP Addresses." \
	"Sorbs.net" "https://www.sorbs.net/"

#DO_NOT_REDISTRIBUTE[sorbs_socks.netset]="1"
#update sorbs_socks 1 0 ipv4 both "" \
#	cat \
#	"anonymizers" \
#	"[Sorbs.net](https://www.sorbs.net/) List of open SOCKS proxy servers." \
#	"Sorbs.net" "https://www.sorbs.net/"

#DO_NOT_REDISTRIBUTE[sorbs_http.netset]="1"
#update sorbs_http 1 0 ipv4 both "" \
#	cat \
#	"anonymizers" \
#	"[Sorbs.net](https://www.sorbs.net/) List of open HTTP proxies." \
#	"Sorbs.net" "https://www.sorbs.net/"

#DO_NOT_REDISTRIBUTE[sorbs_misc.netset]="1"
#update sorbs_misc 1 0 ipv4 both "" \
#	cat \
#	"anonymizers" \
#	"[Sorbs.net](https://www.sorbs.net/) List of open proxy servers (not listed in HTTP or SOCKS)." \
#	"Sorbs.net" "https://www.sorbs.net/"

# all the above are here:
DO_NOT_REDISTRIBUTE[sorbs_anonymizers.netset]="1"
update sorbs_anonymizers 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of open HTTP and SOCKS proxies." \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_zombie.netset]="1"
update sorbs_zombie 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of networks hijacked from their original owners, some of which have already used for spamming." \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_smtp.netset]="1"
update sorbs_smtp 1 0 ipv4 both "" \
	cat "spam" "[Sorbs.net](https://www.sorbs.net/) List of SMTP Open Relays." \
	"Sorbs.net" "https://www.sorbs.net/"

# this is HUGE !!!
#DO_NOT_REDISTRIBUTE[sorbs_spam.netset]="1"
#update sorbs_spam 1 0 ipv4 both "" \
#	remove_comments \
#	"spam" \
#	"[Sorbs.net](https://www.sorbs.net/) List of hosts that have been noted as sending spam/UCE/UBE at any time, and not subsequently resolving the matter and/or requesting a delisting. (Includes both sorbs_old_spam and sorbs_escalations)." \
#	"Sorbs.net" "https://www.sorbs.net/"

#DO_NOT_REDISTRIBUTE[sorbs_old_spam.netset]="1"
#update sorbs_old_spam 1 0 ipv4 both "" \
#	remove_comments \
#	"spam" \
#	"[Sorbs.net](https://www.sorbs.net/) List of hosts that have been noted as sending spam/UCE/UBE within the last year. (includes sorbs_recent_spam)." \
#	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_new_spam.netset]="1"
update sorbs_new_spam 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of hosts that have been noted as sending spam/UCE/UBE within the last 48 hours" \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_recent_spam.netset]="1"
update sorbs_recent_spam 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of hosts that have been noted as sending spam/UCE/UBE within the last 28 days (includes sorbs_new_spam)" \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_web.netset]="1"
update sorbs_web 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of IPs which have spammer abusable vulnerabilities (e.g. FormMail scripts)" \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_escalations.netset]="1"
update sorbs_escalations 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) Netblocks of spam supporting service providers, including those who provide websites, DNS or drop boxes for a spammer. Spam supporters are added on a 'third strike and you are out' basis, where the third spam will cause the supporter to be added to the list." \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_noserver.netset]="1"
update sorbs_noserver 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) IP addresses and Netblocks of where system administrators and ISPs owning the network have indicated that servers should not be present." \
	"Sorbs.net" "https://www.sorbs.net/"

DO_NOT_REDISTRIBUTE[sorbs_block.netset]="1"
update sorbs_block 1 0 ipv4 both "" \
	cat \
	"spam" \
	"[Sorbs.net](https://www.sorbs.net/) List of hosts demanding that they never be tested by SORBS." \
	"Sorbs.net" "https://www.sorbs.net/"

# -----------------------------------------------------------------------------
# FireHOL lists

merge firehol_level1 "attacks" "An ipset made from blocklists that provide the maximum of protection, with the minimum of false positives. Suitable for basic protection on all systems." \
	fullbogons dshield feodo palevo sslbl zeus_badips spamhaus_drop spamhaus_edrop bambenek_c2

merge firehol_level2 "attacks" "An ipset made from blocklists that track attacks and abuse, during the last one or two days." \
	openbl_1d dshield_1d blocklist_de stopforumspam_1d botscout_1d greensnow

merge firehol_level3 "attacks" "An ipset made from blocklists that track attacks, spyware, viruses. It includes IPs than have been reported or detected in the last 30 days." \
	openbl_30d dshield_30d stopforumspam_30d virbl malc0de shunlist malwaredomainlist bruteforceblocker \
	ciarmy cleanmx_viruses snort_ipfilter ib_bluetack_spyware ib_bluetack_hijacked ib_bluetack_webexploit \
	php_commenters php_dictionary php_harvesters php_spammers iw_wormlist zeus maxmind_proxy_fraud \
	dragon_http dragon_sshpauth dragon_vncprobe bambenek_c2

merge firehol_proxies "anonymizers" "An ipset made from all sources that track open proxies. It includes IPs reported or detected in the last 30 days." \
	ib_bluetack_proxies maxmind_proxy_fraud proxyrss_30d proxz_30d \
	ri_connect_proxies_30d ri_web_proxies_30d xroxy_30d \
	proxyspy_30d sslproxies_30d socks_proxy_30d proxylists_30d

merge firehol_anonymous "anonymizers" "An ipset that includes all the anonymizing IPs of the world." \
	firehol_proxies anonymous bm_tor dm_tor tor_exits



# -----------------------------------------------------------------------------
# TODO
#
# add sets
# - https://github.com/Blueliv/api-python-sdk/wiki/Blueliv-REST-API-Documentation
# - https://atlas.arbor.net/summary/attacks.csv
# - https://atlas.arbor.net/summary/botnets.csv
# - https://atlas.arbor.net/summary/fastflux.csv
# - https://atlas.arbor.net/summary/phishing.csv
# - https://atlas.arbor.net/summary/scans.csv
# - spam: http://www.reputationauthority.org/toptens.php
# - spam: https://www.juniper.net/security/auto/spam/
# - spam: http://toastedspam.com/deny
# - spam: http://rss.uribl.com/reports/7d/dns_a.html
# - spam: http://spamcop.net/w3m?action=map;net=cmaxcnt;mask=65535;sort=spamcnt;format=text
# - https://gist.github.com/BBcan177/3cbd01b5b39bb3ce216a
# - https://github.com/rshipp/awesome-malware-analysis

# obsolete - these do not seem to be updated any more
# - http://www.cyber-ta.org/releases/malware/SOURCES/Attacker.Cumulative.Summary
# - http://www.cyber-ta.org/releases/malware/SOURCES/CandC.Cumulative.Summary
# - https://vmx.yourcmc.ru/BAD_HOSTS.IP4
# - http://www.geopsy.org/blacklist.html
# - http://www.malwaregroup.com/ipaddresses/malicious

# user specific features
# - allow the user to request an email if a set increases by a percentage or number of unique IPs
# - allow the user to request an email if a set matches more than X entries of one or more other set

# intended use    : 20:firewall_block_all 10:firewall_block_service 02:[reputation_generic] 01:[reputation_specific] 00:[antispam] 
# false positives : 3:none 2:rare 1:some 0:[common]
# poisoning       : 0:[not_checked] 1:reactive 2:predictive 3:not_possible
# grade           : 0:[personal] 1:community 2:commercial 3:carrier / service_provider
# protection      : 0:[both] 1:inbound 2:outbound
# license         : 


# -----------------------------------------------------------------------------
# updates
update_web

# commit changes to git (does nothing if not enabled)
commit_to_git

# let the cleanup function exit with success
PROGRAM_COMPLETED=1
