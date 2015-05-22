#!/bin/bash
#
# FireHOL - A firewall for humans...
#
#   Copyright
#
#       Copyright (C) 2003-2015 Costa Tsaousis <costa@tsaousis.gr>
#       Copyright (C) 2012-2015 Phil Whineray <phil@sanewall.org>
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

# -----------------------------------------------------------------------------
# OVERVIEW
#
# This program will tail the iptables kernel log, extract SRC/DST IP addresses
# from it, do DNSBL lookups for them, score them and according to this score
# add them to an ipset. This ipset may be used by a firewall rule to block
# further access.
#
# So, initially an attacker will get access, but after a few seconds, his IP
# might be blocked.
#
# This program itself just manipulates ipsets.
# It does not alter your firewall - it does not generate or execute iptables
# statements.
#
#
# -----------------------------------------------------------------------------
# HOW IT WORKS
#
# The configuration file is /etc/firehol/dnsbl-ipset.conf
# It will be generated with defaults, on first run.
# 
# 1. It tails the iptables log file given by IPTABLES_LOG.
#
# 2. It greps for lines containing ULOG_MATCH, it ignores all other.
#    Normally, you should log some packets using iptables, and then
#    set the iptables log text to ULOG_MATCH, to process these lines only.
#
# 3. If the line contains SRC=<IPv4 IP> and DST=<IPv4 IP> it extracts these
#    IPs from the log file.
#    It is safe to tail the system log or a log file containing more than
#    just iptables logs, the program will process only what it understands.
#
# 4. For each IP extracted (both SRC and DST), it first checks if they
#    appear in EXCLUSION_IPSETS, BLACKLIST_IPSET, CACHE_IPSET
#    If an IP is found in any of the above, it is ignored.
#
# 5. For each IP not found on any of the ipsets above, it does the following:
#
# 6. Adds the IP to the CACHE_IPSET with options set by CACHE_IPSET_OPTIONS.
#    These options allow setting a timeout, after which the IP will be
#    re-checked.
#
# 7. It generates DNSBL hostnames to be resolved, for all DNSBLs given in the
#    configuration.
#
# 8. These hostnames are resolved with 'adnshost' an excellent asynchronous
#    client resolver with machine readable output. adnshost is part of
#    adns-tools.
#
# 9. Each successful DNS resolution is scored according to the configuration.
#    The configuration allows you to control scoring DNS resolutions to
#    suit your needs.
#    The default scoring is suitable for servers servicing users, it favours
#    dynamic IPs and penalizes server IPs.
#
# 10. The score of each successfull DNS lookup is added to the total score
#     for each IP.
#
# 11. When the DNS resolution for an IP completes for all DNSBLs configured,
#     it takes a decision:
#
# 12. If the total score for an IP is above BLACKLIST_SCORE, it adds the IP
#     to the BLACKLIST_IPSET, otherwise, it ignores it.
# 
#
# -----------------------------------------------------------------------------
# OTHER FEATURES
#
# a. The speed of DNSBL resolution is controlled by DELAY_BETWEEN_CHECKS.
#    The default is 0.2 which means 5 DNS lookups per second per DNSBL.
#
# b. If the DNS resolution is slow, the program will start throttling.
#    This is controlled with THROTTLE_THRESHOLD which controls how many IPs
#    should be in the queue (currently being resolved) for the program to
#    work without any delays.
#
# c. It saves 4 log files (in the dir set by LOG_DIR):
#      1. ips.log - all the IPs checked (one line per IP)
#      2. matches.log - all the DNSBLs that responded (one line per resolution)
#      3. clean.log - all the IPs with low score (one line per IP)
#      4. blacklisted.log - all the IPs with high score (one line per IP)
#
# d. The blacklisted ipset will include a comment so that you will know
#    why each IP was blacklisted (which DNSBLs matched it, with which score)
#
# e. The BLACKLIST_IPSET has to exist prior to running this script.
#    The program will give you the command to add in firehol.conf
#

PROGRAM_FILE="${0}"

# lock
# if we run already, the script will exit
[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -en "$0" "$0" "$@" || :

if [ ! "${UID}" = 0 ]
	then
	echo >&2 "Only root can run this program."
	exit 1
fi

RUNNING_ON_TERMINAL=0
if [ "z$1" = "z-nc" ]
then
	shift
else
	test -t 2 && RUNNING_ON_TERMINAL=1
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
fi


# -----------------------------------------------------------------------------
# functions to parse the configuration file

declare -A DNSBL=()
declare -A DNSBL_SCORES=()
declare -a work_dnsbl=()
dnsbl() {
	local score="${1}" list=
	shift

	if [ "${score}" = "clear" ]
	then
		DNSBL=()
		DNSBL_SCORES=()
		work_dnsbl=()
		return 0
	fi

	work_dnsbl=("${@}")

	for list in "${work_dnsbl[@]}"
	do
		DNSBL_SCORES[${list}]=$[score]
		DNSBL[${list}]="${list}"
	done
}

score() {
	local score="${1}" result= list=
	shift

	for result in "${@}"
	do
		for list in "${work_dnsbl[@]}"
		do
			DNSBL_SCORES[${result}/${work_dnsbl}]=$[score]
		done
	done
}


# -----------------------------------------------------------------------------
# Configuration

# --- BEGIN OF DNSBL-IPSET DEFAULTS ---

# where is the iptables log file to tail?
# leave empty for auto-detection - may not work for you - please set it
IPTABLES_LOG=""

# which string to find in the log?
ULOG_MATCH="AUDIT"

# where to put our logs?
LOG_DIR="/var/log/dnsbl-ipset"

# which IPSETs to examine to exclude IPs from checking?
# space separated list of any number of ipsets.
# add here any ipsets that include IPs that should never be blacklisted.
EXCLUSION_IPSETS="bogons fullbogons whitelist"

# which IPSET will receive the blacklisted IPs?
# this has to exist - on first error to add the program will exit
# this ipset will also be checked for excluding new queries
BLACKLIST_IPSET="dnsbl"

# what additional options to give when adding an IP to the blacklist ipset?
BLACKLIST_IPSET_OPTIONS="timeout $[7 * 24 * 3600]"

# set this to 1 to have comments on the blacklist ipset
# the comments will include the score and DNSBLs matched it
BLACKLIST_IPSET_COMMENTS=1

# which IPSET will cache the checked IPs?
# this ipset will also be checked for excluding new queries
# it will be automatically created if it does not exist
CACHE_IPSET="dnsbl_cache"

# what additional options to give when adding IPs to the CACHE_IPSET?
CACHE_IPSET_OPTIONS="timeout $[24 * 3600]"

# how to create the cache ipset - if it does not exist?
# this ipset will be created only if it does not exist
CACHE_IPSET_CREATE_OPTIONS="timeout $[24 * 3600] maxelem 2000000"

# which is the BLACKLIST score?
# any IP that will get a score above or equal to this, will be
# added to the BLACKLIST_IPSET
BLACKLIST_SCORE="100"

# delay to issue between IP checks
# if you lower this a lot, DNSBLs will refuse to talk to you
DELAY_BETWEEN_CHECKS="0.2"

# when we will have this many IP checks in progress
# we will stop processing until this drops below this point
THROTTLE_THRESHOLD="500"

# where is the throttle lock file?
THROTTLE_LOCK_FILE="/var/run/dnsbl-ipset.lock"

# enable this for more logging
DEBUG=0


# -----------------------------------------------------------------------------
# Custom Check on Blacklisted IPs

# this function is called for every IP the tool is going to blacklist
blacklist_check() {
	local counter="${1}" ip="${2}" score="${3}"
	shift 3
	# counter = the number of DNSBLs matched it
	# ip      = the IP that is going to be blacklisted
	# score   = the score this IP got from the all lists
	# the rest of the parameters are the lists matched it

	# do anything you like here to check the IP

	# return 0 = ok, blacklist it
	# return 1 = no, don't blacklist it
	return 0
}


# -----------------------------------------------------------------------------
# Default Score Configuration

# clear any previous configuration
dnsbl clear

# the default settings have been set to benefit dynamic IP ranges that might be used by users

# TEMPLATE
# >> dnsbl DEFAULT_SCORE DNSBL
#
# The DEFAULT_SCORE will be used if a more specific score is not given
#
# optionally, followed by:
# >>   score SCORE IP_RESOLVED
#
# IP_RESOLVED is looked up like this:
# If the DNS resolution on DNSBL dnsb.org gives 127.1.2.3, the program will lookup
# IP_RESOLVED in this order (the first matched will be used):
#
#     127.1.2.3
#     127.1.x.3
#     127.x.x.3
#     127.1.2.3
#     127.1.2
#     127.1.x
#     127.x.2
#     127.1
#     127.x
#     127
#     DEFAULT_SCORE
#

dnsbl 0 zen.spamhaus.org
	score  100 127.0.0.2  # sbl.spamhaus.org, Spamhaus SBL Data, Static UBE sources, verified spam services (hosting or support) and ROKSO spammers
	score  100 127.0.0.3  # sbl.spamhaus.org, Spamhaus SBL CSS Data, Static UBE sources, verified spam services (hosting or support) and ROKSO spammers
	score   45 127.0.0.4  # xbl.spamhaus.org, CBL Data, Illegal 3rd party exploits, including proxies, worms and trojan exploits
	score   45 127.0.0.5  # xbl.spamhaus.org = Illegal 3rd party exploits, including proxies, worms and trojan exploits
	score   45 127.0.0.6  # xbl.spamhaus.org = Illegal 3rd party exploits, including proxies, worms and trojan exploits
	score   45 127.0.0.7  # xbl.spamhaus.org = Illegal 3rd party exploits, including proxies, worms and trojan exploits
	score -200 127.0.0.10 # pbl.spamhaus.org = End-user Non-MTA IP addresses set by ISP outbound mail policy
	score -200 127.0.0.11 # pbl.spamhaus.org = End-user Non-MTA IP addresses set by ISP outbound mail policy
	score -500 127.0.2    # Spamhaus Whitelists

dnsbl 0 dnsbl.sorbs.net
	score  200 127.0.0.2 # http.dnsbl.sorbs.net - List of Open HTTP Proxy Servers
	score  200 127.0.0.3 # socks.dnsbl.sorbs.net - List of Open SOCKS Proxy Server
	score  200 127.0.0.4 # misc.dnsbl.sorbs.net - List of open Proxy Servers not listed in the SOCKS or HTTP lists
	score   25 127.0.0.5 # smtp.dnsbl.sorbs.net - List of Open SMTP relay servers
	score   25 127.0.0.6 # new.spam.dnsbl.sorbs.net - List of hosts that have been noted as sending spam/UCE/UBE to the admins of SORBS within the last 48 hours.
	score  100 127.0.0.7 # web.dnsbl.sorbs.net - List of web (WWW) servers which have spammer abusable vulnerabilities (e.g. FormMail scripts) Note: This zone now includes non-webserver IP addresses that have abusable vulnerabilities.
	score    0 127.0.0.8 # block.dnsbl.sorbs.net - List of hosts demanding that they never be tested by SORBS.
	score  100 127.0.0.9 # zombie.dnsbl.sorbs.net - List of networks hijacked from their original owners, some of which have already used for spamming.
	score -200 127.0.0.10 # dul.dnsbl.sorbs.net - Dynamic IP Address ranges (NOT a Dial Up list!)
	score    0 127.0.0.11 # badconf.rhsbl.sorbs.net - List of domain names where the A or MX records point to bad address space.
	score    0 127.0.0.12 # nomail.rhsbl.sorbs.net - List of domain names where the owners have indicated no email should ever originate from these domains.
	score    0 127.0.0.14 # noserver.dnsbl.sorbs.net - IP addresses and Netblocks of where system administrators and ISPs owning the network have indicated that servers should not be present.

dnsbl 0 all.spamrats.com
	score -200 127.0.0.36 # Dyna, IP Addresses that have been found sending an abusive amount of connections, or trying too many invalid users at ISP and Telco's mail servers, and are also known to conform to a naming convention that is indicative of a home connection or dynamic address space.
	score   45 127.0.0.37 # Noptr, IP Addresses that have been found sending an abusive amount of connections, or trying too many invalid users at ISP and Telco's mail servers, and are also known to have no reverse DNS, a technique often used by bots and spammers
	score   45 127.0.0.38 # Spam, IP Addresses that do not conform to more commonly known threats, and is usually because of compromised servers, hosts, or open relays. However, since there is little accompanying data this list COULD have false-positives, and we suggest that it only is used if you support a more aggressive stance

dnsbl 0 hostkarma.junkemailfilter.com
	score -200 127.0.0.1 # whitelist
	score  100 127.0.0.2 # blacklist
	score   35 127.0.0.3 # yellowlist
	score   45 127.0.0.4 # brownlist
	score -200 127.0.0.5 # no blacklist

dnsbl 0 rep.mailspike.net # IP Reputation
	score  200 127.0.0.10 # Worst possible
	score  150 127.0.0.11 # Very bad
	score  100 127.0.0.12 # Bad
	score   35 127.0.0.13 # Suspicious
	score   25 127.0.0.14 # Neutral - probably spam
	score  -50 127.0.0.15 # Neutral
	score  -70 127.0.0.16 # Neutral - probably legit
	score -100 127.0.0.17 # Possibly legit sender
	score -150 127.0.0.18 # Good
	score -200 127.0.0.19 # Very Good
	score -250 127.0.0.20 # Excellent

dnsbl 45 z.mailspike.net # participating in a distributed spam wave in the last 48 hours

dnsbl 35 all.s5h.net

dnsbl 45 b.barracudacentral.org # Barracuda Reputation Block List, http://barracudacentral.org/rbl/listing-methodology

dnsbl 25 spam.dnsbl.sorbs.net #  spam.dnsbl.sorbs.net - List of hosts that have been noted as sending spam/UCE/UBE to the admins of SORBS at any time,  and not subsequently resolving the matter and/or requesting a delisting. (Includes both old.spam.dnsbl.sorbs.net and escalations.dnsbl.sorbs.net).

# cbl.abuseat.org may be also included in xbl.spamhaus.org
# in this case, it should not be added again.
#dnsbl 200 cbl.abuseat.org # The CBL only lists IPs exhibiting characteristics which are specific to open proxies of various sorts (HTTP, socks, AnalogX, wingate, Bagle call-back proxies etc) and dedicated Spam BOTs (such as Cutwail, Rustock, Lethic etc) which have been abused to send spam, worms/viruses that do their own direct mail transmission, or some types of trojan-horse or "stealth" spamware, dictionary mail harvesters etc.

dnsbl 25 dnsbl.justspam.org # If an IP that we never got legit email from is seen spamming and said IP is already listed by at least one of the other well-known and independent blacklists, then it is added to our blacklist dnsbl.justspam.org.

dnsbl 100 korea.services.net # South Korean IP address space - this is not necessarily bad

dnsbl 0 rbl.megarbl.net
	score 25 127.0.0.2 # spam source

#dnsbl 0 dnsbl.inps.de # is listing IPs if they are listed on other DNSBLs

dnsbl 0 bl.spamcop.net
	score 25 127.0.0.2 # spam source

dnsbl 0 db.wpbl.info
	score 25 127.0.0.2 # spam source

dnsbl 0 dnsbl.anticaptcha.net
	score 25 127.0.0.3 # spam source
	score 25 127.0.0.10 # spam source

dnsbl 0 ubl.unsubscore.com
	score 25 127.0.0.2 # spam source

dnsbl 0 bl.tiopan.com
	score 10 127.0.0.2 # spam source

dnsbl -200 list.dnswl.org # all responses include valid mail servers

dnsbl 25 ix.dnsbl.manitu.net # spam source?

dnsbl 25 psbl.surriel.com # spam source


# --- other lists to choose from ---
# access.redhawk.org
# blackholes.five-ten-sg.com
# blackholes.wirehub.net
# blacklist.sci.kun.nl
# blacklist.woody.ch
# bl.emailbasura.org
# blocked.hilli.dk
# bl.spamcannibal.org
# bogons.cymru.com
# cblless.anti-spam.org.cn
# cdl.anti-spam.org.cn
# combined.abuse.ch
# combined.rbl.msrbl.net
# dev.null.dk
# dialup.blacklist.jippg.org
# dialups.mail-abuse.org
# dialups.visi.com
# dnsbl-1.uceprotect.net
# dnsbl-2.uceprotect.net
# dnsbl-3.uceprotect.net
# dnsbl.abuse.ch
# dnsbl.antispam.or.id
# dnsbl.cyberlogic.net
# dnsbl.dronebl.org
# dnsbl.kempt.net
# dnsbl.tornevall.org
# drone.abuse.ch
# dynip.rothen.com
# exitnodes.tor.dnsbl.sectoor.de
# hil.habeas.com
# images.rbl.msrbl.net
# intruders.docs.uu.se
# ips.backscatterer.org
# mail-abuse.blacklist.jippg.org
# msgid.bl.gweep.ca
# no-more-funn.moensted.dk
# opm.tornevall.org
# phishing.rbl.msrbl.net
# proxy.bl.gweep.ca
# pss.spambusters.org.ar
# rbl.interserver.net
# rbl.schulte.org
# rbl.snark.net
# relays.bl.gweep.ca
# relays.bl.kundenserver.de
# relays.nether.net
# short.rbl.jp
# spam.abuse.ch
# spamguard.leadmon.net
# spamlist.or.kr
# spam.olsentech.net
# spamrbl.imp.ch
# spam.rbl.msrbl.net
# spamsources.fabel.dk
# tor.dnsbl.sectoor.de
# virbl.bit.nl
# virus.rbl.jp
# virus.rbl.msrbl.net
# wormrbl.imp.ch

# --- END OF DNSBL-IPSET DEFAULTS ---


# -----------------------------------------------------------------------------
# pre-configuration checks

adnshost=$(which adnshost 2>/dev/null)
if [ -z "${adnshost}" ]
	then
	echo >&2 "Cannot find adnshost - please install adns or adns-tools."
	exit 1
fi

ipset=$(which ipset 2>/dev/null)
if [ -z "${ipset}" ]
	then
	echo >&2 "Cannot find ipset - please install it."
	exit 1
fi


# -----------------------------------------------------------------------------
# configuration file management

FIREHOL_CONFIG_DIR="/etc/firehol"
# Generate config file


if [ ! -f "${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf" ]
then
	grep -E "^# --- BEGIN OF DNSBL-IPSET DEFAULTS ---" -A 1000 "${PROGRAM_FILE}" |\
		grep -E "^# --- END OF DNSBL-IPSET DEFAULTS ---" -B 1000 >"${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf" || exit 1
	chown root:root "${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf" || exit 1
	chmod 600 "${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf" || exit 1

	echo >&2 "Generated default config file '${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf'."
	echo >&2 "Please run me again to execute..."
	exit 1
fi

source "${FIREHOL_CONFIG_DIR}/dnsbl-ipset.conf" || exit 1


# -----------------------------------------------------------------------------
# command line processing

if [ -z "${IPTABLES_LOG}" ]
	then
	for x in /var/log/ulogd/ulogd_syslogemu.log /var/log/ulogd/syslogemu.log
	do
		if [ -f "${x}" ]
			then
			IPTABLES_LOG="${x}"
			break
		fi
	done
fi

usage() {
	cat <<EOF

${PROGRAM_FILE} [file IPTABLES_LOG] [grep ULOG_MATCH] [test] [flush]

defaults:
IPTABLES_LOG="${IPTABLES_LOG}"
LOG_MATCH="${ULOG_MATCH}"

test	will show the IPs matched from the log file.
flush	will empty ${BLACKLIST_IPSET} and ${CACHE_IPSET} ipsets

EOF
	exit 0
}

TEST_SRC_DST=0
while [ ! -z "${1}" ]
do
	case "${1}" in
		match|search|grep|-s)
			ULOG_MATCH="${2}"
			shift
			;;

		file|tail|-f)
			IPTABLES_LOG="${2}"
			shift
			;;

		test|-t)
			TEST_SRC_DST=1
			RUNNING_ON_TERMINAL=0
			;;

		flush|clear|clean|restart)
			ipset --flush "${CACHE_IPSET}"
			ipset --flush "${BLACKLIST_IPSET}"
			echo >&2 "IP sets ${CACHE_IPSET} and ${BLACKLIST_IPSET} have been flushed."
			exit 0
			;;

		help|-h|--help) usage ;;
		*) echo >&2 "Cannot understand option '${1}'."; usage ;;
	esac
	shift
done


# -----------------------------------------------------------------------------
# post-configuration checks

[ ${DEBUG} -eq 1 ] && RUNNING_ON_TERMINAL=0

if [ -z "${IPTABLES_LOG}" -o ! -f "${IPTABLES_LOG}" ]
	then
	echo >&2 "Cannot find ulogd iptables log ${IPTABLES_LOG}"
	exit 1
fi

if [ ! -d "${LOG_DIR}" ]
	then
	mkdir -p "${LOG_DIR}" || exit 1
fi
cd "${LOG_DIR}" || exit 1

ipset --list "${BLACKLIST_IPSET}" >/dev/null
if [ $? -ne 0 ]
then
	echo >&2 "Cannot find BLACKLIST_IPSET '${BLACKLIST_IPSET}'."
	echo >&2 "Please add it in firehol.conf like this:"
	echo >&2 "ipset4 create ${BLACKLIST_IPSET} hash:ip timeout $[86400 * 7] maxelem 1000000 prevent_reset_on_restart comment"
	echo >&2 "And restart firehol to activate it."
	exit 1
fi

ipset --list "${CACHE_IPSET}" -t >/dev/null 2>&1
if [ $? -ne 0 ]
then
	ipset --create ${CACHE_IPSET} hash:ip ${CACHE_IPSET_CREATE_OPTIONS} || exit 1
fi

for ipset in ${EXCLUSION_IPSETS}
do
	ipset --list ${ipset} -t >/dev/null
	if [ $? -ne 0 ]
	then
		echo >&2 "ipset '${ipset}' does not exist. Please set EXCLUSION_IPSETS properly."
		exit 1
	fi
done

cleanup() {
	echo >&2 "Cleaning up..."

	echo >&2 "All done, bye..."
	trap exit EXIT
	trap exit HUP
	trap exit INT
	exit 0
}
trap cleanup EXIT
trap cleanup HUP
trap cleanup INT

# -----------------------------------------------------------------------------
# program functions

DNSBL_GET_SCORE="0"
dnsbl_get_score() {
	local reply="${1}" dnsbl="${2}" ip=() x=

	# parse the reply IP to its parts
	IFS="." read -ra ip <<< "${reply}"

	# check for a score all possible combinations
	# from more specific to more generic
	for x in \
		${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}/${dnsbl} \
		${ip[0]}.${ip[1]}.x.${ip[3]}/${dnsbl} \
		${ip[0]}.x.x.${ip[3]}/${dnsbl} \
		${ip[0]}.${ip[1]}.${ip[2]}/${dnsbl} \
		${ip[0]}.${ip[1]}.x/${dnsbl} \
		${ip[0]}.x.${ip[2]}/${dnsbl} \
		${ip[0]}.${ip[1]}/${dnsbl} \
		${ip[0]}.x/${dnsbl} \
		${ip[0]}/${dnsbl} \
		${dnsbl}
	do
		if [ ! -z "${DNSBL_SCORES[${x}]}" ]
			then

			# found it
			[ ${DEBUG} -eq 1 ] && echo >&2 "SCORE: ${x} = ${DNSBL_SCORES[${x}]}"
			DNSBL_GET_SCORE="${DNSBL_SCORES[${x}]}"
			return 0
		fi
	done

	# not found any
	echo >&2 "ERROR: SCORE NOT FOUND: ${reply}/${dnsbl}"
	DNSBL_GET_SCORE="0"
	return 0
}

match() {
	local reply="${1}" ip3="${2}" ip2="${3}" ip1="${4}" ip0="${5}" dnsbl= ip=
	shift 5
	dnsbl="${*}"
	dnsbl="${dnsbl// /.}"
	ip="${ip0}.${ip1}.${ip2}.${ip3}"

	# find the score
	dnsbl_get_score "${reply}" "${dnsbl}"
	local score="${DNSBL_GET_SCORE}"

	ADNS_COUNT[${ip}]=$[ ADNS_COUNT[${ip}] + 1 ]
	ADNS_SCORE[${ip}]=$[ ADNS_SCORE[${ip}] + score ]
	ADNS_LISTS[${ip}]="${ADNS_LISTS[${ip}]} ${score}/${reply}/${dnsbl}"

	# save the matches log
	echo "${score} ${ip} # ${reply} from ${dnsbl}" >>matches.log

	# let the user know
	[ ${DEBUG} -eq 1 ] && echo >&2 "MATCH (${score}, total ${ADNS_SCORE[${ip}]}): ${ip} on ${reply}/${dnsbl}"

	return 0
}

blacklist() {
	local counter="${1}" ip="${2}" tscore="${3}" comment=
	shift 3

	if [ ${counter} -eq 0 ]
		then
		comment="not matched by any list"
	elif [ ${counter} -eq 1 ]
		then
		comment="score ${tscore} from ${counter} list:${*}"
	else
		comment="score ${tscore} from ${counter} lists:${*}"
	fi

	if [ ${tscore} -ge ${BLACKLIST_SCORE} ]
		then
		blacklist_check ${counter} ${ip} ${tscore} "${@}"
		if [ $? -ne 0 ]
		then
			local d=$[tscore + 1 - BLACKLIST_SCORE]
			tscore=$[tscore - d]
			comment="score ${tscore} from custom check $[-d] and ${counter} lists:${*}"
		fi
	fi

	if [ ${tscore} -ge ${BLACKLIST_SCORE} ]
		then
		printf >&2 " + ${COLOR_BGRED}${COLOR_WHITE}${COLOR_BOLD} %-9.9s  %-15.15s ${COLOR_RESET}${COLOR_CYAN} # ${comment}${COLOR_RESET}\n" BLACKLIST "${ip}"
		echo "${ip} # ${comment}" >>blacklist.log

		# if it is already blacklisted, return
		ipset --test ${BLACKLIST_IPSET} ${ip} 2>/dev/null && return 1

		# blacklist it
		if [ ${BLACKLIST_IPSET_COMMENTS} -eq 1 ]
			then
			ipset --add ${BLACKLIST_IPSET} ${ip} ${BLACKLIST_IPSET_OPTIONS} comment "${comment:0:255}" || exit 1
		else
			ipset --add ${BLACKLIST_IPSET} ${ip} ${BLACKLIST_IPSET_OPTIONS} || exit 1
		fi

		return 0
	fi

	printf >&2 " - ${COLOR_BGGREEN}${COLOR_BLACK} %-9.9s ${COLOR_RESET} %-15.15s ${COLOR_CYAN} # ${comment}${COLOR_RESET}\n" CLEAN "${ip}"
	echo "${ip} # ${comment}" >>clean.log
	return 1
}

generate_dnsbl_hostnames() {
	if [[ "${1}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
		then

		# check if it is excluded
		local x=
		for x in ${EXCLUSION_IPSETS} ${CACHE_IPSET} ${BLACKLIST_IPSET}
		do
			ipset --test "${x}" "${1}" 2>/dev/null && return 1
		done

		# split the IP in its parts
		local ip=()
		IFS="." read -ra ip <<< "${1}"
		local i="${ip[0]}.${ip[1]}.${ip[2]}.${ip[3]}"

		# let the user know
		[ ${DEBUG} -eq 1 ] && echo >&2 "RECEIVED: ${i}"

		echo "${i}" >>ips.log

		# cache it
		ipset --add ${CACHE_IPSET} ${i} ${CACHE_IPSET_OPTIONS} || exit 1

		while [ -f "${THROTTLE_LOCK_FILE}" ]
		do
			[ ${DEBUG} -eq 1 ] && echo >&2 " >>> THROTLING: waiting..."
			sleep 1
		done

		# generate the lookup hostnames for all configured lists
		local x=
		for x in ${!DNSBL[@]}
		do
			echo "${ip[3]}.${ip[2]}.${ip[1]}.${ip[0]}.${x}"
		done
		return 0
	else
		# oops! this does not look like an IP
		echo >&2 "ERROR: INVALID SOURCE IP: ${1}"
		return 1
	fi
}

generate_hostnames_from_src_dst() {
	local last= a= b= x=

	if [ "${TEST_SRC_DST}" -eq 1 ]
		then
		cat >&2
		exit 0
	fi

	while read a b
	do
		[ "${a}" = "${b}" ] && a=
		[ "${a}" = "${last}" ] && a=
		[ "${b}" = "${last}" ] && b=

		for x in ${a} ${b}
		do
			generate_dnsbl_hostnames "${x}"
			[ ! -z "${DELAY_BETWEEN_CHECKS}" ] && sleep ${DELAY_BETWEEN_CHECKS}
			last="${x}"
		done
	done
}

declare -A ADNS_REMAINING=()
declare -A ADNS_COUNT=()
declare -A ADNS_SCORE=()
declare -A ADNS_LISTS=()
ADNS_COMPLETED=0
ADNS_BLACKLISTED=0
parse_adns_asynch() {
	local id n status t1 reason host dollar msg1 msg2 msg3 msg4 msg5 ip=() throttle="waiting"

	# remove the throttle lock file, if present
	[ -f "${THROTTLE_LOCK_FILE}" ] && rm "${THROTTLE_LOCK_FILE}"

	[ ${RUNNING_ON_TERMINAL} -eq 1 ] && spinner "${#ADNS_REMAINING[@]}, waiting for the first IP..."
	while read id n status t1 reason host dollar msg1 msg2 msg3 msg4 msg5
	do
		[ ${RUNNING_ON_TERMINAL} -eq 1 ] && spinner_end

		# split the host
		IFS="." read -ra ip <<< "${host}"
		local i="${ip[3]}.${ip[2]}.${ip[1]}.${ip[0]}"

		# if we don't know it, add it
		if [ -z "${ADNS_REMAINING[$i]}" ]
			then
			echo >&2 " >  IP         ${i}"
			ADNS_REMAINING[$i]="${#DNSBL[@]}"
			ADNS_COUNT[$i]=0
			ADNS_SCORE[$i]=0
			ADNS_LISTS[$i]=""
			[ ${DEBUG} -eq 1 ] && echo "FIRST ${i} (${ADNS_REMAINING[$i]})"
		fi

		# decrement it my one
		ADNS_REMAINING[$i]=$[ADNS_REMAINING[$i] - 1]
		[ ${DEBUG} -eq 1 ] && echo "MINUS ${i} (${ADNS_REMAINING[$i]})"

		# handle the response
		case "${status}" in
			ok)	# positive response, parse it
				local h= a= inet= reply=
				while [ ${n} -gt 0 ]
				do
					read h a inet reply
					[ ! "${h}" = "${host}" ] && echo "ERROR: ${h} <> ${host}"

					match "${reply}" "${ip[@]}"
					n=$[n - 1]
				done
				;;

			permfail)
				;;

			default)
				echo >&2 "ERROR: Unknown response ${status}"
				;;
		esac

		# if it is done, remove it
		if [ ${ADNS_REMAINING[$i]} -eq 0 ]
			then
			blacklist "${ADNS_COUNT[$i]}" "${i}" "${ADNS_SCORE[$i]}" "${ADNS_LISTS[$i]}" && ADNS_BLACKLISTED=$[ADNS_BLACKLISTED + 1]
			ADNS_COMPLETED=$[ADNS_COMPLETED + 1]

			unset ADNS_REMAINING[$i]
			unset ADNS_COUNT[$i]
			unset ADNS_SCORE[$i]
			unset ADNS_LISTS[$i]

			[ ${DEBUG} -eq 1 ] && echo "DONE ${i}"
			#[ ${DEBUG} -eq 1 ] && declare -p ADNS_REMAINING ADNS_SCORE ADNS_COUNT ADNS_LISTS
		fi

		if [ "${#ADNS_REMAINING[@]}" -ge ${THROTTLE_THRESHOLD} ]
			then
			if [ ! -f "${THROTTLE_LOCK_FILE}" ]
				then
				touch "${THROTTLE_LOCK_FILE}"
				[ ${DEBUG} -eq 1 ] && echo >&2 " >>> THROTHLING: there are ${#ADNS_REMAINING[@]} IPs in queue..."
			fi
			throttle="THROTTLING"

		elif [ -f "${THROTTLE_LOCK_FILE}" ]
			then
			[ ${DEBUG} -eq 1 ] && echo >&2 " >>> THROTLING: resuming operations...."
			rm "${THROTTLE_LOCK_FILE}"
			throttle="waiting"

		else
			throttle="waiting"

		fi

		if [ ${RUNNING_ON_TERMINAL} -eq 1 ]
			then
			if [ ${ADNS_COMPLETED} -gt 0 ]
				then
				spinner "${#ADNS_REMAINING[@]}, checked ${ADNS_COMPLETED}, blacklisted ${ADNS_BLACKLISTED} ($[ADNS_BLACKLISTED * 100 / ADNS_COMPLETED] pcent) ${throttle}..."
			else
				spinner "${#ADNS_REMAINING[@]} waiting..."
			fi
		fi
	done
}


# -----------------------------------------------------------------------------
# the console spinner

PROGRAM_SPINNER_SPACES='                                                                                                '
PROGRAM_SPINNER_BACKSPACES='\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b'
PROGRAM_SPINNER_LAST=0
PROGRAM_SPINNER='|/-\'
PROGRAM_SPINNER_RUNNING=0
PROGRAM_SPINNER_PREFIX="Queue"
spinner()
{
	local t="${PROGRAM_SPINNER_PREFIX} ${1}"
	printf >&2 "${PROGRAM_SPINNER_BACKSPACES:0:$PROGRAM_SPINNER_LAST}"
	PROGRAM_SPINNER_LAST=$(( (${#t} + 5) * 2 ))
	local temp=${PROGRAM_SPINNER#?}
	printf >&2 "[${t} %c] " "${PROGRAM_SPINNER}"
	PROGRAM_SPINNER=$temp${PROGRAM_SPINNER%"$temp"}
	PROGRAM_SPINNER_RUNNING=1
}

spinner_end() {
	local last=$((PROGRAM_SPINNER_LAST / 2))
	printf >&2 "${PROGRAM_SPINNER_BACKSPACES:0:$PROGRAM_SPINNER_LAST}"
	printf >&2 "${PROGRAM_SPINNER_SPACES:0:$last}"
	printf >&2 "${PROGRAM_SPINNER_BACKSPACES:0:$PROGRAM_SPINNER_LAST}"
	PROGRAM_SPINNER_RUNNING=0
	PROGRAM_SPINNER_LAST=0
}

# -----------------------------------------------------------------------------
# the main loop

# A pipeline:
# 1. tail the log
# 2. grep the lines we are interested
# 3. replace the lines with: SRC_IP DST_IP
# 4. generate hostnames for each IP
# 5. let adnshost do the lookups
# 6. parse the adnshost responses and take action

echo >&2 "Using ulogd iptables log: ${IPTABLES_LOG}"
echo >&2 "Searching for: ${ULOG_MATCH}"

echo >&2
echo >&2 "Please wait some time... pipes are filling up... (this is not a joke)"

tail -s 0.2 -F "${IPTABLES_LOG}" |\
	grep --line-buffered -E "^.*${ULOG_MATCH}.* SRC=[0-9.]+ DST=[0-9.]+ .*$" |\
	sed --unbuffered "s/^.* SRC=\([0-9\.]\+\) DST=\([0-9\.]\+\) .*$/\1 \2/g" |\
	generate_hostnames_from_src_dst |\
	adnshost --asynch --fmt-asynch --no-env --pipe |\
	parse_adns_asynch

exit 0
