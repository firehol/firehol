#!/bin/sh
#
# Startup script to implement /etc/firehol/firehol.conf pre-defined rules.
#
# chkconfig: 2345 99 92
#
# description: creates stateful iptables packet filtering firewalls.
#
# by Costa Tsaousis <costa@tsaousis.gr>
#
# config: /etc/firehol/firehol.conf
#
# $Id: firehol.sh,v 1.133 2003/06/18 21:44:52 ktsaou Exp $
#
FIREHOL_FILE="${0}"

PATH="${PATH}:/bin:/usr/bin:/sbin:/usr/sbin"

# External commands FireHOL will need.
# If one of those is not found, FireHOL will refuse to run.

which_cmd() {
	unalias $1 >/dev/null 2>&1
	local cmd=`which $1 | head -1`
	if [ $? -gt 0 -o ! -x "${cmd}" ]
	then
		echo "ERROR: Command '$1' not found in system path."
		exit 1
	fi
	
	echo "${cmd}"
}

CAT_CMD=`which_cmd cat`
CUT_CMD=`which_cmd cut`
CHOWN_CMD=`which_cmd chown`
CHMOD_CMD=`which_cmd chmod`
DATE_CMD=`which_cmd date`
EGREP_CMD=`which_cmd egrep`
GAWK_CMD=`which_cmd gawk`
GREP_CMD=`which_cmd grep`
HOSTNAME_CMD=`which_cmd hostname`
IP_CMD=`which_cmd ip`
IPTABLES_CMD=`which_cmd iptables`
IPTABLES_SAVE_CMD=`which_cmd iptables-save`
LESS_CMD=`which_cmd less`
LSMOD_CMD=`which_cmd lsmod`
MKDIR_CMD=`which_cmd mkdir`
MV_CMD=`which_cmd mv`
MODPROBE_CMD=`which_cmd modprobe`
NETSTAT_CMD=`which_cmd netstat`
RENICE_CMD=`which_cmd renice`
RM_CMD=`which_cmd rm`
SED_CMD=`which_cmd sed`
SORT_CMD=`which_cmd sort`
SYSCTL_CMD=`which_cmd sysctl`
TOUCH_CMD=`which_cmd touch`
TR_CMD=`which_cmd tr`
UNAME_CMD=`which_cmd uname`
UNIQ_CMD=`which_cmd uniq`


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# GLOBAL DEFAULTS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

# IANA Reserved IPv4 address space
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# Optimized (CIDR) by Marc 'HE' Brockschmidt <marc@marcbrockschmidt.de>
RESERVED_IPS="0.0.0.0/7 2.0.0.0/8 5.0.0.0/8 7.0.0.0/8 23.0.0.0/8 27.0.0.0/8 31.0.0.0/8 36.0.0.0/8 37.0.0.0/8 39.0.0.0/8 41.0.0.0/8 42.0.0.0/8 58.0.0.0/8 59.0.0.0/8 70.0.0.0/7 72.0.0.0/5 83.0.0.0/8 84.0.0.0/6 88.0.0.0/5 96.0.0.0/3 173.0.0.0/8 174.0.0.0/7 176.0.0.0/5 184.0.0.0/6 189.0.0.0/8 190.0.0.0/8 197.0.0.0/8 223.0.0.0/8 240.0.0.0/4"

# Private IPv4 address space
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# Revised by me according to RFC 3330. Explanation:
# 10.0.0.0/8       => RFC 1918: IANA Private Use
# 169.254.0.0/16   => Link Local
# 192.0.2.0/24     => Test Net
# 192.88.99.0/24   => RFC 3068: 6to4 anycast & RFC 2544: Benchmarking addresses
# 192.168.0.0/16   => RFC 1918: Private use
PRIVATE_IPS="10.0.0.0/8 169.254.0.0/16 172.16.0.0/12 169.254.0.0/16 192.88.99.0/24 192.168.0.0/16"

# The multicast address space
MULTICAST_IPS="224.0.0.0/8"

# A shortcut to have all the Internet unroutable addresses in one
# variable
UNROUTABLE_IPS="${RESERVED_IPS} ${PRIVATE_IPS}"

# ----------------------------------------------------------------------

# The default policy for the interface commands of the firewall.
# This can be controlled on a per interface basis using the
# policy interface subscommand. 
DEFAULT_INTERFACE_POLICY="DROP"

# Which is the filter table chains policy during firewall activation?
FIREHOL_INPUT_ACTIVATION_POLICY="ACCEPT"
FIREHOL_OUTPUT_ACTIVATION_POLICY="ACCEPT"
FIREHOL_FORWARD_ACTIVATION_POLICY="ACCEPT"

# What to do with unmatched packets?
# To change these, simply define them the configuration file.
UNMATCHED_INPUT_POLICY="DROP"
UNMATCHED_OUTPUT_POLICY="DROP"
UNMATCHED_ROUTER_POLICY="DROP"

# Options for iptables LOG action.
# These options will be added to all LOG actions FireHOL will generate.
# To change them, type such a line in the configuration file.
# FIREHOL_LOG_OPTIONS="--log-tcp-sequence --log-tcp-options --log-ip-options"
FIREHOL_LOG_OPTIONS=""
FIREHOL_LOG_LEVEL="warning"
FIREHOL_LOG_FREQUENCY="1/second"
FIREHOL_LOG_BURST="5"

# The client ports to be used for "default" client ports when the
# client specified is a foreign host.
# We give all ports above 1000 because a few systems (like Solaris)
# use this range.
# Note that FireHOL will ask the kernel for default client ports of
# the local host. This only applies to client ports of remote hosts.
DEFAULT_CLIENT_PORTS="1000:65535"

# Get the default client ports from the kernel configuration.
# This is formed to a range of ports to be used for all "default"
# client ports when the client specified is the localhost.
LOCAL_CLIENT_PORTS_LOW=`${SYSCTL_CMD} net.ipv4.ip_local_port_range | ${CUT_CMD} -d '=' -f 2 | ${CUT_CMD} -f 1`
LOCAL_CLIENT_PORTS_HIGH=`${SYSCTL_CMD} net.ipv4.ip_local_port_range | ${CUT_CMD} -d '=' -f 2 | ${CUT_CMD} -f 2`
LOCAL_CLIENT_PORTS="${LOCAL_CLIENT_PORTS_LOW}:${LOCAL_CLIENT_PORTS_HIGH}"


# ----------------------------------------------------------------------
# Temporary directories and files

# These files will be created and deleted during our run.
FIREHOL_DIR="/tmp/firehol-tmp-$$"
FIREHOL_CHAINS_DIR="${FIREHOL_DIR}/chains"
FIREHOL_OUTPUT="${FIREHOL_DIR}/firehol-out.sh"
FIREHOL_SAVED="${FIREHOL_DIR}/firehol-save.sh"
FIREHOL_TMP="${FIREHOL_DIR}/firehol-tmp.sh"

# Where /etc/init.d/iptables expects its configuration?
# Leave it empty for automatic detection
FIREHOL_AUTOSAVE=


# ----------------------------------------------------------------------
# This is our version number. It is increased when the configuration
# file commands and arguments change their meaning and usage, so that
# the user will have to review it more precisely.
FIREHOL_VERSION=5


# ----------------------------------------------------------------------
# The initial line number of the configuration file.
FIREHOL_LINEID="INIT"

# Variable kernel module requirements.
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# Note that each of the complex services
# may add to this variable the kernel modules it requires.
# See rules_ftp() bellow for an example.
FIREHOL_KERNEL_MODULES=""
#
# In the configuration file you can write:
#
#                     require_kernel_module <module_name>
# 
# to have FireHOL require a specific module for the configurarion.

# Set this to 1 in the configuration file to have FireHOL complex
# services' rules load NAT kernel modules too.
FIREHOL_NAT=0

# Set this to 1 in the configuration file if routing should be enabled
# in the kernel.
FIREHOL_ROUTING=0

# Services may add themeselves to this variable so that the service "all" will
# also call them.
# By default it is empty - only rules programmers should change this.
ALL_SHOULD_ALSO_RUN=


# ------------------------------------------------------------------------------
# Command Line Arguments Defaults

# The default configuration file
# It can be changed on the command line
FIREHOL_CONFIG="/etc/firehol/firehol.conf"

if [ ! -d /etc/firehol -a -f /etc/firehol.conf ]
then
	mkdir /etc/firehol
	${CHOWN_CMD} root:root /etc/firehol
	${CHMOD_CMD} 700 /etc/firehol
	${MV_CMD} /etc/firehol.conf "${FIREHOL_CONFIG}"
	
	echo >&2
	echo >&2 "NOTICE: Your config file /etc/firehol.conf has been moved to ${FIREHOL_CONFIG}"
	sleep 5
fi

# If set to 1, we are just going to present the resulting firewall instead of
# installing it.
# It can be changed on the command line
FIREHOL_DEBUG=0

# If set to 1, the firewall will be saved for normal iptables processing.
# It can be changed on the command line
FIREHOL_SAVE=0

# If set to 1, the firewall will be restored if you don't commit it.
# It can be changed on the command line
FIREHOL_TRY=1

# If set to 1, FireHOL enters interactive mode to answer questions.
# It can be changed on the command line
FIREHOL_EXPLAIN=0

# If set to 1, FireHOL enters a wizard mode to help the user build a firewall.
# It can be changed on the command line
FIREHOL_WIZARD=0

# If set to 0, FireHOL will not try to load the required kernel modules.
# It can be set in the configuration file.
FIREHOL_LOAD_KERNEL_MODULES=1


# ------------------------------------------------------------------------------
# Keep information about the current primary command
# Primary commands are: interface, router

work_counter=0
work_cmd=
work_realcmd=("(unset)")
work_name=
work_inface=
work_outface=
work_policy="${DEFAULT_INTERFACE_POLICY}"
work_error=0
work_function="Initializing"


# ------------------------------------------------------------------------------
# Keep status information

# 0 = no errors, 1 = there were errors in the script
work_final_status=0

# This variable is used for generating dynamic chains when needed for
# combined negative statements (AND) implied by the "not" parameter
# to many FireHOL directives.
# What FireHOL is doing to accomplish this, is to produce dynamically
# a linked list of iptables chains with just one condition each, making
# the packets to traverse from chain to chain when matched, to reach
# their final destination.
FIREHOL_DYNAMIC_CHAIN_COUNTER=1


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# SIMPLE SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for simple services.
# We define as "simple" the services that are implemented using a single socket,
# initiated by the client and used by the server.
#
# The following list is sorted by service name.

server_AH_ports="51/any"
client_AH_ports="any"

# Debian package proxy
server_aptproxy_ports="tcp/9999"
client_aptproxy_ports="default"

# APC UPS Server (these ports have to be accessible on all machines NOT
# directly connected to the UPS (e.g. the slaves)
server_apcupsd_ports="tcp/6544"
client_apcupsd_ports="default"

server_apcupsdnis_ports="tcp/3551"
client_apcupsdnis_ports="default"

server_cups_ports="tcp/ipp"
client_cups_ports="default"

server_cvspserver_ports="tcp/2401"
client_cvspserver_ports="default"

server_daytime_ports="tcp/daytime"
client_daytime_ports="default"

server_dcpp_ports="tcp/1412 udp/1412"
client_dcpp_ports="default"

server_dns_ports="udp/domain tcp/domain"
client_dns_ports="any"

server_dhcp_ports="udp/bootps"
client_dhcp_ports="bootpc"

# DHCP Relaying (server is the relay server which behaves like a client
# towards the real DHCP Server); I'm not sure about this one...
server_dhcprelay_ports="udp/bootps"
client_dhcprelay_ports="bootps"

server_ESP_ports="50/any"
client_ESP_ports="any"

server_echo_ports="tcp/echo"
client_echo_ports="default"

server_finger_ports="tcp/finger"
client_finger_ports="default"

server_GRE_ports="47/any"
client_GRE_ports="any"

# We assume heartbeat uses ports in the range 690 to 699
server_heartbeat_ports="udp/690:699"
client_heartbeat_ports="default"

server_http_ports="tcp/http"
client_http_ports="default"

server_https_ports="tcp/https"
client_https_ports="default"

server_ICMP_ports="icmp/any"
client_ICMP_ports="any"

server_icmp_ports="icmp/any"
client_icmp_ports="any"
# ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} icmp"

server_ident_ports="tcp/auth"
client_ident_ports="default"

server_imap_ports="tcp/imap"
client_imap_ports="default"

server_imaps_ports="tcp/imaps"
client_imaps_ports="default"

server_irc_ports="tcp/ircd"
client_irc_ports="default"
require_irc_modules="ip_conntrack_irc"
require_irc_nat_modules="ip_nat_irc"
ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} irc"

# for IPSec Key negotiation
server_isakmp_ports="udp/500"
client_isakmp_ports="500"

server_ldap_ports="tcp/ldap"
client_ldap_ports="default"

server_ldaps_ports="tcp/ldaps"
client_ldaps_ports="default"

server_lpd_ports="tcp/printer"
client_lpd_ports="default"

server_microsoft_ds_ports="tcp/microsoft-ds"
client_microsoft_ds_ports="default"

server_msn_ports="tcp/6891"
client_msn_ports="default"

server_mysql_ports="tcp/mysql"
client_mysql_ports="default"

server_netbios_ns_ports="udp/netbios-ns"
client_netbios_ns_ports="default netbios-ns"

server_netbios_dgm_ports="udp/netbios-dgm"
client_netbios_dgm_ports="default netbios-dgm"

server_netbios_ssn_ports="tcp/netbios-ssn"
client_netbios_ssn_ports="default"

server_nntp_ports="tcp/nntp"
client_nntp_ports="default"

server_ntp_ports="udp/ntp tcp/ntp"
client_ntp_ports="ntp default"

server_pop3_ports="tcp/pop3"
client_pop3_ports="default"

server_pop3s_ports="tcp/pop3s"
client_pop3s_ports="default"

# Portmap clients appear to use ports bellow 1024
server_portmap_ports="udp/sunrpc tcp/sunrpc"
client_portmap_ports="500:65535"

# Privacy Proxy
server_privoxy_ports="tcp/8118"
client_privoxy_ports="default"

server_radius_ports="udp/radius udp/radius-acct"
client_radius_ports="default"

server_radiusold_ports="udp/1645 udp/1646"
client_radiusold_ports="default"

server_rndc_ports="tcp/rndc"
client_rndc_ports="default"

server_rsync_ports="tcp/rsync udp/rsync"
client_rsync_ports="default"

server_socks_ports="tcp/socks udp/socks"
client_socks_ports="default"

server_squid_ports="tcp/3128"
client_squid_ports="default"

server_smtp_ports="tcp/smtp"
client_smtp_ports="default"

server_smtps_ports="tcp/smtps"
client_smtps_ports="default"

server_snmp_ports="udp/snmp"
client_snmp_ports="default"

server_snmptrap_ports="udp/snmptrap"
client_snmptrap_ports="any"

server_ssh_ports="tcp/ssh"
client_ssh_ports="default"

# SMTP over SSL/TLS submission
server_submission_ports="tcp/587"
client_submission_ports="default"

# Sun RCP is an alias for service portmap
server_sunrpc_ports="${server_portmap_ports}"
client_sunrpc_ports="${client_portmap_ports}"

server_swat_ports="tcp/swat"
client_swat_ports="default"

server_syslog_ports="udp/syslog"
client_syslog_ports="syslog default"

server_telnet_ports="tcp/telnet"
client_telnet_ports="default"

# TFTP is more complicated than this.
# TFTP communicates through high ports. The problem is that there is
# no relevant iptables module in most distributions.
#server_tftp_ports="udp/tftp"
#client_tftp_ports="default"

server_uucp_ports="tcp/uucp"
client_uucp_ports="default"

server_vmware_ports="tcp/902"
client_vmware_ports="default"

server_vmwareauth_ports="tcp/903"
client_vmwareauth_ports="default"

server_vmwareweb_ports="tcp/8222"
client_vmwareweb_ports="default"

server_vnc_ports="tcp/5900:5903"
client_vnc_ports="default"

server_webcache_ports="tcp/webcache"
client_webcache_ports="default"


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# COMPLEX SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for complex services.
# We define as "complex" the services that are implemented using multiple sockets.

# Each function bellow is organized in three parts:
# 1) A Header, common to each and every function
# 2) The rules required for the INPUT of the server
# 3) The rules required for the OUTPUT of the server
#
# The Header part, together with the "reverse" keyword can reverse the rules so
# that if we are implementing a client the INPUT will become OUTPUT and vice versa.
#
# In most the cases the input and output rules are the same with the following
# differences:
#
# a) The output rules begin with the "reverse" keyword, which reverses:
#    inface/outface, src/dst, sport/dport
# b) The output rules use ${out}_${mychain} instead of ${in}_${mychain}
# c) The state rules match the client operation, not the server.


# --- EMULE --------------------------------------------------------------------

rules_emule() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow incomming to server tcp/4662
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp" sport any dport 4662 state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport any dport 4662 state ESTABLISHED || return 1
	
	# allow outgoing to server tcp/4662
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp" dport any sport 4662 state NEW,ESTABLISHED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp" dport any sport 4662 state ESTABLISHED || return 1
	
	# allow incomming to server udp/4672
	rule ${in} action "$@" chain "${in}_${mychain}" proto "udp" sport any dport 4672 state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "udp" sport any dport 4672 state ESTABLISHED || return 1
	
	# allow outgoing to server udp/4672
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "udp" dport any sport 4672 state NEW,ESTABLISHED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto "udp" dport any sport 4672 state ESTABLISHED || return 1
	
	# allow incomming to server tcp/4661
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp" sport any dport 4661 state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport any dport 4661 state ESTABLISHED || return 1
	
	# allow incomming to server udp/4665
	rule ${in} action "$@" chain "${in}_${mychain}" proto "udp" sport any dport 4665 state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "udp" sport any dport 4665 state ESTABLISHED || return 1
	
	return 0
}

# --- SAMBA --------------------------------------------------------------------

rules_samba() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule ${in} action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state NEW,ESTABLISHED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state NEW,ESTABLISHED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state ESTABLISHED || return 1
	
	return 0
}


# --- PPTP --------------------------------------------------------------------

rules_pptp() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state NEW,ESTABLISHED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto "47" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "47" state ESTABLISHED|| return 1
	
	return 0
}


# --- NFS ----------------------------------------------------------------------

rules_nfs() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# This command requires in the client or route subcommands,
	# the first argument after the policy/action is a dst.
	
	local action="${1}"; shift
	local servers="localhost"
	
	if [ "${type}" = "client" -o ! "${work_cmd}" = "interface" ]
	then
		case "${1}" in
			dst|DST|destination|DESTINATION)
				shift
				local servers="${1}"
				shift
				;;
				
			*)
				error "Please re-phrase to: ${type} nfs ${action} dst <NFS_SERVER> [other rules]"
				return 1
				;;
		esac
	fi
	
	local x=
	for x in ${servers}
	do
		local tmp="${FIREHOL_DIR}/firehol.rpcinfo.$$"
		
		set_work_function "Getting RPC information from server '${x}'"
		
		rpcinfo -p ${x} >"${tmp}"
		if [ $? -gt 0 -o ! -s "${tmp}" ]
		then
			error "Cannot get rpcinfo from host '${x}' (using the previous firewall rules)"
			${RM_CMD} -f "${tmp}"
			return 1
		fi
		
		local server_mountd_ports="`${CAT_CMD} "${tmp}" | ${GREP_CMD} " mountd$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | ${SORT_CMD} | ${UNIQ_CMD}`"
		local server_nfsd_ports="`${CAT_CMD} "${tmp}" | ${GREP_CMD} " nfs$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | ${SORT_CMD} | ${UNIQ_CMD}`"
		
		test -z "${server_mountd_ports}" && error "Cannot find mountd ports for nfs server '${x}'" && return 1
		test -z "${server_nfsd_ports}"   && error "Cannot find nfsd ports for nfs server '${x}'" && return 1
		
		local dst=
		if [ ! "${x}" = "localhost" ]
		then
			dst="dst ${x}"
		fi
		
		set_work_function "Processing mountd rules for server '${x}'"
		rules_custom "${mychain}" "${type}" nfs-mountd "${server_mountd_ports}" "500:65535" "${action}" $dst "$@"
		
		set_work_function "Processing nfsd rules for server '${x}'"
		rules_custom "${mychain}" "${type}" nfs-nfsd   "${server_nfsd_ports}"   "500:65535" "${action}" $dst "$@"
		
		${RM_CMD} -f "${tmp}"
		
		echo >&2 ""
		echo >&2 "WARNING:"
		echo >&2 "This firewall must be restarted if NFS server ${x} is restarted!"
		echo >&2 ""
	done
	
	return 0
}


# --- AMANDA -------------------------------------------------------------------
FIREHOL_AMANDA_PORTS="850:859"

rules_amanda() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	set_work_function "*** AMANDA: See http://amanda.sourceforge.net/fom-serve/cache/139.html"
	
	
	set_work_function "Setting up rules for initial amanda server-to-client connection"
	
	rule ${out} action "$@" chain "${out}_${mychain}" proto "udp" dport 10080 state NEW,ESTABLISHED || return 1
	rule ${in} reverse action "$@" chain "${in}_${mychain}" proto "udp" dport 10080 state ESTABLISHED || return 1
	
	
	set_work_function "Setting up rules for amanda data exchange client-to-server"
	
	rule ${in} action "$@" chain "${in}_${mychain}" proto "tcp udp" dport "${FIREHOL_AMANDA_PORTS}" state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "tcp udp" dport "${FIREHOL_AMANDA_PORTS}" state ESTABLISHED || return 1
	
	return 0
}

# --- FTP ----------------------------------------------------------------------

ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} ftp"

rules_ftp() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# For an explanation of how FTP connections work, see
	# http://slacksite.com/other/ftp.html
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming, and established outgoing
	# accept port ftp new connections
	rule ${in} action "$@" chain "${in}_${mychain}" proto tcp sport "${client_ports}" dport ftp state NEW,ESTABLISHED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto tcp sport "${client_ports}" dport ftp state ESTABLISHED || return 1
	
	# Active FTP
	# send port ftp-data related connections
	
	set_work_function "Setting up rules for Active FTP ${type}"
	
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto tcp sport "${client_ports}" dport ftp-data state ESTABLISHED,RELATED || return 1
	rule ${in} action "$@" chain "${in}_${mychain}" proto tcp sport "${client_ports}" dport ftp-data state ESTABLISHED || return 1
	
	# ----------------------------------------------------------------------
	
	# A hack for Passive FTP only
	local s_client_ports="${DEFAULT_CLIENT_PORTS}"
	local c_client_ports="${DEFAULT_CLIENT_PORTS}"
	
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		c_client_ports="${LOCAL_CLIENT_PORTS}"
	elif [ "${type}" = "server" -a "${work_cmd}" = "interface" ]
	then
		s_client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# Passive FTP
	# accept high-ports related connections
	set_work_function "Setting up rules for Passive FTP ${type}"
	
	rule ${in} action "$@" chain "${in}_${mychain}" proto tcp sport "${c_client_ports}" dport "${s_client_ports}" state ESTABLISHED,RELATED || return 1
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto tcp sport "${c_client_ports}" dport "${s_client_ports}" state ESTABLISHED || return 1
	
	require_kernel_module ip_conntrack_ftp
	test ${FIREHOL_NAT} -eq 1 && require_kernel_module ip_nat_ftp
	
	return 0
}


# --- PING ---------------------------------------------------------------------

rules_ping() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow incoming new and established PING packets
	rule ${in} action "$@" chain "${in}_${mychain}" proto icmp custom "--icmp-type echo-request" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule ${out} reverse action "$@" chain "${out}_${mychain}" proto icmp custom "--icmp-type echo-reply" state ESTABLISHED || return 1
	
	return 0
}


# --- ALL ----------------------------------------------------------------------

rules_all() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule ${in} action "$@" chain "${in}_${mychain}" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule ${out} reverse action "$@" chain "${out}_${mychain}" state ESTABLISHED || return 1
	
	local ser=
	for ser in ${ALL_SHOULD_ALSO_RUN}
	do
		"${type}" ${ser} "$@" || return 1
	done
	
	return 0
}


# --- ANY ----------------------------------------------------------------------

rules_any() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	local name="${1}"; shift # a special case: service any gets a name
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule ${in} action "$@" chain "${in}_${mychain}" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule ${out} reverse action "$@" chain "${out}_${mychain}" state ESTABLISHED || return 1
	
	return 0
}


# --- MULTICAST ----------------------------------------------------------------

rules_multicast() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# match multicast packets in both directions
	rule ${out} action "$@" chain "${out}_${mychain}" dst "224.0.0.0/8" proto 2 || return 1
	rule ${in} reverse action "$@" chain "${in}_${mychain}" src "224.0.0.0/8" proto 2 || return 1
	
	return 0
}


# --- CUSTOM -------------------------------------------------------------------

rules_custom() {
	local mychain="${1}"; shift
	local type="${1}"; shift
	
	local server="${1}"; shift
	local my_server_ports="${1}"; shift
	local my_client_ports="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" -a "${work_cmd}" = "interface" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	local sp=
	for sp in ${my_server_ports}
	do
		local proto=
		local sport=
		
		IFS="/" read proto sport <<EOF
$sp
EOF
		
		local cp=
		for cp in ${my_client_ports}
		do
			local cport=
			case ${cp} in
				default)
					cport="${client_ports}"
					;;
					
				*)	cport="${cp}"
					;;
			esac
			
			# allow new and established incoming packets
			rule ${in} action "$@" chain "${in}_${mychain}" proto "${proto}" sport "${cport}" dport "${sport}" state NEW,ESTABLISHED || return 1
			
			# allow outgoing established packets
			rule ${out} reverse action "$@" chain "${out}_${mychain}" proto "${proto}" sport "${cport}" dport "${sport}" state ESTABLISHED || return 1
		done
	done
	
	return 0
}


# ------------------------------------------------------------------------------

# The caller may need just our services definitions
if [ "$1" = "gimme-the-services-defs" ]
then
	return 0
	exit 1
fi


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# HELPER FUNCTIONS BELLOW THIS POINT
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

masquerade() {
	work_realcmd=(${FUNCNAME} "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	local f="${work_outface}"
	test "${1}" = "reverse" && f="${work_inface}" && shift
	
	test -z "${f}" && local f="${1}" && shift
	
	test -z "${f}" && error "masquerade requires an interface set or as argument" && return 1
	
	set_work_function "Initializing masquerade on interface '${f}'"
	
	rule noowner table nat chain POSTROUTING "$@" inface any outface "${f}" action MASQUERADE || return 1
	
	FIREHOL_NAT=1
	FIREHOL_ROUTING=1
	
	return 0
}

# helper transparent_squid <squid_port> <squid_user>
transparent_squid_count=0
transparent_squid() {
	work_realcmd=($FUNCNAME "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	require_work clear || ( error "$FUNCNAME cannot be used in '${work_cmd}'. Put it before any '${work_cmd}' definition."; return 1 )
	
	local redirect="${1}"; shift
	local user="${1}"; shift
	
	test -z "${redirect}" && error "Squid port number is empty" && return 1
	
	transparent_squid_count=$[transparent_squid_count + 1]
	
	set_work_function "Setting up rules for catching routed web traffic"
	
	create_chain nat "in_trsquid.${transparent_squid_count}" PREROUTING noowner "$@" outface any proto tcp sport "${DEFAULT_CLIENT_PORTS}" dport http || return 1
	rule table nat chain "in_trsquid.${transparent_squid_count}" proto tcp dport http action REDIRECT to-port ${redirect} || return 1
	
	if [ ! -z "${user}" ]
	then
		set_work_function "Setting up rules for catching outgoing web traffic"
		create_chain nat "out_trsquid.${transparent_squid_count}" OUTPUT "$@" uid not "${user}" nosoftwarnings inface any outface any src any proto tcp sport "${LOCAL_CLIENT_PORTS}" dport http || return 1
		
		# do not cache traffic for localhost web servers
		rule table nat chain "out_trsquid.${transparent_squid_count}" dst "127.0.0.1" action RETURN || return 1
		
		rule table nat chain "out_trsquid.${transparent_squid_count}" proto tcp dport http action REDIRECT to-port ${redirect} || return 1
	fi
	
	FIREHOL_NAT=1
	FIREHOL_ROUTING=1
	
	return 0
}

nat_count=0
nat() {
	work_realcmd=($FUNCNAME "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	require_work clear || ( error "$FUNCNAME cannot be used in '${work_cmd}'. Put it before any '${work_cmd}' definition."; return 1 )
	
	local type="${1}"; shift
	local to="${1}";   shift
	
	nat_count=$[nat_count + 1]
	
	set_work_function "Setting up rules for NAT"
	
	case ${type} in
		to-source)
			create_chain nat "nat.${nat_count}" POSTROUTING nolog "$@" inface any || return 1
			local action=snat
			;;
		
		to-destination)
			create_chain nat "nat.${nat_count}" PREROUTING noowner nolog "$@" outface any || return 1
			local action=dnat
			;;
			
		redirect-to)
			create_chain nat "nat.${nat_count}" PREROUTING noowner nolog "$@" outface any || return 1
			local action=redirect
			;;
			
		*)
			error "$FUNCNAME requires a type (i.e. to-source, to-destination, redirect-to, etc) as its first argument. '${type}' is not understood."
			return 1
			;;
	esac
	
	# we now need to keep the protocol
	rule table nat chain "nat.${nat_count}" noowner "$@" action "${action}" to "${to}" nosoftwarnings src any dst any inface any outface any sport any dport any || return 1
	
	FIREHOL_NAT=1
	FIREHOL_ROUTING=1
	
	return 0
}

snat() {
	work_realcmd=($FUNCNAME "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	local to="${1}"; shift
	test "${to}" = "to" && local to="${1}" && shift
	
	nat "to-source" "${to}" "$@"
}

dnat() {
	work_realcmd=($FUNCNAME "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	local to="${1}"; shift
	test "${to}" = "to" && local to="${1}" && shift
	
	nat "to-destination" "${to}" "$@"
}

redirect() {
	work_realcmd=($FUNCNAME "$@")
	
	set_work_function -ne "Initializing $FUNCNAME"
	
	local to="${1}"; shift
	test "${to}" = "to" -o "${to}" = "to-port" && local to="${1}" && shift
	
	nat "redirect-to" "${to}" "$@"
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# INTERNAL FUNCTIONS BELLOW THIS POINT - Primary commands
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Check the version required by the configuration file
# WHY:
# We have to make sure the configuration file has been written for this version
# of FireHOL. Note that the version command does not actually check the version
# of firehol.sh. It checks only its release number (R5 currently).

version() {
        work_realcmd=(${FUNCNAME} "$@")
	
	if [ ${1} -gt ${FIREHOL_VERSION} ]
	then
		error "Wrong version. FireHOL is v${FIREHOL_VERSION}, your script requires v${1}."
	fi
}


# ------------------------------------------------------------------------------
# PRIMARY COMMAND: interface
# Setup rules specific to an interface (physical or logical)

interface() {
        work_realcmd=(${FUNCNAME} "$@")
	
	# --- close any open command ---
	
	close_cmd || return 1
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	set_work_function -ne "Initializing $FUNCNAME"
	
	
	# --- get paramaters and validate them ---
	
	# Get the interface
	local inface="${1}"; shift
	test -z "${inface}" && error "real interface is not set" && return 1
	
	# Get the name for this interface
	local name="${1}"; shift
	test -z "${name}" && error "$FUNCNAME name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	work_realcmd=("(unset)")
	
	set_work_function -ne "Initializing $FUNCNAME '${work_name}'"
	
	create_chain filter "in_${work_name}" INPUT in set_work_inface "$@" inface "${inface}" outface any || return 1
	create_chain filter "out_${work_name}" OUTPUT out set_work_outface reverse "$@" inface "${inface}" outface any || return 1
	
	return 0
}


router() {
        work_realcmd=(${FUNCNAME} "$@")
	
	# --- close any open command ---
	
	close_cmd || return 1
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	set_work_function -ne "Initializing $FUNCNAME"
	
	
	# --- get paramaters and validate them ---
	
	# Get the name for this router
	local name="${1}"; shift
	test -z "${name}" && error "$FUNCNAME name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	work_realcmd=("(unset)")
	
	set_work_function -ne "Initializing $FUNCNAME '${work_name}'"
	
	create_chain filter "in_${work_name}" FORWARD in set_work_inface set_work_outface "$@" || return 1
	create_chain filter "out_${work_name}" FORWARD out reverse "$@" || return 1
	
	FIREHOL_ROUTING=1
	
	return 0
}

postprocess() {
	local check="error"
	test "A${1}" = "A-ne"   && shift && local check="none"
	test "A${1}" = "A-warn" && shift && local check="warn"
	
	local tmp=
	test ! ${FIREHOL_DEBUG} -eq 1 && local tmp=" >${FIREHOL_OUTPUT}.log 2>&1"
	
	printf "%q " "$@" >>${FIREHOL_OUTPUT}
	test ${FIREHOL_EXPLAIN} -eq 0 && echo " $tmp # L:${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
	
	if [ ${FIREHOL_EXPLAIN} -eq 1 ]
	then
		${CAT_CMD} ${FIREHOL_OUTPUT}
		echo
		${RM_CMD} -f ${FIREHOL_OUTPUT}
	fi
	
	test ${FIREHOL_DEBUG}   -eq 1 && local check="none"
	test ${FIREHOL_EXPLAIN} -eq 1 && local check="none"
	
	if [ ! ${check} = "none" ]
	then
		printf "r=\$?; test \${r} -gt 0 && runtime_error ${check} \${r} ${FIREHOL_LINEID} " >>${FIREHOL_OUTPUT}
		printf "%q " "$@" >>${FIREHOL_OUTPUT}
		printf "\n" >>${FIREHOL_OUTPUT}
	fi
	
	return 0
}

iptables() {
	postprocess "${IPTABLES_CMD}" "$@"
	
	return 0
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# INTERNAL FUNCTIONS BELLOW THIS POINT - Sub-commands
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Change the policy of an interface
# WHY:
# Not all interfaces have the same policy. The admin must have control over it.
# Here we just set what the admin wants. At the interface finalization we
# produce the iptables rules.

policy() {
        work_realcmd=(${FUNCNAME} "$@")
	
	require_work set interface || return 1
	
	set_work_function "Setting interface '${work_inface}' (${work_name}) policy to ${1}"
	work_policy="$*"
	
	return 0
}

server() {
	work_realcmd=(${FUNCNAME} "$@")
	
	require_work set any || return 1
	smart_function server "$@"
	return $?
}

client() {
        work_realcmd=(${FUNCNAME} "$@")
	
	require_work set any || return 1
	smart_function client "$@"
	return $?
}

route() {
        work_realcmd=(${FUNCNAME} "$@")
	
	require_work set router || return 1
	smart_function server "$@"
	return $?
}


# --- protection ---------------------------------------------------------------

protection() {
        work_realcmd=(${FUNCNAME} "$@")
	
	require_work set any || return 1
	
	local in="in"
	local prface="${work_inface}"
	
	local pre="pr"
	unset reverse
	if [ "${1}" = "reverse" ]
	then
		local reverse="reverse"	# needed to recursion
		local pre="prr"		# in case a router has protections
					# both ways, the second needs to
					# have different chain names
					
		local in="out"		# reverse the interface
		
		prface="${work_outface}"
		shift
	fi
	
	local type="${1}"
	local rate="${2}"
	local burst="${3}"
	
	test -z "${rate}"  && rate="100/s"
	test -z "${burst}" && burst="50"
	
	set_work_function -ne "Generating protections on '${prface}' for ${work_cmd} '${work_name}'"
	
	local x=
	for x in ${type}
	do
		case "${x}" in
			none|NONE)
				return 0
				;;
			
			strong|STRONG|full|FULL|all|ALL)
				protection ${reverse} "fragments new-tcp-w/o-syn icmp-floods syn-floods malformed-xmas malformed-null malformed-bad" "${rate}" "${burst}"
				return $?
				;;
				
			fragments|FRAGMENTS)
				local mychain="${pre}_${work_name}_fragments"
				create_chain filter "${mychain}" "${in}_${work_name}" in custom "-f"				|| return 1
				
				set_work_function "Generating rules to be protected from packet fragments on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" loglimit "PACKET FRAGMENTS" action drop 				|| return 1
				;;
				
			new-tcp-w/o-syn|NEW-TCP-W/O-SYN)
				local mychain="${pre}_${work_name}_nosyn"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto tcp state NEW custom "! --syn"	|| return 1
				
				set_work_function "Generating rules to be protected from new TCP connections without the SYN flag set on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" loglimit "NEW TCP w/o SYN" action drop				|| return 1
				;;
				
			icmp-floods|ICMP-FLOODS)
				local mychain="${pre}_${work_name}_icmpflood"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto icmp custom "--icmp-type echo-request"	|| return 1
				
				set_work_function "Generating rules to be protected from ICMP floods on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" limit "${rate}" "${burst}" action return				|| return 1
				rule in chain "${mychain}" loglimit "ICMP FLOOD" action drop					|| return 1
				;;
				
			syn-floods|SYN-FLOODS)
				local mychain="${pre}_${work_name}_synflood"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto tcp custom "--syn"		|| return 1
				
				set_work_function "Generating rules to be protected from TCP SYN floods on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" limit "${rate}" "${burst}" action return				|| return 1
				rule in chain "${mychain}" loglimit "SYN FLOOD" action drop					|| return 1
				;;
				
			malformed-xmas|MALFORMED-XMAS)
				local mychain="${pre}_${work_name}_malxmas"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto tcp custom "--tcp-flags ALL ALL"	|| return 1
				
				set_work_function "Generating rules to be protected from packets with all TCP flags set on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" loglimit "MALFORMED XMAS" action drop				|| return 1
				;;
				
			malformed-null|MALFORMED-NULL)
				local mychain="${pre}_${work_name}_malnull"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto tcp custom "--tcp-flags ALL NONE" || return 1
				
				set_work_function "Generating rules to be protected from packets with all TCP flags unset on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${mychain}" loglimit "MALFORMED NULL" action drop				|| return 1
				;;
				
			malformed-bad|MALFORMED-BAD)
				local mychain="${pre}_${work_name}_malbad"
				create_chain filter "${mychain}" "${in}_${work_name}" in proto tcp custom "--tcp-flags SYN,FIN SYN,FIN"			|| return 1
				
				set_work_function "Generating rules to be protected from packets with illegal TCP flags on '${prface}' for ${work_cmd} '${work_name}'"
				
				rule in chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags SYN,RST SYN,RST"			|| return 1
				rule in chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags ALL     SYN,RST,ACK,FIN,URG"	|| return 1
				rule in chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags ALL     FIN,URG,PSH"		|| return 1
				
				rule in chain "${mychain}" loglimit "MALFORMED BAD" action drop								|| return 1
				;;
				
			*)
				error "Protection '${x}' does not exists."
				return 1
				;;
		esac
	done
	
	return 0
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# INTERNAL FUNCTIONS BELLOW THIS POINT - FireHOL internals
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


set_work_function() {
	local show_explain=1
	test "$1" = "-ne" && shift && local show_explain=0
	
	work_function="$*"
	
	test ${FIREHOL_EXPLAIN} -eq 1 -a ${show_explain} -eq 1 && printf "\n# %s\n" "$*"
}


# ------------------------------------------------------------------------------
# Manage kernel modules
# WHY:
# We need to load a set of kernel modules during postprocessing, and after the
# new firewall has been activated. Here we just keep a list of the required
# kernel modules.

check_kernel_module() {
	local mod="${1}"
	
	case ${mod} in
		ip_tables)
			test -f /proc/net/ip_tables_name && return 0
			return 1
			;;
		
		ip_conntrack)
			test -f /proc/net/ip_conntrack && return 0
			return 1
			;;
	esac
	
	return 1
}

load_kernel_module() {
	local mod="${1}"
	
	if [ ! ${FIREHOL_LOAD_KERNEL_MODULES} -eq 0 ]
	then
		check_kernel_module ${mod}
		if [ $? -gt 0 ]
		then
			${MODPROBE_CMD} ${mod} >${FIREHOL_OUTPUT}.log 2>&1
			local r=$?
			test ! ${r} -eq 0 && runtime_error warn ${r} ${FIREHOL_LINEID} ${MODPROBE_CMD} ${mod}
		fi
	fi
	return 0
}

require_kernel_module() {
	local new="${1}"
	
	local m=
	for m in ${FIREHOL_KERNEL_MODULES}
	do
		test "${m}" = "${new}" && return 0
	done
	
	FIREHOL_KERNEL_MODULES="${FIREHOL_KERNEL_MODULES} ${new}"
	
	return 0
}


# ------------------------------------------------------------------------------
# Make sure we automatically cleanup when we exit.
# WHY:
# Even a CTRL-C will call this and we will not leave temp files.
# Also, if a configuration file breaks, we will detect this too.

firehol_exit() {
	
	if [ -f "${FIREHOL_SAVED}" ]
	then
		echo
		echo -n $"FireHOL: Restoring old firewall:"
		iptables-restore <"${FIREHOL_SAVED}"
		if [ $? -eq 0 ]
		then
			success $"FireHOL: Restoring old firewall:"
		else
			failure $"FireHOL: Restoring old firewall:"
		fi
		echo
	fi
	
	test -d "${FIREHOL_DIR}" && ${RM_CMD} -rf "${FIREHOL_DIR}"
	return 0
}

# Run our exit even if we don't call exit.
trap firehol_exit EXIT

test -d "${FIREHOL_DIR}" && ${RM_CMD} -rf "${FIREHOL_DIR}"
${MKDIR_CMD} -p "${FIREHOL_DIR}"
test $? -gt 0 && exit 1

${MKDIR_CMD} -p "${FIREHOL_CHAINS_DIR}"
test $? -gt 0 && exit 1


# ------------------------------------------------------------------------------
# Check the status of the current primary command.
# WHY:
# Some sanity check for the order of commands in the configuration file.
# Each function has a "require_work type command" in order to check that it is
# placed in a valid point. This means that if you place a "route" command in an
# interface section (and many other compinations) it will fail.

require_work() {
	local type="${1}"
	local cmd="${2}"
	
	case "${type}" in
		clear)
			test ! -z "${work_cmd}" && error "Previous work was not applied." && return 1
			;;
		
		set)
			test -z "${work_cmd}" && error "The command used requires that a primary command is set." && return 1
			test ! "${work_cmd}" = "${cmd}" -a ! "${cmd}" = "any"  && error "Primary command is '${work_cmd}' but '${cmd}' is required." && return 1
			;;
			
		*)
			error "Unknown work status '${type}'."
			return 1
			;;
	esac
	
	return 0
}


# ------------------------------------------------------------------------------
# Finalizes the rules of the last primary command.
# WHY:
# At the end of an interface or router we need to add some code to apply its
# policy, accept all related packets, etc.
# Finalization occures automatically when a new primary command is executed and
# when the configuration file finishes.

close_cmd() {
	set_work_function -ne "Closing last open primary command (${work_cmd}/${work_name})"
	
	case "${work_cmd}" in
		interface)
			close_interface || return 1
			;;
		
		router)
			close_router || return 1
			;;
		
		'')
			;;
		
		*)
			error "Unknown work '${work_cmd}'."
			return 1
			;;
	esac
	
	# Reset the current status variables to empty/default
	work_counter=0
	work_cmd=
	work_realcmd=("(unset)")
	work_name=
	work_inface=
	work_outface=
	work_policy="${DEFAULT_INTERFACE_POLICY}"
	
	return 0
}

# ------------------------------------------------------------------------------
# close_interface
# WHY:
# Finalizes the rules for the last interface().

close_interface() {
	require_work set interface || return 1
	
	set_work_function "Finilizing interface '${work_name}'"
	
	case "${work_policy}" in
		return|RETURN)
			return 0
			;;
			
		accept|ACCEPT)
			;;
		
		*)
			local -a inlog=(loglimit "'IN-${work_name}'")
			local -a outlog=(loglimit "'OUT-${work_name}'")
			;;
	esac
	
	# Accept all related traffic to the established connections
	rule chain "in_${work_name}" state RELATED action ACCEPT || return 1
	rule chain "out_${work_name}" state RELATED action ACCEPT || return 1
	
	rule chain "in_${work_name}" "${inlog[@]}" action ${work_policy} || return 1
	rule reverse chain "out_${work_name}" "${outlog[@]}" action ${work_policy} || return 1
	
	return 0
}


# ------------------------------------------------------------------------------
# close_router
# WHY:
# Finalizes the rules for the last router().

close_router() {	
	require_work set router || return 1
	
	set_work_function "Finilizing router '${work_name}'"
	
	# Accept all related traffic to the established connections
	rule chain "in_${work_name}" state RELATED action ACCEPT || return 1
	rule chain "out_${work_name}" state RELATED action ACCEPT || return 1
	
	return 0
}


# ------------------------------------------------------------------------------
# close_master
# WHY:
# Finalizes the rules for the whole firewall.
# It assummes there is not primary command open.

close_master() {
	set_work_function "Finilizing firewall policies"
	
	# Accept all related traffic to the established connections
	rule chain INPUT state RELATED action ACCEPT || return 1
	rule chain OUTPUT state RELATED action ACCEPT || return 1
	rule chain FORWARD state RELATED action ACCEPT || return 1
	
	rule chain INPUT loglimit "IN-unknown" action ${UNMATCHED_INPUT_POLICY} || return 1
	rule chain OUTPUT loglimit "OUT-unknown" action ${UNMATCHED_OUTPUT_POLICY} || return 1
	rule chain FORWARD loglimit "PASS-unknown" action ${UNMATCHED_ROUTER_POLICY} || return 1
	return 0
}


# ------------------------------------------------------------------------------
# rule - the heart of FireHOL - iptables commands generation
# WHY:
# This is the function that gives all the magic to FireHOL. Actually it is a
# wrapper for iptables, producing multiple iptables commands based on its
# arguments. The rest of FireHOL is simply a "driver" for this function.


# rule_action_param() is a function - part of rule() - to create the final iptables cmd
# taking into account the "action_param" parameter of the action.

# rule_action_param() should only be used within rule() - no other place

rule_action_param() {
	local action="${1}"; shift
	local protocol="${1}"; shift
	local -a action_param=()
	
	local count=0
	while [ ! -z "${1}" -a ! "A${1}" = "A--" ]
	do
		action_param[$count]="${1}"
		shift
		
		count=$[count + 1]
	done
	
	local sep="${1}"; shift
	if [ ! "A${sep}" = "A--" ]
	then
		error "Internal Error, in parsing action_param parameters ($FUNCNAME '${action}' '${protocol}' '${action_param[@]}' ${sep} $@)."
		return 1
	fi
	
	# Do the rule
	case "${action}" in
		NONE)
			return 0
			;;
			
		REJECT)
			if [ "${action_param[1]}" = "auto" ]
			then
				if [ "${protocol}" = "tcp" -o "${protocol}" = "TCP" ]
				then
					action_param=("--reject-with" "tcp-reset")
				else
					action_param=()
				fi
			fi
			;;
	esac
	
	iptables "$@" -j "${action}" "${action_param[@]}"
	local ret=$?
	
	test $ret -gt 0 && failed=$[failed + 1]
	
	return $ret
}

rule() {
	local table=
	local chain=
	
	local inface=any
	local infacenot=
	
	local outface=any
	local outfacenot=
	
	local src=any
	local srcnot=
	
	local dst=any
	local dstnot=
	
	local sport=any
	local sportnot=
	
	local dport=any
	local dportnot=
	
	local proto=any
	local protonot=
	
	local uid=any
	local uidnot=
	
	local gid=any
	local gidnot=
	
	local pid=any
	local pidnot=
	
	local sid=any
	local sidnot=
	
	local log=
	local logtxt=
	local loglevel=
	
	local limit=
	local burst=
	
	local iplimit=
	local iplimit_mask=
	
	local action=
	
	local state=
	local statenot=
	
	local failed=0
	local reverse=0
	
	local swi=0
	local swo=0
	
	local custom=
	
	# if set to 1, all owner module options will be ignored
	local noowner=0
	
	# if set to 1, MIRROR will be converted to REJECT
	local nomirror=0
	
	# if set to 1, log and loglimit are ignored.
	local nolog=0
	
	# if set to 1, detection algorithm about overwritting optional rule
	# parameters will take place.
	local softwarnings=1
	
	# set it, in order to be local
	local -a action_param=()
	
	while [ ! -z "${1}" ]
	do
		case "${1}" in
			reverse|REVERSE)
				reverse=1
				shift
				;;
				
			table|TABLE)
				test ${softwarnings} -eq 1 -a ! -z "${table}" && softwarning "Overwritting param: ${1} '${chain}' becomes '${2}'"
				table="-t ${2}"
				shift 2
				;;
				
			chain|CHAIN)
				test ${softwarnings} -eq 1 -a ! -z "${chain}" && softwarning "Overwritting param: ${1} '${chain}' becomes '${2}'"
				chain="${2}"
				shift 2
				;;
				
			inface|INFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					infacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						infacenot="!"
					else
						if [ $swi -eq 1 ]
						then
							work_inface="${1}"
						fi
					fi
					test ${softwarnings} -eq 1 -a ! "${inface}" = "any" && softwarning "Overwritting param: inface '${inface}' becomes '${1}'"
					inface="${1}"
				else
					outfacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						outfacenot="!"
					else
						if [ ${swo} -eq 1 ]
						then
							work_outface="$1"
						fi
					fi
					test ${softwarnings} -eq 1 -a ! "${outface}" = "any" && softwarning "Overwritting param: outface '${outface}' becomes '${1}'"
					outface="${1}"
				fi
				shift
				;;
				
			outface|OUTFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					outfacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						outfacenot="!"
					else
						if [ ${swo} -eq 1 ]
						then
							work_outface="${1}"
						fi
					fi
					test ${softwarnings} -eq 1 -a ! "${outface}" = "any" && softwarning "Overwritting param: outface '${outface}' becomes '${1}'"
					outface="${1}"
				else
					infacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						infacenot="!"
					else
						if [ ${swi} -eq 1 ]
						then
							work_inface="${1}"
						fi
					fi
					test ${softwarnings} -eq 1 -a ! "${inface}" = "any" && softwarning "Overwritting param: inface '${inface}' becomes '${1}'"
					inface="${1}"
				fi
				shift
				;;
				
			src|SRC|source|SOURCE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					srcnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${src}" = "any" && softwarning "Overwritting param: src '${src}' becomes '${1}'"
					src="${1}"
				else
					dstnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${dst}" = "any" && softwarning "Overwritting param: dst '${dst}' becomes '${1}'"
					dst="${1}"
				fi
				shift
				;;
				
			dst|DST|destination|DESTINATION)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dstnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${dst}" = "any" && softwarning "Overwritting param: dst '${dst}' becomes '${1}'"
					dst="${1}"
				else
					srcnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${src}" = "any" && softwarning "Overwritting param: src '${src}' becomes '${1}'"
					src="${1}"
				fi
				shift
				;;
				
			sport|SPORT|sourceport|SOURCEPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					sportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${sport}" = "any" && softwarning "Overwritting param: sport '${sport}' becomes '${1}'"
					sport="${1}"
				else
					dportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${dport}" = "any" && softwarning "Overwritting param: dport '${dport}' becomes '${1}'"
					dport="${1}"
				fi
				shift
				;;
				
			dport|DPORT|destinationport|DESTINATIONPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${dport}" = "any" && softwarning "Overwritting param: dport '${dport}' becomes '${1}'"
					dport="${1}"
				else
					sportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					test ${softwarnings} -eq 1 -a ! "${sport}" = "any" && softwarning "Overwritting param: sport '${sport}' becomes '${1}'"
					sport="${1}"
				fi
				shift
				;;
				
			proto|PROTO|protocol|PROTOCOL)
				shift
				protonot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					protonot="!"
				fi
				test ${softwarnings} -eq 1 -a ! "${proto}" = "any" && softwarning "Overwritting param: proto '${proto}' becomes '${1}'"
				proto="${1}"
				shift
				;;
				
			action|ACTION)
				test ${softwarnings} -eq 1 -a ! -z "${action}" && softwarning "Overwritting param: action '${action}' becomes '${2}'"
				action="${2}"
				shift 2
				
				unset action_param
				local action_is_chain=0
				case "${action}" in
					accept|ACCEPT)
						action="ACCEPT"
						;;
						
					deny|DENY|drop|DROP)
						action="DROP"
						;;
						
					reject|REJECT)
						action="REJECT"
						if [ "${1}" = "with" ]
						then
							local -a action_param=("--reject-with" "${2}")
							shift 2
						else
							local -a action_param=("--reject-with" "auto")
						fi
						;;
						
					return|RETURN)
						action="RETURN"
						;;
						
					mirror|MIRROR)
						action="MIRROR"
						test $nomirror -eq 1 && action="REJECT"
						;;
						
					none|NONE)
						action="NONE"
						;;
						
					snat|SNAT)
						action="SNAT"
						if [ "${1}" = "to" ]
						then
							local -a action_param=()
							local x=
							for x in ${2}
							do
								action_param=(${action_param[@]} "--to-source" "${x}")
							done
							shift 2
						else
							error "${action} requires a 'to' argument."
							return 1
						fi
						if [ ! "A${table}" = "A-t nat" ]
						then
							error "${action} must on a the 'nat' table."
							return 1
						fi
						;;
						
					dnat|DNAT)
						action="DNAT"
						if [ "${1}" = "to" ]
						then
							local -a action_param=()
							local x=
							for x in ${2}
							do
								action_param=(${action_param[@]} "--to-destination" "${x}")
							done
							shift 2
						else
							error "${action} requires a 'to' argument"
							return 1
						fi
						if [ ! "A${table}" = "A-t nat" ]
						then
							error "${action} must on a the 'nat' table."
							return 1
						fi
						;;
						
					redirect|REDIRECT)
						action="REDIRECT"
						if [ "${1}" = "to-port" -o "${1}" = "to" ]
						then
							local -a action_param=("--to-ports" "${2}")
							shift 2
						else
							error "${action} requires a 'to-port' or 'to' argument."
							return 1
						fi
						if [ ! "A${table}" = "A-t nat" ]
						then
							error "${action} must on a the 'nat' table."
							return 1
						fi
						;;
						
					tos|TOS)
						action="TOS"
						if [ "${1}" = "to" ]
						then
							local -a action_param=("--set-tos" "${2}")
							shift 2
						else
							error "${action} requires a 'to' argument"
							return 1
						fi
						if [ ! "A${table}" = "A-t mangle" ]
						then
							error "${action} must on a the 'mangle' table."
							return 1
						fi
						;;
						
					mark|MARK)
						action="MARK"
						if [ "${1}" = "to" ]
						then
							local -a action_param=("--set-mark" "${2}")
							shift 2
						else
							error "${action} requires a 'to' argument"
							return 1
						fi
						if [ ! "A${table}" = "A-t mangle" ]
						then
							error "${action} must on a the 'mangle' table."
							return 1
						fi
						;;
						
					*)
						chain_exists "${action}"
						local action_is_chain=$?
						;;
				esac
				;;
			
			state|STATE)
				shift
				statenot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					statenot="!"
				fi
				test ${softwarnings} -eq 1 -a ! -z "${state}" && softwarning "Overwritting param: state '${state}' becomes '${1}'"
				state="${1}"
				shift
				;;
				
			user|USER|uid|UID)
				shift
				uidnot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					test ${noowner} -eq 0 && uidnot="!"
				fi
				test ${softwarnings} -eq 1 -a ! "${uid}" = "any" && softwarning "Overwritting param: uid '${uid}' becomes '${1}'"
				test ${noowner} -eq 0 && uid="${1}"
				shift
				;;
				
			group|GROUP|gid|GID)
				shift
				gidnot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					test ${noowner} -eq 0 && gidnot="!"
				fi
				test ${softwarnings} -eq 1 -a ! "${gid}" = "any" && softwarning "Overwritting param: gid '${gid}' becomes '${1}'"
				test ${noowner} -eq 0 && gid="${1}"
				shift
				;;
				
			process|PROCESS|pid|PID)
				shift
				pidnot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					test ${noowner} -eq 0 && pidnot="!"
				fi
				test ${softwarnings} -eq 1 -a ! "${pid}" = "any" && softwarning "Overwritting param: pid '${pid}' becomes '${1}'"
				test ${noowner} -eq 0 && pid="${1}"
				shift
				;;
				
			session|SESSION|sid|SID)
				shift
				sidnot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					test ${noowner} -eq 0 && sidnot="!"
				fi
				test ${softwarnings} -eq 1 -a ! "${sid}" = "any" && softwarning "Overwritting param: sid '${sid}' becomes '${1}'"
				test ${noowner} -eq 0 && sid="${1}"
				shift
				;;
				
			custom|CUSTOM)
				test ${softwarnings} -eq 1 -a ! -z "${custom}" && softwarning "Overwritting param: custom '${custom}' becomes '${2}'"
				custom="${2}"
				shift 2
				;;
				
			log|LOG)
				if [ ${nolog} -eq 0 ]
				then
					test ${softwarnings} -eq 1 -a ! -z "${log}" && softwarning "Overwritting param: log '${log}/${logtxt}' becomes 'normal/${2}'"
					log=normal
					logtxt="${2}"
				fi
				shift 2
				if [ "${1}" = "level" ]
				then
					loglevel="${2}"
					shift 2
				else
					loglevel="${FIREHOL_LOG_LEVEL}"
				fi
				;;
				
			loglimit|LOGLIMIT)
				if [ ${nolog} -eq 0 ]
				then
					test ${softwarnings} -eq 1 -a ! -z "${log}" && softwarning "Overwritting param: log '${log}/${logtxt}' becomes 'limit/${2}'"
					log=limit
					logtxt="${2}"
				fi
				shift 2
				if [ "${1}" = "level" ]
				then
					loglevel="${2}"
					shift 2
				else
					loglevel="${FIREHOL_LOG_LEVEL}"
				fi
				;;
				
			limit|LIMIT)
				test ${softwarnings} -eq 1 -a ! -z "${limit}" && softwarning "Overwritting param: limit '${limit}' becomes '${2}'"
				limit="${2}"
				burst="${3}"
				shift 3
				;;
				
			iplimit|IPLIMIT)
				test ${softwarnings} -eq 1 -a ! -z "${iplimit}" && softwarning "Overwritting param: iplimit '${iplimit}' becomes '${2}'"
				iplimit="${2}"
				iplimit_mask="${3}"
				shift 3
				;;
				
			in)	# this is incoming traffic - ignore packet ownership
				local noowner=1
				local nomirror=0
				shift
				;;
				
			out)	# this is outgoing traffic - ignore packet ownership if not in an interface
				if [ ! "${work_cmd}" = "interface" ]
				then
					local noowner=1
				else
					local nomirror=1
				fi
				shift
				;;
				
			nolog)
				local nolog=1
				shift
				;;
				
			noowner)
				local noowner=1
				shift
				;;
				
			softwarnings)
				local softwarnings=1
				shift
				;;
				
			nosoftwarnings)
				local softwarnings=0
				shift
				;;
				
			set_work_inface|SET_WORK_INFACE)
				swi=1
				shift
				;;
				
			set_work_outface|SET_WORK_OUTFACE)
				swo=1
				shift
				;;
				
			*)
				error "Cannot understand directive '${1}'."
				return 1
				;;
		esac
	done
	
	test -z "${table}" && table="-t filter"
	
	# If the user did not specified a rejection message,
	# we have to be smart and produce a tcp-reset if the protocol
	# is TCP and an ICMP port unreachable in all other cases.
	# The special case here is the protocol "any".
	# To accomplish the differentiation based on protocol we have
	# to change the protocol "any" to "tcp any"
	
	test "${action}" = "REJECT" -a "${action_param[1]}" = "auto" -a "${proto}" = "any" && proto="tcp any"
	
	
	# we cannot accept empty strings to a few parameters, since this
	# will prevent us from generating a rule (due to nested BASH loops).
	test -z "${inface}"	&& error "Cannot accept an empty 'inface'."	&& return 1
	test -z "${outface}"	&& error "Cannot accept an empty 'outface'."	&& return 1
	test -z "${src}"	&& error "Cannot accept an empty 'src'."	&& return 1
	test -z "${dst}"	&& error "Cannot accept an empty 'dst'."	&& return 1
	test -z "${sport}"	&& error "Cannot accept an empty 'sport'."	&& return 1
	test -z "${dport}"	&& error "Cannot accept an empty 'dport'."	&& return 1
	test -z "${proto}"	&& error "Cannot accept an empty 'proto'."	&& return 1
	test -z "${uid}"	&& error "Cannot accept an empty 'uid'."	&& return 1
	test -z "${gid}"	&& error "Cannot accept an empty 'gid'."	&& return 1
	test -z "${pid}"	&& error "Cannot accept an empty 'pid'."	&& return 1
	test -z "${sid}"	&& error "Cannot accept an empty 'sid'."	&& return 1
	
	
	# ----------------------------------------------------------------------------------
	# Do we have negative contitions?
	# If yes, we have to:
	#
	# case 1: If the action is a chain.
	#         Add to this chain positive RETURN statements matching all the negatives.
	#         The positive rules will be added bellow to the same chain and will be
	#         matched only if all RETURNs have not been matched.
	#
	# case 2: If the action is not a chain.
	#         Create a temporary chain, then add to this chain positive RETURN rules
	#         matching the negatives, and append at its end the final action (which is
	#         not a chain), then change the action of the positive rules to jump to
	#         this temporary chain.
	
	
	# ignore 'statenot' since it is negated in the positive rules
	if [ ! -z "${infacenot}${outfacenot}${srcnot}${dstnot}${sportnot}${dportnot}${protonot}${uidnot}${gidnot}${pidnot}${sidnot}" ]
	then
		if [ ${action_is_chain} -eq 1 ]
		then
			# if the action is a chain name, then just add the negative
			# expressions to this chain. Nothing more.
			
			local negative_chain="${action}"
			local negative_action=
		else
			# if the action is a native iptables action, then create
			# an intermidiate chain to store the negative expression,
			# and change the action of the rule to point to this action.
			
			# In this case, bellow we add after all negatives, the original
			# action of the rule.
			
			local negative_chain="${chain}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${negative_chain}"
			local negative_action="${action}"
			local action="${negative_chain}"
		fi
		
		
		if [ ! -z "${infacenot}" ]
		then
			local inf=
			for inf in ${inface}
			do
				iptables ${table} -A "${negative_chain}" -i "${inf}" -j RETURN
			done
			infacenot=
			inface=any
		fi
	
		if [ ! -z "${outfacenot}" ]
		then
			local outf=
			for outf in ${outface}
			do
				iptables ${table} -A "${negative_chain}" -o "${outf}" -j RETURN
			done
			outfacenot=
			outface=any
		fi
		
		if [ ! -z "${srcnot}" ]
		then
			local s=
			for s in ${src}
			do
				iptables ${table} -A "${negative_chain}" -s "${s}" -j RETURN
			done
			srcnot=
			src=any
		fi
		
		if [ ! -z "${dstnot}" ]
		then
			local d=
			for d in ${dst}
			do
				iptables ${table} -A "${negative_chain}" -d "${d}" -j RETURN
			done
			dstnot=
			dst=any
		fi
		
		if [ ! -z "${protonot}" ]
		then
			if [ ! -z "${sportnot}" -o ! -z "${dportnot}" ]
			then
				error "Cannot have negative protocol(s) and source/destination port(s)."
				return 1
			fi
			
			local pr=
			for pr in ${proto}
			do
				iptables ${table} -A "${negative_chain}" --p "${pr}" -j RETURN
			done
			protonot=
			proto=any
		fi
		
		if [ ! -z "${sportnot}" ]
		then
			if [ "${proto}" = "any" ]
			then
				error "Cannot have negative source port specification without protocol."
				return 1
			fi
			
			local sp=
			for sp in ${sport}
			do
				local pr=
				for pr in ${proto}
				do
					iptables ${table} -A "${negative_chain}" -p "${pr}" --sport "${sp}" -j RETURN
				done
			done
			sportnot=
			sport=any
		fi
		
		if [ ! -z "${dportnot}" ]
		then
			if [ "${proto}" = "any" ]
			then
				error "Cannot have negative destination port specification without protocol."
				return 1
			fi
			
			local dp=
			for dp in ${dport}
			do
				local pr=
				for pr in ${proto}
				do
					iptables ${table} -A "${negative_chain}" -p "${pr}" --dport "${dp}" -j RETURN
				done
			done
			dportnot=
			dport=any
		fi
		
		if [ ! -z "${uidnot}" ]
		then
			local tuid=
			for tuid in ${uid}
			do
				iptables ${table} -A "${negative_chain}" -m owner --uid-owner "${tuid}" -j RETURN
			done
			uidnot=
			uid=any
		fi
		
		if [ ! -z "${gidnot}" ]
		then
			local tgid=
			for tgid in ${gid}
			do
				iptables ${table} -A "${negative_chain}" -m owner --gid-owner "${tgid}" -j RETURN
			done
			gidnot=
			gid=any
		fi
		
		if [ ! -z "${pidnot}" ]
		then
			local tpid=
			for tpid in ${pid}
			do
				iptables ${table} -A "${negative_chain}" -m owner --pid-owner "${tpid}" -j RETURN
			done
			pidnot=
			pid=any
		fi
		
		if [ ! -z "${sidnot}" ]
		then
			local tsid=
			for tsid in ${sid}
			do
				iptables ${table} -A "${negative_chain}" -m owner --sid-owner "${tsid}" -j RETURN
			done
			sidnot=
			sid=any
		fi
		
		# in case this is temporary chain we created for the negative expression,
		# just make it have the final action of the rule.
		if [ ! -z "${negative_action}" ]
		then
			local pr=
			for pr in ${proto}
			do
				unset proto_arg
				
				case ${pr} in
					any|ANY)
						;;
					
					*)
						local -a proto_arg=("-p" "${pr}")
						;;
				esac
				
				rule_action_param "${negative_action}" "${pr}" "${action_param[@]}" -- ${table} -A "${negative_chain}" "${proto_arg[@]}"
				unset action_param
			done
		fi
	fi
	
	
	# ----------------------------------------------------------------------------------
	# Process the positive rules
	
	local tuid=
	for tuid in ${uid}
	do
		unset uid_arg
		unset owner_arg
		
		case ${tuid} in
			any|ANY)
				;;
			
			*)
				local -a owner_arg=("-m" "owner")
				local -a uid_arg=("--uid-owner" "${tuid}")
				;;
		esac
	
		local tgid=
		for tgid in ${gid}
		do
			unset gid_arg
			
			case ${tgid} in
				any|ANY)
					;;
				
				*)
					local -a owner_arg=("-m" "owner")
					local -a gid_arg=("--gid-owner" "${tgid}")
					;;
			esac
		
			local tpid=
			for tpid in ${pid}
			do
				unset pid_arg
				
				case ${tpid} in
					any|ANY)
						;;
					
					*)
						local -a owner_arg=("-m" "owner")
						local -a pid_arg=("--pid-owner" "${tpid}")
						;;
				esac
			
				local tsid=
				for tsid in ${sid}
				do
					unset sid_arg
					
					case ${tsid} in
						any|ANY)
							;;
						
						*)
							local -a owner_arg=("-m" "owner")
							local -a sid_arg=("--sid-owner" "${tsid}")
							;;
					esac
					
					local pr=
					for pr in ${proto}
					do
						unset proto_arg
						
						case ${pr} in
							any|ANY)
								;;
							
							*)
								local -a proto_arg=("-p" "${pr}")
								;;
						esac
							
						local inf=
						for inf in ${inface}
						do
							unset inf_arg
							case ${inf} in
								any|ANY)
									;;
								
								*)
									local -a inf_arg=("-i" "${inf}")
									;;
							esac
							
							local outf=
							for outf in ${outface}
							do
								unset outf_arg
								case ${outf} in
									any|ANY)
										;;
									
									*)
										local -a outf_arg=("-o" "${outf}")
										;;
								esac
								
								local sp=
								for sp in ${sport}
								do
									unset sp_arg
									case ${sp} in
										any|ANY)
											;;
										
										*)
											local -a sp_arg=("--sport" "${sp}")
											;;
									esac
									
									local dp=
									for dp in ${dport}
									do
										unset dp_arg
										case ${dp} in
											any|ANY)
												;;
											
											*)
												local -a dp_arg=("--dport" "${dp}")
												;;
										esac
										
										local s=
										for s in ${src}
										do
											unset s_arg
											case ${s} in
												any|ANY)
													;;
												
												*)
													local -a s_arg=("-s" "${s}")
													;;
											esac
											
											local d=
											for d in ${dst}
											do
												unset d_arg
												case ${d} in
													any|ANY)
														;;
													
													*)
														local -a d_arg=("-d" "${d}")
														;;
												esac
												
												unset state_arg
												if [ ! -z "${state}" ]
												then
													local -a state_arg=("-m" "state" "${statenot}" "--state" "${state}")
												fi
												
												unset limit_arg
												if [ ! -z "${limit}" ]
												then
													local -a limit_arg=("-m" "limit" "--limit" "${limit}" "--limit-burst" "${burst}")
												fi
												
												unset iplimit_arg
												if [ ! -z "${iplimit}" ]
												then
													local -a iplimit_arg=("-m" "iplimit" "--iplimit-above" "${iplimit}" "--iplimit-mask" "${iplimit_mask}")
												fi
												
												declare -a basecmd=("${inf_arg[@]}" "${outf_arg[@]}" "${limit_arg[@]}" "${iplimit_arg[@]}" "${proto_arg[@]}" "${s_arg[@]}" "${sp_arg[@]}" "${d_arg[@]}" "${dp_arg[@]}" "${owner_arg[@]}" "${uid_arg[@]}" "${gid_arg[@]}" "${pid_arg[@]}" "${sid_arg[@]}" "${state_arg[@]}")
												
												case "${log}" in
													'')
														;;
													
													limit)
														iptables ${table} -A "${chain}" "${basecmd[@]}" ${custom} -m limit --limit "${FIREHOL_LOG_FREQUENCY}" --limit-burst "${FIREHOL_LOG_BURST}" -j LOG ${FIREHOL_LOG_OPTIONS} --log-level "${loglevel}" --log-prefix="${logtxt}:"
														;;
														
													normal)
														iptables ${table} -A "${chain}" "${basecmd[@]}" ${custom} -j LOG ${FIREHOL_LOG_OPTIONS} --log-level "${loglevel}" --log-prefix="${logtxt}:"
														;;
														
													*)
														error "Unknown log value '${log}'."
														;;
												esac
												
												rule_action_param "${action}" "${pr}" "${action_param[@]}" -- ${table} -A "${chain}" "${basecmd[@]}" ${custom}
											done
										done
									done
								done
							done
						done
					done
				done
			done
		done
	done
	
	test ${failed} -gt 0 && error "There are ${failed} failed commands." && return 1
	return 0
}


softwarning() {
	echo >&2
	echo >&2 "--------------------------------------------------------------------------------"
	echo >&2 "WARNING"
	echo >&2 "WHAT   : ${work_function}"
	echo >&2 "WHY    :" "$@"
	printf >&2 "COMMAND: "; printf >&2 "%q " "${work_realcmd[@]}"; echo >&2
	echo >&2 "SOURCE : line ${FIREHOL_LINEID} of ${FIREHOL_CONFIG}"
	echo >&2
	
	return 0
}

# ------------------------------------------------------------------------------
# error - error reporting while still parsing the configuration file
# WHY:
# This is the error handler that presents to the user detected errors during
# processing FireHOL's configuration file.
# This command is directly called by other functions of FireHOL.

error() {
	work_error=$[work_error + 1]
	echo >&2
	echo >&2 "--------------------------------------------------------------------------------"
	echo >&2 "ERROR #: ${work_error}"
	echo >&2 "WHAT   : ${work_function}"
	echo >&2 "WHY    :" "$@"
	printf >&2 "COMMAND: "; printf >&2 "%q " "${work_realcmd[@]}"; echo >&2
	echo >&2 "SOURCE : line ${FIREHOL_LINEID} of ${FIREHOL_CONFIG}"
	echo >&2
	
	return 0
}


# ------------------------------------------------------------------------------
# runtime_error - postprocessing evaluation of commands run
# WHY:
# The generated iptables commands must be checked for errors in case they fail.
# This command is executed after every postprocessing command to find out
# if it has been successfull or failed.

runtime_error() {
	local type="ERROR"
	local id=
	
	case "${1}" in
		error)
			local type="ERROR  "
			work_final_status=$[work_final_status + 1]
			local id="# ${work_final_status}."
			;;
			
		warn)
			local type="WARNING"
			local id="This might or might not affect the operation of your firewall."
			;;
		
		*)
			work_final_status=$[work_final_status + 1]
			local id="# ${work_final_status}."
			
			echo >&2
			echo >&2
			echo >&2 "*** unsupported final status type '${1}'. Assuming it is 'ERROR'"
			echo >&2
			echo >&2
			;;
	esac
	shift
	
	local ret="${1}"; shift
	local line="${1}"; shift
	
	echo >&2
	echo >&2
	echo >&2 "--------------------------------------------------------------------------------"
	echo >&2 "${type} : ${id}"
	echo >&2 "WHAT    : A runtime command failed to execute (returned error ${ret})."
	echo >&2 "SOURCE  : line ${line} of ${FIREHOL_CONFIG}"
	printf >&2 "COMMAND : "
	printf >&2 "%q " "$@"
	printf >&2 "\n"
	echo >&2 "OUTPUT  : "
	echo >&2
	${CAT_CMD} ${FIREHOL_OUTPUT}.log
	echo >&2
	
	return 0
}


# ------------------------------------------------------------------------------
# chain_exists - find if chain name has already being specified
# WHY:
# We have to make sure each service gets its own chain.
# Although FireHOL chain naming makes chains with unique names, this is just
# an extra sanity check.

chain_exists() {
	local chain="${1}"
	
	test -f "${FIREHOL_CHAINS_DIR}/${chain}" && return 1
	return 0
}


# ------------------------------------------------------------------------------
# create_chain - create a chain and link it to the firewall
# WHY:
# When a chain is created it must somehow to be linked to the rest of the
# firewall apropriately. This function first creates the chain and then
# it links it to its final position within the generated firewall.

create_chain() {
	local table="${1}"
	local newchain="${2}"
	local oldchain="${3}"
	shift 3
	
	set_work_function "Creating chain '${newchain}' under '${oldchain}' in table '${table}'"
	
	chain_exists "${newchain}"
	test $? -eq 1 && error "Chain '${newchain}' already exists." && return 1
	
	iptables -t ${table} -N "${newchain}" || return 1
	${TOUCH_CMD} "${FIREHOL_CHAINS_DIR}/${newchain}"
	
	rule table ${table} chain "${oldchain}" action "${newchain}" "$@" || return 1
	
	return 0
}


# ------------------------------------------------------------------------------
# smart_function - find the valid service definition for a service
# WHY:
# FireHOL supports simple and complex services. This function first tries to
# detect if there are the proper variables set for a simple service, and if
# they do not exist, it then tries to find the complex function definition for
# the service.
#
# Additionally, it creates a chain for the subcommand.

smart_function() {
	local type="${1}"	# The current subcommand: server/client/route
	local services="${2}"	# The services to implement
	shift 2
	
	local service=
	for service in $services
	do
		local servname="${service}"
		test "${service}" = "custom" && local servname="${1}"
		
		set_work_function "Preparing for service '${service}' of type '${type}' under interface '${work_name}'"
		
		# Increase the command counter, to make all chains within a primary
		# command, unique.
		work_counter=$[work_counter + 1]
		
		local suffix="u${work_counter}"
		case "${type}" in
			client)
				suffix="c${work_counter}"
				;;
			
			server)
				suffix="s${work_counter}"
				;;
			
			route)
				suffix="r${work_counter}"
				;;
			
			*)	error "Cannot understand type '${type}'."
				return 1
				;;
		esac
		
		local mychain="${work_name}_${servname}_${suffix}"
		
		create_chain filter "in_${mychain}" "in_${work_name}" || return 1
		create_chain filter "out_${mychain}" "out_${work_name}" || return 1
		
		# Try the simple services first
		simple_service "${mychain}" "${type}" "${service}" "$@"
		local ret=$?
		
		# simple service completed succesfully.
		test $ret -eq 0 && continue
		
		# simple service exists but failed.
		if [ $ret -ne 127 ]
		then
			error "Simple service '${service}' returned an error ($ret)."
			return 1
		fi
		
		
		# Try the custom services
		local fn="rules_${service}"
		
		set_work_function "Running complex rules function ${fn}() for ${type} '${service}'"
		
		"${fn}" "${mychain}" "${type}" "$@"
		local ret=$?
		test $ret -eq 0 && continue
		
		if [ $ret -eq 127 ]
		then
			error "There is no service '${service}' defined."
		else
			error "Complex service '${service}' returned an error ($ret)."
		fi
		return 1
	done
	
	return 0
}

# ------------------------------------------------------------------------------
# simple_service - convert a service definition to an inline service definition
# WHY:
# When a simple service is detected, there must be someone to call
# rules_custom() with the appropriate service definition parameters.

simple_service() {
	local mychain="${1}"; shift
	local type="${1}"; shift
	local server="${1}"; shift
	
	local server_varname="server_${server}_ports"
	eval local server_ports="\$${server_varname}"
	
	local client_varname="client_${server}_ports"
	eval local client_ports="\$${client_varname}"
	
	test -z "${server_ports}" -o -z "${client_ports}" && return 127
	
	local x=
	local varname="require_${server}_modules"
	eval local value="\$${varname}"
	for x in ${value}
	do
		require_kernel_module $x || return 1
	done
	
	if [ ${FIREHOL_NAT} -eq 1 ]
	then
		local varname="require_${server}_nat_modules"
		eval local value="\$${varname}"
		for x in ${value}
		do
			require_kernel_module $x || return 1
		done
	fi
	
	set_work_function "Running simple rules for  ${type} '${service}'"
	
	rules_custom "${mychain}" "${type}" "${server}" "${server_ports}" "${client_ports}" "$@"
	return $?
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# START UP SCRIPT PROCESSING
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# On non RedHat machines we need success() and failure()
success() {
	echo " OK"
}
failure() {
	echo " FAILED"
}

# Be nice on production environments
${RENICE_CMD} 10 $$ >/dev/null 2>/dev/null

# ------------------------------------------------------------------------------
# A small part bellow is copied from /etc/init.d/iptables

# On RedHat systems this will define success() and failure()
test -f /etc/init.d/functions && . /etc/init.d/functions

if [ -z "${IPTABLES_CMD}" -o ! -x "${IPTABLES_CMD}" ]; then
	exit 0
fi

KERNELMAJ=`${UNAME_CMD} -r | ${SED_CMD}                   -e 's,\..*,,'`
KERNELMIN=`${UNAME_CMD} -r | ${SED_CMD} -e 's,[^\.]*\.,,' -e 's,\..*,,'`

if [ "$KERNELMAJ" -lt 2 ] ; then
	exit 0
fi
if [ "$KERNELMAJ" -eq 2 -a "$KERNELMIN" -lt 3 ] ; then
	exit 0
fi

if  ${LSMOD_CMD} 2>/dev/null | ${GREP_CMD} -q ipchains ; then
	# Don't do both
	exit 0
fi


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# COMMAND LINE ARGUMENTS PROCESSING
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

me="${0}"
arg="${1}"
shift

case "${arg}" in
	explain)
		FIREHOL_EXPLAIN=1
		;;
	
	helpme|wizard)
		FIREHOL_WIZARD=1
		;;
	
	try)
		FIREHOL_TRY=1
		;;
	
	start)
		FIREHOL_TRY=0
		;;
	
	stop)
		test -f /var/lock/subsys/firehol && ${RM_CMD} -f /var/lock/subsys/firehol
		test -f /var/lock/subsys/iptables && ${RM_CMD} -f /var/lock/subsys/iptables
		
		echo -n $"FireHOL: Clearing Firewall:"
		load_kernel_module ip_tables
		tables=`${CAT_CMD} /proc/net/ip_tables_names`
		for t in ${tables}
		do
			${IPTABLES_CMD} -t "${t}" -F
			${IPTABLES_CMD} -t "${t}" -X
			${IPTABLES_CMD} -t "${t}" -Z
			
			# Find all default chains in this table.
			chains=`${IPTABLES_CMD} -t "${t}" -nL | ${GREP_CMD} "^Chain " | ${CUT_CMD} -d ' ' -f 2`
			for c in ${chains}
			do
				${IPTABLES_CMD} -t "${t}" -P "${c}" ACCEPT
			done
		done
		success $"FireHOL: Clearing Firewall:"
		echo
		
		exit 0
		;;
	
	restart|force-reload)
		FIREHOL_TRY=0
		;;
	
	condrestart)
		FIREHOL_TRY=0
		if [ -f /var/lock/subsys/firehol ]
		then
			exit 0
		fi
		;;
	
	status)
		(
			echo 
			echo "--- MANGLE ---------------------------------------------------------------------"
			echo 
			${IPTABLES_CMD} -t mangle -nxvL
			
			echo 
			echo 
			echo "--- NAT ------------------------------------------------------------------------"
			echo 
			${IPTABLES_CMD} -t nat -nxvL
			
			echo 
			echo 
			echo "--- FILTER ---------------------------------------------------------------------"
			echo 
			${IPTABLES_CMD} -nxvL
		) | ${LESS_CMD}
		exit $?
		;;
	
	panic)
		ssh_src=
		ssh_sport="0:65535"
		ssh_dport="0:65535"
		if [ ! -z "${SSH_CLIENT}" ]
		then
			set -- ${SSH_CLIENT}
			ssh_src="${1}"
			ssh_sport="${2}"
			ssh_dport="${3}"
		elif [ ! -z "${1}" ]
		then
			ssh_src="${1}"
		fi
		
		echo -n $"FireHOL: Blocking all communications:"
		load_kernel_module ip_tables
		tables=`${CAT_CMD} /proc/net/ip_tables_names`
		for t in ${tables}
		do
			${IPTABLES_CMD} -t "${t}" -F
			${IPTABLES_CMD} -t "${t}" -X
			${IPTABLES_CMD} -t "${t}" -Z
			
			# Find all default chains in this table.
			chains=`${IPTABLES_CMD} -t "${t}" -nL | ${GREP_CMD} "^Chain " | ${CUT_CMD} -d ' ' -f 2`
			for c in ${chains}
			do
				${IPTABLES_CMD} -t "${t}" -P "${c}" ACCEPT
				
				if [ ! -z "${ssh_src}" ]
				then
					${IPTABLES_CMD} -t "${t}" -A "${c}" -p tcp -s "${ssh_src}" --sport "${ssh_sport}" --dport "${ssh_dport}" -m state --state ESTABLISHED -j ACCEPT
					${IPTABLES_CMD} -t "${t}" -A "${c}" -p tcp -d "${ssh_src}" --dport "${ssh_sport}" --sport "${ssh_dport}" -m state --state ESTABLISHED -j ACCEPT
				fi
				${IPTABLES_CMD} -t "${t}" -A "${c}" -j DROP
			done
		done
		success $"FireHOL: Blocking all communications:"
		echo
		
		exit 0
		;;
	
	save)
		FIREHOL_TRY=0
		FIREHOL_SAVE=1
		;;
		
	debug)
		FIREHOL_TRY=0
		FIREHOL_DEBUG=1
		;;
	
	*)	if [ ! -z "${arg}" -a -f "${arg}" ]
		then
			FIREHOL_CONFIG="${arg}"
			arg="${1}"
			test "${arg}" = "--" && arg="" && shift
			test -z "${arg}" && arg="try"
			
			case "${arg}" in
				start)
					FIREHOL_TRY=0
					FIREHOL_DEBUG=0
					;;
					
				try)
					FIREHOL_TRY=1
					FIREHOL_DEBUG=0
					;;
					
				debug)
					FIREHOL_TRY=0
					FIREHOL_DEBUG=1
					;;
				
				*)
					echo "Cannot accept command line argument '${arg}' here."
					exit 1
					;;
			esac
		else
		
		${CAT_CMD} <<"EOF"
$Id: firehol.sh,v 1.133 2003/06/18 21:44:52 ktsaou Exp $
(C) Copyright 2003, Costa Tsaousis <costa@tsaousis.gr>
FireHOL is distributed under GPL.

EOF

		${CAT_CMD} <<EOF
FireHOL supports the following command line arguments (only one of them):

	start		to activate the firewall configuration.
			The configuration is expected to be found in
			/etc/firehol/firehol.conf
			
	try		to activate the firewall, but wait until
			the user types the word "commit". If this word
			is not typed within 30 seconds, the previous
			firewall is restored.
			
	stop		to stop a running iptables firewall.
			This will allow all traffic to pass unchecked.
		
	restart		this is an alias for start and is given for
			compatibility with /etc/init.d/iptables.
			
	condrestart	will start the firewall only if it is not
			already active. It does not detect a modified
			configuration file.
	
	status		will show the running firewall, as in:
			${IPTABLES_CMD} -nxvL | ${LESS_CMD}
			
	panic		will block all IP communication.
	
	save		to start the firewall and then save it using
			${IPTABLES_SAVE_CMD} to /etc/sysconfig/iptables
			
			Note that not all firewalls will work if
			restored with:
			/etc/init.d/iptables start
			
	debug		to parse the configuration file but instead of
			activating it, to show the generated iptables
			statements.
	
	explain		to enter interactive mode and accept configuration
			directives. It also gives the iptables commands
			for each directive together with reasoning.
			
	helpme	or	to enter a wizard mode where FireHOL will try
	wizard		to figure out the configuration you need.
			You can redirect the standard output of FireHOL to
			a file to get the config to this file.
			
	<a filename>	a different configuration file.
			If not other argument is given, the configuration
			will be "tried" (default = try).
			Otherwise the argument next to the filename can
			be one of 'start', 'debug' and 'try'.


-------------------------------------------------------------------------

FireHOL supports the following services (sorted by name):
EOF


		(
			# The simple services
			${CAT_CMD} "${me}"				|\
				${GREP_CMD} -e "^server_.*_ports="	|\
				${CUT_CMD} -d '=' -f 1			|\
				${SED_CMD} "s/^server_//"		|\
				${SED_CMD} "s/_ports\$//"
			
			# The complex services
			${CAT_CMD} "${me}"				|\
				${GREP_CMD} -e "^rules_.*()"		|\
				${CUT_CMD} -d '(' -f 1			|\
				${SED_CMD} "s/^rules_/(*) /"
		) | ${SORT_CMD} | ${UNIQ_CMD} |\
		(
			x=0
			while read
			do
				x=$[x + 1]
				if [ $x -gt 4 ]
				then
					printf "\n"
					x=1
				fi
				printf "% 16s |" "$REPLY"
			done
			printf "\n\n"
		)
		
		${CAT_CMD} <<EOF

Services marked with (*) are "smart" or complex services.
All the others are simple single socket services.

Please note that the service:
	
	all	matches all packets, all protocols, all of everything,
		while ensuring that required kernel modules are loaded.
	
	any	allows the matching of packets with unusual rules, like
		only protocol but no ports. If service any is used
		without other parameters, it does what service all does
		but it does not handle kernel modules.
		For example, to match GRE traffic use:
		
		server any mygre accept proto 47
		
		Service any does not handle kernel modules.
		
	custom	allows the definition of a custom service.
		The template is:
		
		server custom name protocol/sport cport accept
		
		where name is just a name, protocol is the protocol the
		service uses (tcp, udp, etc), sport is server port,
		cport is the client port. For example, IMAP4 is:
		
		server custom imap tcp/143 default accept


For more information about FireHOL, please refer to:

		http://firehol.sourceforge.net

-------------------------------------------------------------------------
FireHOL controls your firewall. You should want to get updates quickly.
Subscribe (at the home page) to get notified of new releases.
-------------------------------------------------------------------------

YOU DO NOT KNOW WHAT TO DO? FireHOL can help you! Just run it with the
argument 'helpme' and it will generate its configuration file for this
machine. Your running firewall will not be altered or stopped, and no
systems settings will be modified. Just run:

${FIREHOL_FILE} helpme >/tmp/firehol.conf

and you will get the configuration written to /tmp/firehol.conf

EOF
		exit 1
		
		fi
		;;
esac

# Remove the next arg if it is --
test "${1}" = "--" && shift

if [ ${FIREHOL_EXPLAIN} -eq 0 -a ${FIREHOL_WIZARD} -eq 0 -a ! -f "${FIREHOL_CONFIG}" ]
then
	echo -n $"FireHOL config ${FIREHOL_CONFIG} not found:"
	failure $"FireHOL config ${FIREHOL_CONFIG} not found:"
	echo
	exit 1
fi


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# MAIN PROCESSING - Interactive mode
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

if [ ${FIREHOL_EXPLAIN} -eq 1 ]
then
	FIREHOL_CONFIG="Interactive User Input"
	FIREHOL_LINEID="1"
	
	FIREHOL_TEMP_CONFIG="${FIREHOL_DIR}/firehol.conf"
	
	echo "version ${FIREHOL_VERSION}" >"${FIREHOL_TEMP_CONFIG}"
	version ${FIREHOL_VERSION}
	
	${CAT_CMD} <<"EOF"

$Id: firehol.sh,v 1.133 2003/06/18 21:44:52 ktsaou Exp $
(C) Copyright 2003, Costa Tsaousis <costa@tsaousis.gr>
FireHOL is distributed under GPL.
Home Page: http://firehol.sourceforge.net

--------------------------------------------------------------------------------
FireHOL controls your firewall. You should want to get updates quickly.
Subscribe (at the home page) to get notified of new releases.
--------------------------------------------------------------------------------

You can now start typing FireHOL configuration directives.
Special interactive commands: help, show, quit

EOF
	
	while [ 1 = 1 ]
	do
		read -p "# FireHOL [${work_cmd}:${work_name}] > " -e -r
		test -z "${REPLY}" && continue
		
		set_work_function -ne "Executing user input"
		
		while [ 1 = 1 ]
		do
		
		set -- ${REPLY}
		
		case "${1}" in
			help)
				${CAT_CMD} <<"EOF"
You can use anything a FireHOL configuration file accepts, including variables,
loops, etc. Take only care to write loops in one row.

Additionaly, you can use the following commands:
	
	help	to print this text on your screen.
	
	show	to show all the successfull commands so far.
	
	quit	to show the interactively given configuration file
		and quit.
	
	in	same as typing: interface eth0 internet
		This is used as a shortcut to get into the server/client
		mode in which you can test the rules for certain
		services.

EOF
				break
				;;
				
			show)
				echo
				${CAT_CMD} "${FIREHOL_TEMP_CONFIG}"
				echo
				break
				;;
				
			quit)
				echo
				${CAT_CMD} "${FIREHOL_TEMP_CONFIG}"
				echo
				exit 1
				;;
				
			in)
				REPLY="interface eth0 internet"
				continue
				;;
				
			*)
				${CAT_CMD} <<EOF

# \/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# Cmd Line : ${FIREHOL_LINEID}
# Command  : ${REPLY}
EOF
				eval "$@"
				if [ $? -gt 0 ]
				then
					printf "\n# > FAILED <\n"
				else
					if [ "${1}" = "interface" -o "${1}" = "router" ]
					then
						echo >>"${FIREHOL_TEMP_CONFIG}"
					else
						printf "	" >>"${FIREHOL_TEMP_CONFIG}"
					fi
					
					printf "%s\n" "${REPLY}" >>"${FIREHOL_TEMP_CONFIG}"
					
					FIREHOL_LINEID=$[FIREHOL_LINEID + 1]
					
					printf "\n# > OK <\n"
				fi
				break
				;;
		esac
		
		break
		done
	done
	
	exit 0
fi


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# MAIN PROCESSING - help wizard
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


if [ ${FIREHOL_WIZARD} -eq 1 ]
then
	wizard_ask() {
		local prompt="${1}"; shift
		local def="${1}"; shift
		
		echo
		
		while [ 1 = 1 ]
		do
			printf >&2 "%s [%s] > " "${prompt}" "${def}"
			read
			
			local ans="${REPLY}"
			
			test -z "${ans}" && ans="${def}"
			
			local c=0
			while [ $c -le $# ]
			do
				eval local t="\${${c}}"
				
				test "${ans}" = "${t}" && break
				c=$[c + 1]
			done
			
			test $c -le $# && return $c
			
			printf >&2 "*** '${ans}' is not a valid answer. Pick one of "
			printf >&2 "%s " "$@"
			echo >&2 
			echo >&2 
		done
		
		return 0
	}
	
	ip_in_net() {
		local ip="${1}"; shift
		local net="${1}"; shift
		
		if [ -z "${ip}" -o -z "${net}" ]
		then
			return 1
		fi
		
		test "${net}" = "default" && net="0.0.0.0/0"
		
		set -- `echo ${ip} | ${TR_CMD} './' '  '`
		local i1=${1}
		local i2=${2}
		local i3=${3}
		local i4=${4}
		
		set -- `echo ${net} | ${TR_CMD} './' '  '`
		local n1=${1}
		local n2=${2}
		local n3=${3}
		local n4=${4}
		local n5=${5:-32}
		
		local i=$[i1*256*256*256 + i2*256*256 + i3*256 + i4]
		local n=$[n1*256*256*256 + n2*256*256 + n3*256 + n4]
		
#		echo "IP : '${i1}' . '${i2}' . '${i3}' . '${i4}'"
#		echo "NET: '${n1}' . '${n2}' . '${n3}' . '${n4}' / '${n5}'"
		
		local d=1
		local c=${n5}
		while [ $c -lt 32 ]
		do
			c=$[c + 1]
			d=$[d * 2]
		done
		
		local nm=$[n + d - 1]
		
		printf "### DEBUG: Is ${ip} part of network ${net}? "
		
		if [ ${i} -ge ${n} -a ${i} -le ${nm} ]
		then
			echo "yes"
			return 0
		else
			echo "no"
			return 1
		fi
	}
	
	ip_is_net() {
		local ip="${1}"; shift
		local net="${1}"; shift
		
		if [ -z "${ip}" -o -z "${net}" ]
		then
			return 1
		fi
		
		test "${net}" = "default" && net="0.0.0.0/0"
		
		set -- `echo ${ip} | ${TR_CMD} './' '  '`
		local i1=${1}
		local i2=${2}
		local i3=${3}
		local i4=${4}
		local i5=${5:-32}
		
		set -- `echo ${net} | ${TR_CMD} './' '  '`
		local n1=${1}
		local n2=${2}
		local n3=${3}
		local n4=${4}
		local n5=${5:-32}
		
		local i=$[i1*256*256*256 + i2*256*256 + i3*256 + i4]
		local n=$[n1*256*256*256 + n2*256*256 + n3*256 + n4]
		
		if [ ${i} -eq ${n} -a ${i5} -eq ${n5} ]
		then
			return 0
		else
			return 1
		fi
	}
	
	ip2net() {
		local ip="${1}"; shift
		
		if [ -z "${ip}" ]
		then
			return 0
		fi
		
		if [ "${ip}" = "default" ]
		then
			echo "default"
			return 0
		fi
		
		set -- `echo ${ip} | ${TR_CMD} './' '  '`
		local i1=${1}
		local i2=${2}
		local i3=${3}
		local i4=${4}
		local i5=${5:-32}
		
		echo ${i1}.${i2}.${i3}.${i4}/${i5}
	}
	
	ips2net() {
		
		(
			if [ "A${1}" = "A-" ]
			then
				while read ip
				do
					ip2net ${ip}
				done
			else
				while [ ! -z "${1}" ]
				do
					ip2net ${1}
					shift 
				done
			fi
		) | ${SORT_CMD} | ${UNIQ_CMD} | ${TR_CMD} "\n" " "
	}
	
	cd "${FIREHOL_DIR}"
	${MKDIR_CMD} ports
	${MKDIR_CMD} keys
	cd ports
	${MKDIR_CMD} tcp
	${MKDIR_CMD} udp
	
	${CAT_CMD} >&2 <<"EOF"

$Id: firehol.sh,v 1.133 2003/06/18 21:44:52 ktsaou Exp $
(C) Copyright 2003, Costa Tsaousis <costa@tsaousis.gr>
FireHOL is distributed under GPL.
Home Page: http://firehol.sourceforge.net

--------------------------------------------------------------------------------
FireHOL controls your firewall. You should want to get updates quickly.
Subscribe (at the home page) to get notified of new releases.
--------------------------------------------------------------------------------

FireHOL will now try to figure out its configuration file on this system.
Please have all the services and network interfaces on this system running.

Your running firewall will not be stopped or altered.

You can re-run the same command with output redirection to get the config
to a file. Example:

EOF
	echo >&2 "${FIREHOL_FILE} helpme >/tmp/firehol.conf"
	echo >&2 
	echo >&2 
		
	echo >&2 
	echo >&2 "Building list of known services."
	echo >&2 "Please wait..."
	
	${CAT_CMD} /etc/services	|\
		${TR_CMD} '\t' ' '	|\
		${SED_CMD} "s/     / /g" |\
		${SED_CMD} "s/     / /g" |\
		${SED_CMD} "s/    / /g" |\
		${SED_CMD} "s/    / /g" |\
		${SED_CMD} "s/   / /g"	|\
		${SED_CMD} "s/   / /g"	|\
		${SED_CMD} "s/  / /g"	|\
		${SED_CMD} "s/  / /g"	|\
		${SED_CMD} "s/  / /g"	|\
		${SED_CMD} "s/  / /g"	|\
		${SED_CMD} "s/  / /g"	>services
	
	for c in `echo ${!server_*} | ${TR_CMD} ' ' '\n' | ${GREP_CMD} "_ports$"`
	do
		serv=`echo $c | ${SED_CMD} "s/server_//" | ${SED_CMD} "s/_ports//"`
		
		eval "ret=\${$c}"
		for x in ${ret}
		do
			proto=`echo $x | ${CUT_CMD} -d '/' -f 1`
			port=`echo $x | ${CUT_CMD} -d '/' -f 2`
			
			test ! -d "${proto}" && continue
			
			nport=`${EGREP_CMD} "^${port}[[:space:]][0-9]+/${proto}" services | ${CUT_CMD} -d ' ' -f 2 | ${CUT_CMD} -d '/' -f 1`
			test -z "${nport}" && nport="${port}"
			
			echo "server ${serv}" >"${proto}/${nport}"
		done
	done
	
	echo "server ftp" >tcp/21
	echo "server nfs" >udp/2049
	
	echo "client amanda" >udp/10080
	
	echo "server dhcp" >udp/67
	echo "server dhcp" >tcp/67
	
	echo "client dhcp" >udp/68
	echo "client dhcp" >tcp/68
	
	echo "server emule" >tcp/4662
	
	echo "server pptp" >tcp/1723
	
	echo "server samba" >udp/137
	echo "server samba" >udp/138
	echo "server samba" >tcp/139
	
	
	wizard_ask "Press RETURN to start." "continue" "continue"
	
	echo >&2 
	echo >&2 "--- snip --- snip --- snip --- snip ---"
	echo >&2 
	
	echo "#!${FIREHOL_FILE}"
	echo "# ------------------------------------------------------------------------------"
	echo "# This feature is under construction -- use it with care."
	echo "#             *** NEVER USE THIS CONFIG AS-IS ***"
	echo "# "

	${CAT_CMD} <<"EOF"
# $Id: firehol.sh,v 1.133 2003/06/18 21:44:52 ktsaou Exp $
# (C) Copyright 2003, Costa Tsaousis <costa@tsaousis.gr>
# FireHOL is distributed under GPL.
# Home Page: http://firehol.sourceforge.net
# 
# ------------------------------------------------------------------------------
# FireHOL controls your firewall. You should want to get updates quickly.
# Subscribe (at the home page) to get notified of new releases.
# ------------------------------------------------------------------------------
#
EOF
	echo "# This config will have the same effect as NO PROTECTION!"
	echo "# Everything that found to be running, is allowed."
	echo "# "
	echo "# Date: `${DATE_CMD}` on host `${HOSTNAME_CMD}`"
	echo "# "
	echo "# The TODOs bellow, are YOUR to-dos!"
	echo
	
	# globals for routing
	set -a found_interfaces=
	set -a found_ips=
	set -a found_nets=
	set -a found_excludes=
	
	helpme_iface() {
		local route="${1}"; shift
		local i="${1}"; shift
		local iface="${1}"; shift
		local ifip="${1}"; shift
		local ifnets="${1}"; shift
		local ifreason="${1}"; shift
		
		# one argument left: ifnets_excluded
		
		if [ "${route}" = "route" ]
		then
			found_interfaces[$i]="${iface}"
			found_ips[$i]="${ifip}"
			found_nets[$i]="${ifnets}"
			found_excludes[$i]="${1}"
		fi
		
		if [ "${ifnets}" = "default" ]
		then
			ifnets="not \"\${UNROUTABLE_IPS} ${1}\""
		else
			ifnets="\"${ifnets}\""
		fi
		
		# output the interface
		echo
		echo "# Interface No $i."
		echo "# The purpose of this interface is to control the traffic"
		if [ ! -z "${ifreason}" ]
		then
			echo "# ${ifreason}."
		else
			echo "# on the ${iface} interface with IP ${ifip} (net: ${ifnets})."
		fi
		echo "# TODO: Change \"interface${i}\" to something with meaning to you."
		echo "# TODO: Check the optional rule parameters (src/dst)."
		echo "# TODO: Remove 'dst ${ifip}' if this is dynamically assigned."
		echo "interface ${iface} interface${i} src ${ifnets} dst ${ifip}"
		echo
		echo "	# The default policy is DROP. You can be more polite with REJECT."
		echo "	# Prefer to be polite on your own clients to prevent timeouts."
		echo "	policy drop"
		echo
		echo "	# If you don't trust the clients behind ${iface} (net ${ifnets}),"
		echo "	# add something like this."
		echo "	# > protection strong"
		echo
		echo "	# Here are the services listening on ${iface}."
		echo "	# TODO: Normally, you will have to remove those not needed."
		
		(
			local x=
			local ports=
			for x in `${NETSTAT_CMD} -an | ${EGREP_CMD} "^tcp" | ${GREP_CMD} "0.0.0.0:*" | ${EGREP_CMD} " (${ifip}|0.0.0.0):[0-9]+" | ${CUT_CMD} -d ':' -f 2 | ${CUT_CMD} -d ' ' -f 1 | ${SORT_CMD} -n | ${UNIQ_CMD}`
			do
				if [ -f "tcp/${x}" ]
				then
					echo "	`${CAT_CMD} tcp/${x}` accept"
				else
					ports="${ports} tcp/${x}"
				fi
			done
			
			for x in `${NETSTAT_CMD} -an | ${EGREP_CMD} "^udp" | ${GREP_CMD} "0.0.0.0:*" | ${EGREP_CMD} " (${ifip}|0.0.0.0):[0-9]+" | ${CUT_CMD} -d ':' -f 2 | ${CUT_CMD} -d ' ' -f 1 | ${SORT_CMD} -n | ${UNIQ_CMD}`
			do
				if [ -f "udp/${x}" ]
				then
					echo "	`${CAT_CMD} udp/${x}` accept"
				else
					ports="${ports} udp/${x}"
				fi
			done
			
			echo "	server ICMP accept"
			
			echo "${ports}" | ${TR_CMD} " " "\n" | ${SORT_CMD} -n | ${UNIQ_CMD} | ${TR_CMD} "\n" " " >unknown.ports
		) | ${SORT_CMD} | ${UNIQ_CMD}
		
		echo
		echo "	# The following ${iface} server ports are not known by FireHOL:"
		echo "	# `${CAT_CMD} unknown.ports`"
		echo "	# TODO: If you need any of them, you should define new services."
		echo "	#       (see Adding Services at the web site - http://firehol.sf.net)."
		echo
		
		echo "	# The following means that this machine can REQUEST anything via ${iface}."
		echo "	# TODO: On production servers, avoid this and allow only the"
		echo "	#       client services you really need."
		echo "	client all accept"
		echo
	}
	
	interfaces=`${IP_CMD} link show | ${EGREP_CMD} "^[0-9A-Za-z]+:" | ${CUT_CMD} -d ':' -f 2 | ${SED_CMD} "s/^ //" | ${GREP_CMD} -v "^lo$" | ${SORT_CMD} | ${UNIQ_CMD} | ${TR_CMD} "\n" " "`
	gw_if=`${IP_CMD} route show | ${GREP_CMD} "^default" | ${SED_CMD} "s/dev /dev:/g" | ${TR_CMD} " " "\n" | ${GREP_CMD} "^dev:" | ${CUT_CMD} -d ':' -f 2`
	gw_ip=`${IP_CMD} route show | ${GREP_CMD} "^default" | ${SED_CMD} "s/via /via:/g" | ${TR_CMD} " " "\n" | ${GREP_CMD} "^via:" | ${CUT_CMD} -d ':' -f 2 | ips2net -`
	
	i=0
	for iface in ${interfaces}
	do
		echo "### DEBUG: Processing interface '${iface}'"
		ips=`${IP_CMD} addr show dev ${iface} | ${SED_CMD} "s/  / /g" | ${SED_CMD} "s/  / /g" | ${SED_CMD} "s/  / /g" | ${GREP_CMD} "^ inet " | ${CUT_CMD} -d ' ' -f 3 | ${CUT_CMD} -d '/' -f 1 | ips2net -`
		peer=`${IP_CMD} addr show dev ${iface} | ${SED_CMD} "s/  / /g" | ${SED_CMD} "s/  / /g" | ${SED_CMD} "s/  / /g" | ${SED_CMD} "s/peer /peer:/g" | ${TR_CMD} " " "\n" | ${GREP_CMD} "^peer:" | ${CUT_CMD} -d ':' -f 2 | ips2net -`
		nets=`${IP_CMD} route show dev ${iface} | ${CUT_CMD} -d ' ' -f 1 | ips2net -`
		
		if [ -z "${ips}" -o -z "${nets}" ]
		then
			echo
			echo "# Ignoring interface '${iface}' because does not have an IP or route."
			echo
			continue
		fi
		
		for ip in ${ips}
		do
			echo "### DEBUG: Processing IP ${ip} of interface '${iface}'"
			
			ifreason=""
			
			# find all the networks this IP can access directly
			# or through its peer
			netcount=0
			unset ifnets
			unset ofnets
			set -a ifnets=
			set -a ofnets=
			for net in ${nets}
			do
				test "${net}" = "default" && continue
				
				found=1
				ip_in_net ${ip} ${net}
				found=$?
				
				if [ ${found} -gt 0 -a ! -z "${peer}" ]
				then
					ip_in_net ${peer} ${net}
					found=$?
				fi
				
				if [ ${found} -eq 0 ]
				then
					# Add it to ifnets
					f=0; ff=0
					while [ $f -lt $netcount ]
					do
						if ip_in_net ${net} ${ifnets[$f]}
						then
							# Already satisfied
							ff=1
						elif ip_in_net ${ifnets[$f]} ${net}
						then
							# New one is superset of old
							ff=1
							ifnets[$f]=${net}
						fi
						
						f=$[f + 1]
					done
					
					if [ $ff -eq 0 ]
					then
						# Add it
						netcount=$[netcount + 1]
						ifnets=(${net} ${ifnets[@]})
					fi
				else
					ofnets=(${net} ${ofnets[@]})
				fi
			done
			
			# find all the networks this IP can access through gateways
			if [ ! -z "${ofnets[*]}" ]
			then
				for net in ${ofnets[@]}
				do
					test "${net}" = "default" && continue
					
					nn=`echo "${net}" | ${CUT_CMD} -d "/" -f 1`
					gw=`${IP_CMD} route show ${nn} dev ${iface} | ${EGREP_CMD} "^${nn}[[:space:]]+via[[:space:]][0-9\.]+" | ${CUT_CMD} -d ' ' -f 3 | ips2net -`
					test -z "${gw}" && continue
					
					for nn in ${ifnets[@]}
					do
						test "${nn}" = "default" && continue
						
						if ip_in_net ${gw} ${nn}
						then
							echo "### DEBUG: Route ${net} is accessed through ${gw}"
							
							# Add it to ifnets
							f=0; ff=0
							while [ $f -lt $netcount ]
							do
								if ip_in_net ${net} ${ifnets[$f]}
								then
									# Already satisfied
									ff=1
								elif ip_in_net ${ifnets[$f]} ${net}
								then
									# New one is superset of old
									ff=1
									ifnets[$f]=${net}
								fi
								
								f=$[f + 1]
							done
							
							if [ $ff -eq 0 ]
							then
								# Add it
								netcount=$[netcount + 1]
								ifnets=(${net} ${ifnets[@]})
							fi
							break
						fi
					done
				done
			fi
			
			# Don't produce an interface if this is just a peer that is also the default gw
			def_ignore_ifnets=0
			if (test ${netcount} -eq 1 -a "${gw_if}" = "${iface}" && ip_is_net "${peer}" "${ifnets[*]}" && ip_is_net "${gw_ip}" "${peer}")
			then
				echo "### DEBUG: Skipping ${iface} peer ${ifnets[*]} only interface (default gateway)."
				echo
				def_ignore_ifnets=1
			else
				i=$[i + 1]
				helpme_iface route $i "${iface}" "${ip}" "${ifnets[*]}" "${ifreason}"
			fi
			
			# Is this interface the default gateway too?
			if [ "${gw_if}" = "${iface}" ]
			then
				for nn in ${ifnets[@]}
				do
					if ip_in_net "${gw_ip}" ${nn}
					then
						echo "### DEBUG: Default gateway ${gw_ip} is part of network ${nn}"
						
						i=$[i + 1]
						helpme_iface route $i "${iface}" "${ip}" "default" "from/to unknown networks behind the default gateway ${gw_ip}" "`test ${def_ignore_ifnets} -eq 0 && echo "${ifnets[*]}"`"
						
						break
					fi
				done
			fi
		done
	done
		
	echo
	echo "# The above $i interfaces were found active at this moment."
	echo "# Add more interfaces that can potentially be activated in the future."
	echo "# FireHOL will not complain if you setup a firewall on an interface that is"
	echo "# not active when you activate the firewall."
	echo "# If you don't setup an interface, FireHOL will drop all traffic from or to"
	echo "# this interface, if and when it becomes available."
	echo "# Also, if an interface name dynamically changes (i.e. ppp0 may become ppp1)"
	echo "# you can use the plus (+) character to match all of them (i.e. ppp+)."
	echo
	
	if [ "1" = "`${CAT_CMD} /proc/sys/net/ipv4/ip_forward`" ]
	then
		x=0
		i=0
		while [ $i -lt ${#found_interfaces[*]} ]
		do
			i=$[i + 1]
			
			inface="${found_interfaces[$i]}"
			src="${found_nets[$i]}"
			
			case "${src}" in
				"default")
					src="not \"\${UNROUTABLE_IPS} ${found_excludes[$i]}\""
					;;
					
					*)
					src="\"${src}\""
					;;
			esac
			
			j=0
			while [ $j -lt ${#found_interfaces[*]} ]
			do
				j=$[j + 1]
				
				test $j -eq $i && continue
				
				outface="${found_interfaces[$j]}"
				dst="${found_nets[$j]}"
				dst_ip="${found_ips[$j]}"
				
				case "${dst}" in
					"default")
						dst="not \"\${UNROUTABLE_IPS} ${found_excludes[$j]}\""
						;;
						
						*)
						dst="\"${dst}\""
						;;
				esac
				
				# Make sure we are not routing to the same subnet
				test "${inface}" = "${outface}" -a "${src}" = "${dst}" && continue
				
				# Make sure this is not a duplicate router
				key="`echo ${inface}/${src}-${outface}/${dst} | ${TR_CMD} "/ \\\$\\\"{}" "______"`"
				test -f "${FIREHOL_DIR}/keys/${key}" && continue
				${TOUCH_CMD} "${FIREHOL_DIR}/keys/${key}"
				
				x=$[x + 1]
				
				echo
				echo "# Router No ${x}."
				echo "# Clients on ${inface} (from ${src}) accessing servers on ${outface} (to ${dst})."
				echo "# TODO: Change \"router${x}\" to something with meaning to you."
				echo "# TODO: Check the optional rule parameters (src/dst)."
				echo "router router${x} inface ${inface} outface ${outface} src ${src} dst ${dst}"
				echo 
				echo "	# If you don't trust the clients on ${inface} (from ${src}), or"
				echo "	# if you want to protect the servers on ${outface} (to ${dst}),"
				echo "	# uncomment the following line."
				echo "	# > protection strong"
				echo
				echo "	# To NAT client requests on the output of ${outface}, add this."
				echo "	# > masquerade"
				
				echo "	# Alternatively, you can SNAT them by placing this at the top of this config:"
				echo "	# > snat to ${dst_ip} outface ${outface} src ${src} dst ${dst}"
				echo "	# SNAT commands can be enhanced using 'proto', 'sport', 'dport', etc in order to"
				echo "	# NAT only some specific traffic."
				echo
				echo "	# TODO: This will allow all traffic to pass."
				echo "	# If you remove it, no REQUEST will pass matching this traffic."
				echo "	route all accept"
				echo
			done
		done
		
		if [ ${x} -eq 0 ]
		then
			echo
			echo
			echo "# No router statements have been produced, because your server"
			echo "# does not seem to need any."
			echo
		fi
	else
		echo
		echo
		echo "# No router statements have been produced, because your server"
		echo "# is not configured for forwarding traffic."
		echo
	fi
	
	exit 0
fi

# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# MAIN PROCESSING
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

# --- Initialization -----------------------------------------------------------

fixed_iptables_save() {
	local tmp="${FIREHOL_DIR}/iptables-save-$$"
	local err=
	
	load_kernel_module ip_tables
	${IPTABLES_SAVE_CMD} -c >$tmp
	err=$?
	if [ ! $err -eq 0 ]
	then
		${RM_CMD} -f $tmp >/dev/null 2>&1
		return $err
	fi
	
	${CAT_CMD} ${tmp} |\
		${SED_CMD} "s/--uid-owner !/! --uid-owner /g"	|\
		${SED_CMD} "s/--gid-owner !/! --gid-owner /g"	|\
		${SED_CMD} "s/--pid-owner !/! --pid-owner /g"	|\
		${SED_CMD} "s/--sid-owner !/! --sid-owner /g"
	
	err=$?
	
	${RM_CMD} -f $tmp >/dev/null 2>&1
	return $err
}

echo -n $"FireHOL: Saving your old firewall to a temporary file:"
fixed_iptables_save >${FIREHOL_SAVED}
if [ $? -eq 0 ]
then
	success $"FireHOL: Saving your old firewall to a temporary file:"
	echo
else
	test -f "${FIREHOL_SAVED}" && ${RM_CMD} -f "${FIREHOL_SAVED}"
	failure $"FireHOL: Saving your old firewall to a temporary file:"
	echo
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Place all the statements bellow to the beginning of the final firewall script.
${CAT_CMD} >"${FIREHOL_OUTPUT}" <<"EOF"
#!/bin/sh

load_kernel_module ip_tables
load_kernel_module ip_conntrack

# Find all tables supported
tables=`${CAT_CMD} /proc/net/ip_tables_names`
for t in ${tables}
do
	# Reset/empty this table.
	${IPTABLES_CMD} -t "${t}" -F >${FIREHOL_OUTPUT}.log 2>&1
	r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t "${t}" -F
	
	${IPTABLES_CMD} -t "${t}" -X >${FIREHOL_OUTPUT}.log 2>&1
	r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t "${t}" -X
	
	${IPTABLES_CMD} -t "${t}" -Z >${FIREHOL_OUTPUT}.log 2>&1
	r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t "${t}" -Z
		
	# Find all default chains in this table.
	chains=`${IPTABLES_CMD} -t "${t}" -nL | ${GREP_CMD} "^Chain " | ${CUT_CMD} -d ' ' -f 2`
	
	# If this is the 'filter' table, remember the default chains.
	# This will be used at the end to make it DROP all packets.
	test "${t}" = "filter" && firehol_filter_chains="${chains}"
	
	# Set the policy to ACCEPT on all default chains.
	for c in ${chains}
	do
		${IPTABLES_CMD} -t "${t}" -P "${c}" ACCEPT >${FIREHOL_OUTPUT}.log 2>&1
		r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t "${t}" -P "${c}" ACCEPT
	done
done

${IPTABLES_CMD} -t filter -P INPUT "${FIREHOL_INPUT_ACTIVATION_POLICY}" >${FIREHOL_OUTPUT}.log 2>&1
r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t filter -P INPUT "${FIREHOL_INPUT_ACTIVATION_POLICY}"

${IPTABLES_CMD} -t filter -P INPUT "${FIREHOL_OUTPUT_ACTIVATION_POLICY}" >${FIREHOL_OUTPUT}.log 2>&1
r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t filter -P INPUT "${FIREHOL_OUTPUT_ACTIVATION_POLICY}"

${IPTABLES_CMD} -t filter -P FORWARD "${FIREHOL_FORWARD_ACTIVATION_POLICY}" >${FIREHOL_OUTPUT}.log 2>&1
r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t filter -P FORWARD "${FIREHOL_FORWARD_ACTIVATION_POLICY}"

# Accept everything in/out the loopback device.
${IPTABLES_CMD} -A INPUT -i lo -j ACCEPT
${IPTABLES_CMD} -A OUTPUT -o lo -j ACCEPT

# Drop all invalid packets.
# Netfilter HOWTO suggests to DROP all INVALID packets.
${IPTABLES_CMD} -A INPUT -m state --state INVALID -j DROP
${IPTABLES_CMD} -A OUTPUT -m state --state INVALID -j DROP
${IPTABLES_CMD} -A FORWARD -m state --state INVALID -j DROP

EOF

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
ret=0

# ------------------------------------------------------------------------------
# Create a small awk script that inserts line numbers in the configuration file
# just before each known directive.
# These line numbers will be used for debugging the configuration script.

${CAT_CMD} >"${FIREHOL_TMP}.awk" <<"EOF"
/^[[:space:]]*interface[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*router[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*route[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*client[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*server[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*iptables[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*protection[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*policy[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*masquerade[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*postprocess[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*transparent_squid[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*nat[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*snat[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*dnat[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
/^[[:space:]]*redirect[[:space:]]/ { printf "FIREHOL_LINEID=${LINENO} " }
{ print }
EOF

${CAT_CMD} ${FIREHOL_CONFIG} | ${GAWK_CMD} -f "${FIREHOL_TMP}.awk" >${FIREHOL_TMP}
${RM_CMD} -f "${FIREHOL_TMP}.awk"

# ------------------------------------------------------------------------------
# Run the configuration file.

enable -n trap			# Disable the trap buildin shell command.
enable -n exit			# Disable the exit buildin shell command.
source ${FIREHOL_TMP} "$@"	# Run the configuration as a normal script.
FIREHOL_LINEID="FIN"
enable trap			# Enable the trap buildin shell command.
enable exit			# Enable the exit buildin shell command.


close_cmd					|| ret=$[ret + 1]
close_master					|| ret=$[ret + 1]

${CAT_CMD} >>"${FIREHOL_OUTPUT}" <<"EOF"

# Make it drop everything on table 'filter'.
for c in ${firehol_filter_chains}
do
	${IPTABLES_CMD} -t filter -P "${c}" DROP >${FIREHOL_OUTPUT}.log 2>&1
	r=$?; test ! ${r} -eq 0 && runtime_error error ${r} INIT ${IPTABLES_CMD} -t filter -P "${c}" DROP
done

EOF

if [ ${work_error} -gt 0 -o $ret -gt 0 ]
then
	echo >&2
	echo >&2 "NOTICE: No changes made to your firewall."
	failure $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
	echo
	exit 1
fi

success $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
echo


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

for m in ${FIREHOL_KERNEL_MODULES}
do
	postprocess -ne load_kernel_module $m
done

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ $FIREHOL_ROUTING -eq 1 ]
then
	postprocess ${SYSCTL_CMD} -w "net.ipv4.ip_forward=1"
fi

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_DEBUG} -eq 1 ]
then
	${CAT_CMD} ${FIREHOL_OUTPUT}
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Activating new firewall:"

source ${FIREHOL_OUTPUT} "$@"

if [ ${work_final_status} -gt 0 ]
then
	failure $"FireHOL: Activating new firewall:"
	echo
	
	# The trap will restore the firewall.
	
	exit 1
fi
success $"FireHOL: Activating new firewall:"
echo

if [ ${FIREHOL_TRY} -eq 1 ]
then
	read -p "Keep the firewall? (type 'commit' to accept - 30 seconds timeout) : " -t 30 -e
	ret=$?
	echo
	if [ ! $ret -eq 0 -o ! "${REPLY}" = "commit" ]
	then
		# The trap will restore the firewall.
		
		exit 1
	else
		echo "Successfull activation of FireHOL firewall."
	fi
fi

# Remove the saved firewall, so that the trap will not restore it.
${RM_CMD} -f "${FIREHOL_SAVED}"

${TOUCH_CMD} /var/lock/subsys/iptables
${TOUCH_CMD} /var/lock/subsys/firehol

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_SAVE} -eq 1 ]
then
	if [ -z "${FIREHOL_AUTOSAVE}" ]
	then
		if [ -d "/etc/sysconfig" ]
		then
			# 
			FIREHOL_AUTOSAVE="/etc/sysconfig/iptables"
		elif [ -d "/var/lib/iptables" ]
		then
			FIREHOL_AUTOSAVE="/var/lib/iptables/autosave"
		else
			error "Cannot find where to save iptables file. Please set FIREHOL_AUTOSAVE."
			echo
			exit 1
		fi
	fi
	
	echo -n $"FireHOL: Saving firewall to ${FIREHOL_AUTOSAVE}:"
	
	fixed_iptables_save >"${FIREHOL_AUTOSAVE}"
	
	if [ ! $? -eq 0 ]
	then
		failure $"FireHOL: Saving firewall to ${FIREHOL_AUTOSAVE}:"
		echo
		exit 1
	fi
	
	success $"FireHOL: Saving firewall to ${FIREHOL_AUTOSAVE}:"
	echo
	exit 0
fi
