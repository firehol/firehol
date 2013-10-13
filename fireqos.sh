#!/bin/bash

# FireQOS - BETA
# A traffic shapper for humans...
# (C) Copyright 2013, Costa Tsaousis
# GPL
# $Id$

# let everyone read our status info
umask 022

me="$0"

shopt -s extglob

FIREQOS_SYSLOG_FACILITY="daemon"
FIREQOS_CONFIG=/etc/firehol/fireqos.conf
FIREQOS_LOCK_FILE=/var/run/fireqos.lock
FIREQOS_LOCK_FILE_TIMEOUT=600
FIREQOS_DIR=/var/run/fireqos

# Set the number of IFB devices to load into the kernel
# Set it in the config file to overwrite this default.
FIREQOS_IFBS=2

# Set it to 1 to see the tc commands generated.
# Set it in the config file to overwrite this default.
FIREQOS_DEBUG=0
FIREQOS_DEBUG_STACK=0
FIREQOS_DEBUG_PORTS=0

# The default and minimum rate for all classes is 1/100
# of the interface bandwidth
FIREQOS_MIN_RATE_DIVISOR=100

# if set to 1, it will print a line per match statement
FIREQOS_SHOW_MATCHES=0

# the classes priority in ballanced mode
FIREQOS_BALLANCED_PRIO=100

FIREQOS_COMPLETED=
fireqos_exit() {
	if [ "$FIREQOS_COMPLETED" = "0" ]
	then
		clear_everything
		echo >&2 "FAILED. Cleared QoS on all interfaces."
		syslog error "QoS FAILED"
		
	elif [ "$FIREQOS_COMPLETED" = "1" ]
	then
		syslog info "QoS applied ok"
		
	fi
	echo >&2 "bye..."
	
	[ -f "${FIREQOS_LOCK_FILE}" ] && rm -f "${FIREQOS_LOCK_FILE}" >/dev/null 2>&1
}

fireqos_concurrent_run_lock() {
	if [ -f "${FIREQOS_LOCK_FILE}" ]
	then
		echo >&2 "FireQOS is already running. Waiting for the other process to exit..."
	fi
	
	lockfile -1 -r ${FIREQOS_LOCK_FILE_TIMEOUT} -l ${FIREQOS_LOCK_FILE_TIMEOUT} "${FIREQOS_LOCK_FILE}" || exit 1
	
	return 0
}

syslog() {
	local p="$1"; shift
	
	logger -p ${FIREQOS_SYSLOG_FACILITY}.$p -t "FireQOS[$$]" "${@}"
	return 0
}

error() {
	echo >&2
	echo >&2 "FAILED: $@"
	exit 1
}

warning() {
	echo >&2 -e ":	\e[1;31mWARNING! $* \e[0m"
}

tc() {
	local noerror=0
	if [ "$1" = "ignore-error" ]
	then
		local noerror=1
		shift
	fi
	
	if [ $FIREQOS_DEBUG -eq 1 ]
	then
		echo -e -n "#\e[33m"
		printf " %q" tc "${@}"
		echo -e "\e[0m"
	fi
	
	if [ $noerror -eq 1 ]
	then
		/sbin/tc "${@}" >/dev/null 2>&1
	else
		/sbin/tc "${@}"
		local ret=$?
		
		if [ $ret -ne 0 ]
		then
			echo >&2 "FAILED: tc failed with error $ret, while executing the command:"
			printf "%q " tc "${@}"
			echo
			exit 1
		fi
	fi
}

device_mtu() {
	ip link show dev "${1}" | sed "s/^.* \(mtu [0-9]\+\) .*$/\1/g" | grep ^mtu | cut -d ' ' -f 2
}

rate2bps() {
	local r="$1"
	local p="$2" # is assumed to be the base rate in bytes per second
	
	# calculate it in bits per second (highest resolution)
	case "$r" in
		+([0-9])kbps)
			local label="Kilobytes per second"
			local identifier="kbps"
			local multiplier=$((8 * 1024))
			;;

		+([0-9])Kbps)
			local label="Kilobytes per second"
			local identifier="Kbps"
			local multiplier=$((8 * 1024))
			;;

		+([0-9])mbps)
			local label="Megabytes per second"
			local identifier="mbps"
			local multiplier=$((8 * 1024 * 1024))
			;;

		+([0-9])Mbps)
			local label="Megabytes per second"
			local identifier="Mbps"
			local multiplier=$((8 * 1024 * 1024))
			;;

		+([0-9])gbps)
			local label="Gigabytes per second"
			local identifier="gbps"
			local multiplier=$((8 * 1024 * 1024 * 1024))
			;;

		+([0-9])Gbps)
			local label="Gigabytes per second"
			local identifier="Gbps"
			local multiplier=$((8 * 1024 * 1024 * 1024))
			;;

		+([0-9])bit)
			local label="bits per second"
			local identifier="bit"
			local multiplier=1
			;;

		+([0-9])kbit)
			local label="Kilobits per second"
			local identifier="kbit"
			local multiplier=1000
			;;

		+([0-9])Kbit)
			local label="Kilobits per second"
			local identifier="Kbit"
			local multiplier=1000
			;;

		+([0-9])mbit)
			local label="Megabits per second"
			local identifier="mbit"
			local multiplier=1000000
			;;

		+([0-9])Mbit)
			local label="Megabits per second"
			local identifier="Mbit"
			local multiplier=1000000
			;;

		+([0-9])gbit)
			local label="Gigabits per second"
			local identifier="gbit"
			local multiplier=1000000000
			;;

		+([0-9])Gbit)
			local label="Gigabits per second"
			local identifier="Gbit"
			local multiplier=1000000000
			;;

		+([0-9])bps)
			local label="Bytes per second"
			local identifier="bps"
			local multiplier=8
			;;

		+([0-9])%)
			local label="Percent"
			local identifier="bps"
			local multiplier=8
			r=$((p * multiplier * `echo $r | sed "s/%//g"` / 100))
			;;

		+([0-9]))
			local label="Kilobits per second"
			local identifier="Kbit"
			local multiplier=1000
			r=$(( r * multiplier ))
			;;

		*)	
			echo >&2 "Invalid rate '${r}' given."
			return 1
			;;
	esac
	
        local n="`echo "$r" | sed "s|$identifier| * $multiplier|g"`"
	
	# evaluate it in bytes per second (the default for a rate in tc)
        eval "local o=\$(($n / 8))"
	
	echo "$o"
	return 0
}

calc_r2q() {
	# r2q is by default 10
	# It is used to find the default quantum (i.e. the size in bytes a class can burst above its ceiling).
	# At the same time quantum cannot be smaller than a single packet (ptu).
	# So, the default is good only if the minimum rate specified to any class is MTU * R2Q = 1500 * 10 = 15000 * 8(bits) = 120kbit
	#
	# To be adaptive, we allocate to the default classes 1/100 of the total bandwidth.
	# This means that we need :
	#
	#  rate = mtu * r2q
	#  or
	#  r2q = rate / mtu
	#
	
	local rate=$1; shift	# we expect the minimum rate that might be given
	local mtu=$1; shift
	[ -z "$mtu" ] && local mtu=1500
	
	local r2q=$(( rate / mtu ))
	
	[ $r2q -lt 1 ] && local r2q=1
	# [ $r2q -gt 10 ] && local r2q=10
	
	echo $r2q
}

parse_class_params() {
	local prefix="$1"; shift
	local parent="$1"; shift
	local ipv4=
	local ipv6=
	
	local priority_mode=
	local prio=
	local qdisc=
	local minrate=
	local rate=
	local ceil=
	local r2q=
	local burst=
	local cburst=
	local quantum=
	local mtu=
	local mpu=
	local tsize=
	local linklayer=
	
	eval local base_rate="\$${parent}_rate"
	
	case "$force_ipv" in
		4)
			local ipv4=1
			local ipv6=0
			;;
		
		6)
			local ipv4=0
			local ipv6=1
			;;
			
		46)
			local ipv4=1
			local ipv6=1
			;;
	esac
	
	# find all work_X arguments
	while [ ! -z "$1" ]
	do
		case "$1" in
			priority|ballanced)
					local priority_mode="$1"
					;;
					
			prio)
					local prio="$2"
					shift
					;;
			qdisc)	
					local qdisc="$2"
					shift
					;;
			
			sfq|pfifo|bfifo)
					local qdisc="$1"
					;;
					
			minrate)
					[ "$prefix" = "class" ] && error "'$1' cannot be used in classes."
					
					local minrate="`rate2bps $2 $base_rate`"
					shift
					;;
					
			rate|min|commit)
					local rate="`rate2bps $2 $base_rate`"
					shift
					;;
					
			ceil|max)
					local ceil="`rate2bps $2 $base_rate`"
					shift
					;;
					
			r2q)
					[ "$prefix" = "class" ] && error "'$1' cannot be used in classes."
					
					local r2q="$2"
					shift
					;;
					
			burst)
					local burst="$2"
					shift
					;;
					
			cburst)
					local cburst="$2"
					shift
					;;
					
			quantum)
					# must be as small as possible, but larger than mtu
					local quantum="$2"
					shift
					;;
					
			mtu)
					local mtu="$2"
					shift
					;;
			
			mpu)
					local mpu="$2"
					shift
					;;
			
			tsize)
					local tsize="$2"
					shift
					;;
			
			overhead)
					local overhead="$2"
					shift
					;;
			
			adsl)
					local linklayer="$1"
					local diff=0
					case "$2" in
						local)	local diff=0
							;;
							
						remote)	local diff=-14
							;;
							
						*)	error "Unknown adsl option '$2'."
							return 1
							;;
					esac
					
					# default overhead values taken from http://ace-host.stuart.id.au/russell/files/tc/tc-atm/
					case "$3" in
						IPoA-VC/Mux|ipoa-vcmux|ipoa-vc|ipoa-mux)
								local overhead=$((8 + diff))
								;;
						IPoA-LLC/SNAP|ipoa-llcsnap|ipoa-llc|ipoa-snap)
								local overhead=$((16 + diff))
								;;
						Bridged-VC/Mux|bridged-vcmux|bridged-vc|bridged-mux)
								local overhead=$((24 + diff))
								;;
						Bridged-LLC/SNAP|bridged-llcsnap|bridged-llc|bridged-snap)
								local overhead=$((32 + diff))
								;;
						PPPoA-VC/Mux|pppoa-vcmux|pppoa-vc|pppoa-mux)
								local overhead=$((10 + diff))
								[ "$2" = "remote" ] && local mtu=1478
								;;
						PPPoA-LLC/SNAP|pppoa-llcsnap|pppoa-llc|pppoa-snap)
								local overhead=$((14 + diff))
								;;
						PPPoE-VC/Mux|pppoe-vcmux|pppoe-vc|pppoe-mux)
								local overhead=$((32 + diff))
								;;
						PPPoE-LLC/SNAP|pppoe-llcsnap|pppoe-llc|pppoe-snap)
								local overhead=$((40 + diff))
								[ "$2" = "remote" ] && local mtu=1492
								;;
						*)
								error "Cannot understand adsl protocol '$3'."
								return 1
								;;
					esac
					shift 2
					;;
					
			atm|ethernet)
					local linklayer="$1"
					;;
					
			*)		error "Cannot understand what '${1}' means."
					return 1
					;;
		esac
		
		shift
	done
	
	# export our parameters for the caller
	# for every parameter not set, use the parent value
	# for every one set, use the set value
	local param=
	for param in ceil burst cburst quantum qdisc ipv4 ipv6 priority_mode
	do
		eval local value="\$$param"
		if [ -z "$value" ]
		then
			eval export ${prefix}_${param}="\${${parent}_${param}}"
		else
			eval export ${prefix}_${param}="\$$param"
		fi
	done
	
	# no inheritance for these parameters
	local param=
	for param in rate mtu mpu tsize overhead linklayer r2q prio minrate
	do
		eval export ${prefix}_${param}="\$$param"
	done
	
	return 0
}

parent_path=
parent_stack_size=0
parent_push() {
	local param=
	local prefix="$1"; shift
	local vars="classid major sumrate default_class default_added filters_to name ceil burst cburst quantum qdisc rate mtu mpu tsize overhead linklayer r2q prio ipv4 ipv6 minrate priority_mode"
	
	if [ $FIREQOS_DEBUG_STACK -eq 1 ]
	then
		eval "local before=\$parent_stack_${parent_stack_size}"
		echo "PUSH $prefix: OLD(${parent_stack_size}): $before"
	fi
	
	# refresh the existing parent_* values to stack
	eval "parent_stack_${parent_stack_size}="
	for param in $vars
	do
		eval "parent_stack_${parent_stack_size}=\"\${parent_stack_${parent_stack_size}}parent_$param=\$parent_$param;\""
	done
	
	if [ $FIREQOS_DEBUG_STACK -eq 1 ]
	then
		eval "local after=\$parent_stack_${parent_stack_size}"
		echo "PUSH $prefix: REFRESHED(${parent_stack_size}): $after"
	fi
	
	# now push the new values into the stack
	parent_stack_size=$((parent_stack_size + 1))
	eval "parent_stack_${parent_stack_size}="
	for param in $vars
	do
		eval "parent_$param=\$${prefix}_$param"
		eval "parent_stack_${parent_stack_size}=\"\${parent_stack_${parent_stack_size}}parent_$param=\$${prefix}_$param;\""
	done
	
	if [ $FIREQOS_DEBUG_STACK -eq 1 ]
	then
		eval "local push=\$parent_stack_${parent_stack_size}"
		echo "PUSH $prefix: NEW(${parent_stack_size}): $push"
		#-- set | grep ^parent
	fi
	
	if [ "$prefix" = "interface" ]
	then
		parent_path=
	else
		parent_path="$parent_path$parent_name/"
	fi
	[ $FIREQOS_DEBUG_STACK -eq 1 ] && echo "PARENT_PATH=$parent_path"
	
	set_tabs
}

parent_pull() {
	if [ $parent_stack_size -lt 1 ]
	then
		error "Cannot pull a not pushed set of values from stack."
		exit 1
	fi
	
	parent_stack_size=$((parent_stack_size - 1))
	
	eval "eval \${parent_stack_${parent_stack_size}}"
	
	if [ $FIREQOS_DEBUG_STACK -eq 1 ]
	then
		eval "local pull=\$parent_stack_${parent_stack_size}"
		echo "PULL(${parent_stack_size}): $pull"
		#-- set | grep ^parent
	fi
	
	if [ $parent_stack_size -gt 1 ]
	then
		parent_path="`echo $parent_path | cut -d '/' -f 1-$((parent_stack_size - 1))`/"
	else
		parent_path=
	fi
	[ $FIREQOS_DEBUG_STACK -eq 1 ] && echo "PARENT_PATH=$parent_path"
	
	set_tabs
}

parent_clear() {
	parent_stack_size=0

	set_tabs
}

class_tabs=
set_tabs() {
	class_tabs=
	local x=
	for x in `seq 1 $parent_stack_size`
	do
		class_tabs="$class_tabs	"
	done
}

check_constrains() {
	local prefix="$1"
	eval "local mtu=\$${prefix}_mtu"
	eval "local burst=\$${prefix}_burst"
	eval "local cburst=\$${prefix}_cburst"
	eval "local quantum=\$${prefix}_quantum"
	eval "local rate=\$${prefix}_rate"
	eval "local ceil=\$${prefix}_ceil"
	eval "local minrate=\$${prefix}_minrate"
	
	# check the constrains
	if [ ! -z "$mtu" ]
	then
		if [ ! -z "$quantum" ]
		then
			if [ $quantum -lt $mtu ]
			then
				warning "quantum ($quantum bytes) is less than MTU ($mtu bytes). Fixed it by setting quantum to MTU."
				eval "${prefix}_quantum=$mtu"
			fi
		fi
		
		if [ ! -z "$burst" ]
		then
			if [ $burst -lt $mtu ]
			then
				warning "burst ($burst bytes) is less than MTU ($mtu bytes). Fixed it by setting burst to MTU."
				eval "${prefix}_burst=$mtu"
			fi
		fi
		
		if [ ! -z "$cburst" ]
		then
			if [ $cburst -lt $mtu ]
			then
				warning "cburst ($cburst bytes) is less than MTU ($mtu bytes). Fixed it by setting cburst to MTU."
				eval "${prefix}_cburst=$mtu"
			fi
		fi
		
		if [ ! -z "$minrate" ]
		then
			if [ $minrate -lt $mtu ]
			then
				warning "minrate ($minrate bytes per second) is less than MTU ($mtu bytes). Fixed it by setting minrate to MTU."
				eval "${prefix}_minrate=$mtu"
			fi
		fi
	fi
	
	if [ ! -z "$ceil" ]
	then
		if [ $ceil -lt $rate ]
		then
			warning "ceil ($((ceil * 8 / 1000))kbit) is less than rate ($((rate * 8 / 1000))kbit). Fixed it by setting ceil to rate."
			eval "${prefix}_ceil=$rate"
		fi
	fi
	
	[ "$prefix" = "interface" ] && return 0
	
	if [ ! -z "$ceil" ]
	then
		if [ $ceil -gt $parent_ceil ]
		then
			warning "ceil ($((ceil * 8 / 1000))kbit) is more than its parent's ceil ($((parent_ceil * 8 / 1000))kbit). Fixed it by settting ceil to parent's ceil."
			eval "${prefix}_ceil=$parent_ceil"
		fi
	fi
	
	if [ ! -z "$burst" -a ! -z "$parent_burst" ]
	then
		if [ $burst -gt $parent_burst ]
		then
			warning "burst ($burst bytes) is less than its parent's burst ($parent_burst bytes). Fixed it by setting burst to parent's burst."
			eval "${prefix}_burst=$parent_burst"
		fi
	fi
	
	if [ ! -z "$cburst" -a ! -z "$parent_cburst" ]
	then
		if [ $cburst -gt $parent_cburst ]
		then
			warning "cburst ($cburst bytes) is less than its parent's cburst ($parent_cburst bytes). Fixed it by setting cburst to parent's cburst."
			eval "${prefix}_cburst=$parent_cburst"
		fi
	fi
	
	return 0
}

interface_major=
interface_dev=
interface_name=
interface_inout=
interface_realdev=
interface_minrate=
interface_class_counter=
interface_qdisc_counter=
interface_default_added=
interface_default_class=
interface_classes=
interface_classes_ids=
interface_classes_monitor=
interface_sumrate=0
interface_classid=
class_matchid=

ifb_counter=
force_ipv=

interface_close() {
	if [ ! -z "$interface_dev" ]
	then
		# close all open class groups
		while [ $parent_stack_size -gt 1 ]
		do
			class group end
		done
		
		# if we have not added the default class
		# for the interface, add it now
		if [ $parent_default_added -eq 0 ]
		then
			class default
			parent_default_added=1
		fi
		
		# NOT NEEDED - the default for interfaces works via kernel.
		# match all class default flowid $interface_major:$parent_default_class prio 0xffff
	fi
	
	echo "interface_classes='TOTAL|${interface_major}:1 $interface_classes'" >>"${FIREQOS_DIR}/${interface_name}.conf"
	echo "interface_classes_ids='${interface_major}_1 $interface_classes_ids'" >>"${FIREQOS_DIR}/${interface_name}.conf"
	echo "interface_classes_monitor='$interface_classes_monitor'" >>"${FIREQOS_DIR}/${interface_name}.conf"
	echo
	parent_clear
	
	interface_major=1
	interface_dev=
	interface_name=
	interface_inout=
	interface_realdev=
	interface_minrate=
	interface_class_counter=10
	interface_qdisc_counter=10
	interface_default_added=0
	interface_default_class=5000
	interface_classes=
	interface_classes_ids=
	interface_classes_monitor=
	interface_sumrate=0
	interface_classid=
	class_matchid=1
	parent_stack_size=0
	
	return 0
}

FIREQOS_LOADED_IFBS=0

ipv4() {
	force_ipv="4"
	"${@}"
	force_ipv=
}

ipv6() {
	force_ipv="6"
	"${@}"
	force_ipv=
}

ipv46() {
	force_ipv="46"
	"${@}"
	force_ipv=
}

interface4() {
	ipv4 interface "${@}"
}

interface6() {
	ipv6 interface "${@}"
}

interface46() {
	ipv46 interface "${@}"
}

interface() {
	interface_close
	
	printf ": ${FUNCNAME} %s" "$*"
	
	interface_dev="$1"; shift
	interface_name="$1"; shift
	interface_inout="$1"; shift
	
	if [ "$interface_inout" = "input" ]
	then
		# Find an available IFB device to use.
		if [ -z "$ifb_counter" ]
		then
			# we start at 1
			# we need ifb0 for live monitoring of traffic
			ifb_counter=1
		else
			ifb_counter=$((ifb_counter + 1))
		fi
		interface_realdev=ifb$ifb_counter
		
		# check if we run out of IFB devices
		if [ $ifb_counter -ge $((FIREQOS_IFBS + 1)) ]
		then
			error "You don't have enough IFB devices. Please add FIREQOS_IFBS=XX at the top of your config. Replace XX with a number high enough for the 'input' interfaces you define."
			exit 1
		fi
		
		if [ $FIREQOS_LOADED_IFBS -eq 0 ]
		then
			# we open +1 IFBs to leave ifb0 for live monitoring of traffic
			modprobe ifb numifbs=$((FIREQOS_IFBS + 1)) || exit 1
			FIREQOS_LOADED_IFBS=1
		fi
		
		ip link set dev $interface_realdev up
		if [ $? -ne 0 ]
		then
			error "Cannot bring device $interface_realdev UP."
			exit 1
		fi
	else
		# for 'output' interfaces, realdev is dev
		interface_realdev=$interface_dev
	fi
	
	# parse the parameters given
	parse_class_params interface noparent "${@}"
	
	[ -z "$interface_priority_mode" ] && interface_priority_mode="priority"
	
	if [ -z "$interface_ipv4" -a -z "$interface_ipv6" ]
	then
		interface_ipv4=1
		interface_ipv6=0
	elif [ -z "$interface_ipv4" ]
	then
		interface_ipv4=0
	elif [ -z "$interface_ipv6" ]
	then
		interface_ipv6=0
	fi
	
	# check important arguments
	if [ -z "$interface_rate" ]
	then
		error "Cannot figure out the rate of interface '${interface_dev}'."
		return 1
	fi
	
	if [ -z "$interface_mtu" ]
	then
		# to find the mtu, we query the original device, not an ifb device
		interface_mtu=`device_mtu $interface_dev`
		
		if [ -z "$interface_mtu" ]
		then
			interface_mtu=1500
			warning "Device MTU cannot be detected. Setting it to 1500 bytes."
		fi
	fi
	
	# fix stab
	local stab=
	if [ ! -z "$interface_linklayer" -o ! -z "$interface_overhead" -o ! -z "$interface_mtu" -o ! -z "$interface_mpu" -o ! -z "$interface_overhead" ]
	then
		local stab="stab"
		test ! -z "$interface_linklayer"	&& local stab="$stab linklayer $interface_linklayer"
		test ! -z "$interface_overhead"		&& local stab="$stab overhead $interface_overhead"
		test ! -z "$interface_tsize"		&& local stab="$stab tsize $interface_tsize"
		test ! -z "$interface_mtu"		&& local stab="$stab mtu $interface_mtu"
		test ! -z "$interface_mpu"		&& local stab="$stab mpu $interface_mpu"
	fi
	
	# the default ceiling for the interface, is the rate of the interface
	# if we don't respect this, all unclassified traffic will get just 1kbit!
	[ -z "$interface_ceil" ] && interface_ceil=$interface_rate
	
	# set the default qdisc for all classes
	[ -z "$interface_qdisc" ] && interface_qdisc="sfq"
	
	# the desired minimum rate for all classes
	[ -z "$interface_minrate" ] && interface_minrate=$((interface_rate / FIREQOS_MIN_RATE_DIVISOR))
	
	# calculate the default r2q for this interface
	# *** THIS MAY NOT BE NEEDED ANYMORE, SINCE WE ALWAYS SET QUANTUM ***
	if [ -z "$interface_r2q" ]
	then
		interface_r2q=`calc_r2q $interface_minrate $interface_mtu`
	fi
	
	# the actual minimum rate we can get
	local r=$((interface_r2q * interface_mtu))
	[ $r -gt $interface_minrate ] && interface_minrate=$r
	
	# set the default quantum
	[ -z "$interface_quantum" ] && interface_quantum=$interface_mtu
	
	check_constrains interface
	
	local rate="rate $((interface_rate * 8 / 1000))kbit"
	local minrate="rate $((interface_minrate * 8 / 1000))kbit"
	[ ! -z "$interface_ceil" ]			&& local ceil="ceil $((interface_ceil * 8 / 1000))kbit"
	[ ! -z "$interface_burst" ]			&& local burst="burst $interface_burst"
	[ ! -z "$interface_cburst" ]			&& local cburst="cburst $interface_cburst"
	[ ! -z "$interface_quantum" ]			&& local quantum="quantum $interface_quantum"
	[ ! -z "$interface_r2q" ]			&& local r2q="r2q $interface_r2q"
	
	echo -e " \e[1;34m($interface_realdev, MTU $interface_mtu, quantum $interface_quantum)\e[0m"
	
	# Add root qdisc with proper linklayer and overheads
	tc qdisc add dev $interface_realdev $stab root handle $interface_major: htb default $interface_default_class $r2q
	
	# redirect all incoming traffic to ifb
	if [ $interface_inout = input ]
	then
		# Redirect all incoming traffic to ifbX
		# We then shape the traffic in the output of ifbX
		tc qdisc add dev $interface_dev ingress
		
		# [ $interface_ipv4 -eq 1 ] && tc filter add dev $interface_dev parent ffff: protocol ip  prio 1 u32 match u32 0 0 action mirred egress redirect dev $interface_realdev
		# [ $interface_ipv6 -eq 1 ] && tc filter add dev $interface_dev parent ffff: protocol ipv6 prio 1 u32 match u32 0 0 action mirred egress redirect dev $interface_realdev
		tc filter add dev $interface_dev parent ffff: protocol all prio 1 u32 match u32 0 0 action mirred egress redirect dev $interface_realdev
	fi
	
	interface_classid="$interface_major:1"
	
	# Add the root class for the interface
	tc class add dev $interface_realdev parent $interface_major: classid $interface_classid htb $rate $ceil $burst $cburst $quantum
	
	interface_filters_to="$interface_major:0"
	
	parent_push interface
	
	[ -f "${FIREQOS_DIR}/${interface_name}.conf" ] && rm "${FIREQOS_DIR}/${interface_name}.conf"
	cat >"${FIREQOS_DIR}/${interface_name}.conf" <<EOF
interface_name=$interface_name
interface_rate=$interface_rate
interface_ceil=$interface_ceil
interface_dev=$interface_dev
interface_realdev=$interface_realdev
interface_inout=$interface_inout
interface_minrate=$interface_minrate
interface_linklayer=$interface_linklayer
interface_overhead=$interface_overhead
interface_minrate=$interface_minrate
interface_r2q=$interface_r2q
interface_burst=$interface_burst
interface_cburst=$interface_cburst
interface_quantum=$interface_quantum
interface_mtu=$interface_mtu
interface_mpu=$interface_mpu
interface_tsize=$interface_tsize
interface_qdisc=$interface_qdisc
class_${interface_major}_1_name=TOTAL
class_${interface_major}_1_classid=CLASSID
class_${interface_major}_1_priority=PRIORITY
class_${interface_major}_1_rate=COMMIT
class_${interface_major}_1_ceil=MAX
class_${interface_major}_1_burst=BURST
class_${interface_major}_1_cburst=CBURST
class_${interface_major}_1_quantum=QUANTUM
class_${interface_major}_1_qdisc=QDISC
EOF
	
	echo $interface_name >>$FIREQOS_DIR/interfaces
	return 0
}

class_name=
class_classid=
class_major=
class_group=0

class4() {
	ipv4 class "${@}"
}

class6() {
	ipv6 class "${@}"
}

class46() {
	ipv46 class "${@}"
}

class() {
	# check if the have to push into the stack the last class (if it was a group class)
	if [ $class_group -eq 1 ]
	then
		# the last class was a group 
		# filters have been added to it, and now we have reached its first child class
		# we push the previous class, into the our parents stack
		
		class_default_added=0
		parent_push class
		
		# the current command is the first child class
	fi
	
	printf ": $class_tabs${FUNCNAME} %s" "$*"
	
	# reset the values of the current class
	class_name=
	class_classid=
	class_major=
	class_group=0
	
	# if this is a group class
	if [ "$1" = "group" ]
	then
		shift
		
		# if this is the end of a group class
		if [ "$1" = "end" ]
		then
			shift
			
			if [ $parent_stack_size -le 1 ]
			then
				error "No open class group to end."
				exit 1
			fi
			
			echo
			if [ $parent_default_added -eq 0 ]
			then
				class default
			fi
			
			# In nested classes, the default of the parent class is not respected
			# by the kernel. This rule, sends all remaining traffic to the inner default.
			match all class default flowid $parent_major:$parent_default_class prio 0xffff
			
			parent_pull
			return 0
		elif [ "$1" = "default" ]
		then
			error "The default class cannot have subclasses."
			exit 1
		fi
		
		class_group=1
	fi
	
	class_name="$1"; shift
	
	# increase the id of this class
	interface_class_counter=$((interface_class_counter + 1))
	
	# if this is the default class, use the pre-defined
	# id, otherwise use the classid we just increased
	if [ "$class_name" = "default" ]
	then
		local id=$parent_default_class
	else
		local id=$interface_class_counter
	fi
	
	# the tc classid that we will create
	# this is used for the parent of all child classed
	class_classid="$parent_major:$id"
	
	# the flowid the matches on this class will classify the packets
	class_filters_flowid="$parent_major:$id"
	
	# the id of the class in the config, for getting status info about it
	local ncid="${parent_major}_$id"
	
	# the handle of the new qdisc we will create
	interface_qdisc_counter=$((interface_qdisc_counter + 1))
	class_major=$interface_qdisc_counter
	
	parse_class_params class parent "${@}"
	
	# the priority of this class, compared to the others in the same interface
	if [ -z "$class_prio" ]
	then
		[ "$parent_priority_mode" = "ballanced" ] && class_prio=$FIREQOS_BALLANCED_PRIO
		[ -z "$class_prio" ] && class_prio=$((interface_class_counter - 10))
	fi
	
	# if not specified, set the minimum rate
	[ -z "$class_rate" ] && class_rate=$interface_minrate
	
	# class rate cannot go bellow 1/100 of the interface rate
	[ $class_rate -lt $interface_minrate ] && class_rate=$interface_minrate
	
	check_constrains class
	
	[ ! -z "$class_rate" ]		&& local rate="rate $((class_rate * 8 / 1000))kbit"
	[ ! -z "$class_ceil" ]		&& local ceil="ceil $((class_ceil * 8 / 1000))kbit"
	[ ! -z "$class_burst" ]		&& local burst="burst $class_burst"
	[ ! -z "$class_cburst" ]	&& local cburst="cburst $class_cburst"
	[ ! -z "$class_quantum" ]	&& local quantum="quantum $class_quantum"
	
	echo -e "\e[1;34m class $class_classid, priority $class_prio\e[0m"
	
	# keep track of all classes in the interface, so that the matches can name them to get their flowid
	interface_classes="$interface_classes $class_name|$class_filters_flowid"
	interface_classes_ids="$interface_classes_ids $ncid"
	
	# check it the user overbooked the parent
	parent_sumrate=$((parent_sumrate + $class_rate))
	if [ $parent_sumrate -gt $parent_rate ]
	then
		warning "The classes under $parent_name commit more bandwidth (+$(( (parent_sumrate - parent_rate) * 8 / 1000 ))kbit) than the available rate."
	fi
	
	# add the class
	tc class add dev $interface_realdev parent $parent_classid classid $class_classid htb $rate $ceil $burst $cburst prio $class_prio $quantum
	
	# construct the stab for group class
	# later we will check if this is accidentaly used in leaf classes
	local stab=
	if [ ! -z "$class_linklayer" -o ! -z "$class_overhead" -o ! -z "$class_mtu" -o ! -z "$class_mpu" -o ! -z "$class_overhead" ]
	then
		local stab="stab"
		test ! -z "$class_linklayer"	&& local stab="$stab linklayer $class_linklayer"
		test ! -z "$class_overhead"	&& local stab="$stab overhead $class_overhead"
		test ! -z "$class_tsize"	&& local stab="$stab tsize $class_tsize"
		test ! -z "$class_mtu"		&& local stab="$stab mtu $class_mtu"
		test ! -z "$class_mpu"		&& local stab="$stab mpu $class_mpu"
	fi
	
	class_default_class=
	if [ $class_group -eq 1 ]
	then
		# this class will have subclasses
		
		# the default class that all unmatched traffic will be sent to
		class_default_class="$((interface_default_class + interface_qdisc_counter))"
		
		# if the user added a stab, we need a qdisc and a slave class bellow the qdisc
		if [ ! -z "$stab" ]
		then
			# this is a group class with a linklayer
			# we add a qdisc with the stab, and an HTB class bellow it
			
			# attach a qdisc
			tc qdisc add dev $interface_realdev $stab parent $class_classid handle $class_major: htb default $class_default_class
			
			# attach a class bellow the qdisc
			tc class add dev $interface_realdev parent $class_major: classid $class_major:1 htb $rate $ceil $burst $cburst $quantum
			
			# the parent of the child classes
			class_classid="$class_major:1"
			
			# the qdisc the filters of all child classes should be attached to
			class_filters_to="$class_major:0"
		else
			# this is a group class without a linklayer
			# there is no need for a qdisc (HTB class directly attached to an HTB class)
			class_major=$parent_major
			class_filters_to="$class_classid"
		fi
		
		# this class will become a parent [parent_push()], as soon as we encounter the next class.
		# we don't push it now as the parent, because we need to add filters to its parent, redirecting traffic to this class.
		# so we add the filters and when we encounter the next class, we push it into the parents' stack, so that it becomes
		# the parent for all classes following, until we encounter its matching 'class group end'.
		
	else
		# this is a leaf class (no child classes possible)
		
		if [ ! -z "$stab" ]
		then
			error "Linklayer can be used only in interfaces and group classes."
			exit 1
		fi
		
		case "$class_qdisc" in
			htb)	local qdisc="htb"
				;;
			
			sfq)	local qdisc="sfq perturb 10"
				;;
			
			*)	local qdisc="$class_qdisc"
				;;
		esac
		
		# attach a qdisc to it for handling all traffic
		tc qdisc add dev $interface_realdev $stab parent $class_classid handle $class_major: $qdisc
		
		# if this is the default, make sure we don't added again
		if [ "$class_name" = "default" ]
		then
			parent_default_added=1
			interface_classes_monitor="$interface_classes_monitor $parent_path$class_name|$parent_path$class_name|$class_classid|$class_major:"
		else
			interface_classes_monitor="$interface_classes_monitor $class_name|$parent_path$class_name|$class_classid|$class_major:"
		fi
	fi
	
	local name="$class_name"
	[ $parent_stack_size -gt 1 ] && local name="${parent_name:0:2}/$class_name"
	
	# save the configuration
	cat >>"${FIREQOS_DIR}/${interface_name}.conf" <<EOF
class_${ncid}_name=$name
class_${ncid}_classid=$class_classid
class_${ncid}_priority=$class_prio
class_${ncid}_rate=$class_rate
class_${ncid}_ceil=$class_ceil
class_${ncid}_burst=$class_burst
class_${ncid}_cburst=$class_cburst
class_${ncid}_quantum=$class_quantum
class_${ncid}_qdisc=$class_qdisc
EOF
	
	return 0
}

find_port_masks() {
	local from=$(($1))
	local to=$(($2))
	
	if [ -z "$to" ]
	then
		[ $FIREQOS_DEBUG_PORTS -eq 1 ] && echo >&2 "$from/0xffff"
		echo "$from/0xffff"
		return 0
	fi
	
	if [ $from -ge $to ]
	then
		[ $FIREQOS_DEBUG_PORTS -eq 1 ] && echo >&2 "$from/0xffff"
		echo "$from/0xffff"
		return 0
	fi
	
	# find the biggest power of two that fits in the range
	# starting from $from
	local i=
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17
	do
		local base=$(( (from >> i) << i ))
		local end=$(( base + (1 << i) - 1 ))

		[ $FIREQOS_DEBUG_PORTS -eq 1 ] && printf >&2 ": >>> examine bit %d, from 0x%04x (%s) to 0x%04x (%s), " $i $base $base $end $end

		[ $base -ne $from ] && break
		[ $end -gt $to ] && break

		[ $FIREQOS_DEBUG_PORTS -eq 1 ] && echo >&2 " ok"
	done
	[ $FIREQOS_DEBUG_PORTS -eq 1 ] && echo >&2 " failed"
	
	i=$[ i - 1 ]
	local base=$(( (from >> i) << i ))
	local end=$(( base + (1 << i) - 1 ))
	local mask=$(( (0xffff >> i) << i ))
	
	[ $FIREQOS_DEBUG_PORTS -eq 1 ] && printf >&2 ": 0x%04x (%d) to 0x%04x (%d),  match 0x%04x (%d) to 0x%04x (%d) with mask 0x%04x \n" $from $from $to $to $base $base $end $$
	printf "%d/0x%04x\n" $base $mask
	if [ $end -lt $to ]
	then
		local next=$[end + 1]
		[ $FIREQOS_DEBUG_PORTS -eq 1 ] && printf >&2 "\n: next range 0x%04x (%d) to 0x%04x (%d)\n" $next $next $to $to
		find_port_masks $next $to
	fi
	return 0
}

expand_ports() {
	while [ ! -z "$1" ]
	do
		local p=`echo $1 | tr ":-" "  "`
		case $p in
			any|all)
				echo $p
				;;
			
			*)	find_port_masks $p
				;;
		esac
		shift
	done
	return 0
}

match4() {
	ipv4 match "${@}"
}

match6() {
	ipv6 match "${@}"
}

match46() {
	ipv46 match "${@}"
}

match() {
	[ $FIREQOS_DEBUG -eq 1 -o $FIREQOS_SHOW_MATCHES -eq 1 ] && echo ":		${FUNCNAME} $*"
	
	local proto=any
	local port=any
	local sport=any
	local dport=any
	local src=any
	local dst=any
	local ip=any
	local tos=any
	local mark=any
	local class=$class_name
	local flowid=$class_filters_flowid
	local ack=0
	local syn=0
	local at=
	local custom=
	local tcproto=
	local ipv4=$class_ipv4
	local ipv6=$class_ipv6
	
	case "$force_ipv" in
		4)
			local ipv4=1
			local ipv6=0
			;;
		
		6)
			local ipv4=0
			local ipv6=1
			;;
			
		46)
			local ipv4=1
			local ipv6=1
			;;
	esac
	
	while [ ! -z "$1" ]
	do
		case "$1" in
			at)
				local at="$2"
				shift
				;;
			
			syn|syns)
				local syn=1
				;;
				
			ack|acks)
				local ack=1
				;;
				
			arp)
				local tcproto="$1"
				;;
				
			tcp|TCP|udp|UDP|icmp|ICMP|gre|GRE|ipv6|IPv6|all)
				local proto="$1"
				;;
				
			tos|priority)
				local tos="$2"
				shift
				;;
				
			mark|marks)
				local mark="$2"
				shift
				;;
				
			proto|protocol|protocols)
				local proto="$2"
				shift
				;;
			
			port|ports)
				local port="$2"
				shift
				;;
			
			sport|sports)
				local sport="$2"
				shift
				;;
			
			dport|dports)
				local dport="$2"
				shift
				;;
			
			src)
				local src="$2"
				shift
				;;
			
			dst)
				local dst="$2"
				shift
				;;
			
			prio)
				local prio="$2"
				shift
				;;
			
			ip|ips|net|nets|host|hosts)
				local ip="$2"
				shift
				;;
			
			class)
				local class="$2"
				shift
				;;
			
			flowid)
				local flowid="$2"
				shift
				;;
			
			custom)
				local custom="$2"
				shift
				;;
				
			*)	error "Cannot understand what the filter '${1}' is."
				return 1
				;;
		esac
		shift
	done
	
	if [ -z "$prio" ]
	then
		local prio=$((class_matchid * 10))
		class_matchid=$((class_matchid + 1))
	fi
	
	local p=`echo $port | tr "," " "`; local port=`expand_ports $p`
	local p=`echo $sport | tr "," " "`; local sport=`expand_ports $p`
	local p=`echo $dport | tr "," " "`; local dport=`expand_ports $p`
	
	local proto=`echo $proto | tr "," " "`;
	local ip=`echo $ip | tr "," " "`;
	local src=`echo $src | tr "," " "`;
	local dst=`echo $dst | tr "," " "`;
	local mark=`echo $mark | tr "," " "`;
	local tos=`echo $tos | tr "," " "`;
	
	[ -z "$proto" ]	&& error "Cannot accept empty protocol."		&& return 1
	[ -z "$port" ]	&& error "Cannot accept empty ports."			&& return 1
	[ -z "$sport" ]	&& error "Cannot accept empty source ports."		&& return 1
	[ -z "$dport" ]	&& error "Cannot accept empty destination ports."	&& return 1
	[ -z "$src" ]	&& error "Cannot accept empty source IPs."		&& return 1
	[ -z "$dst" ]	&& error "Cannot accept empty destination IPs."		&& return 1
	[ -z "$ip" ]	&& error "Cannot accept empty IPs."			&& return 1
	[ -z "$tos" ]	&& error "Cannot accept empty TOS."			&& return 1
	[ -z "$mark" ]	&& error "Cannot accept empty MARK."			&& return 1
	
	[ ! "$port" = "any" -a ! "$sport" = "any" ]	&& error "Cannot match 'port' and 'sport'." && exit 1
	[ ! "$port" = "any" -a ! "$dport" = "any" ]	&& error "Cannot match 'port' and 'dport'." && exit 1
	[ ! "$ip" = "any" -a ! "$src" = "any" ]		&& error "Cannot match 'ip' and 'src'." && exit 1
	[ ! "$ip" = "any" -a ! "$dst" = "any" ]		&& error "Cannot match 'ip' and 'dst'." && exit 1
	
	if [ -z "$class" ]
	then
		error "No class name given for match with priority $prio."
		exit 1
	elif [ -z "$flowid" ]
	then
		error "No flowid given for match with priority $prio."
		exit 1
	elif [ ! "$class" = "$class_name" ]
	then
		local c=
		for c in $interface_classes
		do
			local cn="`echo $c | cut -d '|' -f 1`"
			local cf="`echo $c | cut -d '|' -f 2`"
			
			if [ "$class" = "$cn" ]
			then
				local flowid=$cf
				break
			fi
		done
		
		if [ -z "$flowid" ]
		then
			error "Cannot find class '$class'"
			exit 1
		fi
	fi
	
	local parent="$parent_filters_to"
	if [ ! -z "$at" ]
	then
		case "$at" in
			root)
				local parent="$interface_filters_to"
				;;

			*)
				local c=
				for c in $interface_classes
				do
					local cn="`echo $c | cut -d '|' -f 1`"
					local cf="`echo $c | cut -d '|' -f 2`"
					
					if [ "$class" = "$cn" ]
					then
						local parent=$cf
						break
					fi
				done
				
				if [ -z "$parent" ]
				then
					error "Cannot find class '$class'"
					exit 1
				fi
				;;
		esac
	fi
	
	if [ -z "$tcproto" ]
	then
		[ $ipv4 -eq 1 ] && local tcproto="$tcproto ip"
		[ $ipv6 -eq 1 ] && local tcproto="$tcproto ipv6"
	fi
	
	# create all tc filter statements
	for tcproto_arg in $tcproto
	do
		local ipvx=
		[ "$tcproto_arg" = "ipv6" ] && local ipvx="6"
		
		local tproto=
		for tproto in $proto
		do
			local ack_arg=
			local syn_arg=
			local proto_arg=
			case $tproto in
					any)	;;
					
					all)
							local proto_arg="match ip$ipvx protocol 0 0x00"
							;;
					
					ipv6|IPv6)
							local proto_arg="match ip$ipvx protocol 41 0xff"
							;;
							
					icmp|ICMP)
							if [ "$ipvx" = "6" ]
							then
								local proto_arg="match ip$ipvx protocol 58 0xff"
							else
								local proto_arg="match ip$ipvx protocol 1 0xff"
							fi
							;;
							
					tcp|TCP)
							local proto_arg="match ip$ipvx protocol 6 0xff"
							
							# http://www.lartc.org/lartc.html#LARTC.ADV-FILTER
							if [ $ack -eq 1 ]
							then
								if [ "$ipvx" = "6" ]
								then
									local ack_arg="match u8 0x10 0xff at nexthdr+13"
									error "I don't know how to match ACKs in ipv6"
									exit 1
								else
									local ack_arg="match u8 0x05 0x0f at 0 match u16 0x0000 0xffc0 at 2 match u8 0x10 0xff at 33"
								fi
							fi
							
							if [ $syn -eq 1 ]
							then
								if [ "$ipvx" = "6" ]
								then
									# I figured this out, based on the ACK match
									local syn_arg="match u8 0x02 0x02 at nexthdr+13"
									
									error "I don't know how to match SYNs in ipv6"
									exit 1
								else
									# I figured this out, based on the ACK match
									local syn_arg="match u8 0x02 0x02 at 33"
								fi
							fi
							;;
					
					udp|UDP)
							local proto_arg="match ip$ipvx protocol 17 0xff"
							;;
					
					gre|GRE)
							local proto_arg="match ip$ipvx protocol 47 0xff"
							;;
					
					*)		local pid=`cat /etc/protocols | egrep -i "^$tproto[[:space:]]" | tail -n 1 | sed "s/[[:space:]]\+/ /g" | cut -d ' ' -f 2`
							if [ -z "$pid" ]
							then
								error "Cannot find protocol '$tproto' in /etc/protocols."
								return 1
							fi
							local proto_arg="match ip$ipvx protocol $pid 0xff"
							;;
			esac
			
			local tip=
			local mtip=src
			local otherip="dst $ip"
			[ "$ip" = "any" ] && local otherip=
			for tip in $ip $otherip
			do
				[ "$tip" = "dst" ] && local mtip="dst" && continue
				
				local ip_arg=
				case "$tip" in
					any)
						;;
					
					all)
						local ip_arg="match ip$ipvx $mtip 0.0.0.0/0"
						;;
					
					*)	local ip_arg="match ip$ipvx $mtip $tip"
						;;
				esac
				
				local tsrc=
				for tsrc in $src
				do
					local src_arg=
					case "$tsrc" in
						any)	;;
						
						all)
							local src_arg="match ip$ipvx src 0.0.0.0/0"
							;;
						
						*)	local src_arg="match ip$ipvx src $tsrc"
							;;
					esac
					
					local tdst=
					for tdst in $dst
					do
						local dst_arg=
						case "$tdst" in
							any)	;;
							
							all)	local dst_arg="match ip$ipvx dst 0.0.0.0/0"
								;;
								
							*)	local dst_arg="match ip$ipvx dst $tdst"
								;;
						esac
						
						local tport=
						local mtport=sport
						local otherport="dport $port"
						[ "$port" = "any" ] && local otherport=
						for tport in $port $otherport
						do
							[ "$tport" = "dport" ] && local mtport="dport" && continue
							
							local port_arg=
							case "$tport" in
								any)	;;
								
								all)	local port_arg="match ip$ipvx $mtport 0 0x0000"
									;;
								
								*)	local mportmask=`echo $tport | tr "/" " "`
									local port_arg="match ip$ipvx $mtport $mportmask"
									;;
							esac
							
							local tsport=
							for tsport in $sport
							do
								local sport_arg=
								case "$tsport" in
									any)	;;
									
									all)	local sport_arg="match ip$ipvx sport 0 0x0000"
										;;
									
									*)	local mportmask=`echo $tsport | tr "/" " "`
										local sport_arg="match ip$ipvx sport $mportmask"
										;;
								esac
							
								local tdport=
								for tdport in $dport
								do
									local dport_arg=
									case "$tdport" in
										any)	;;
										
										all)	local dport_arg="match ip$ipvx dport 0 0x0000"
											;;
										
										*)	local mportmask=`echo $tdport | tr "/" " "`
											local dport_arg="match ip$ipvx dport $mportmask"
											;;
									esac
								
									local ttos=
									for ttos in $tos
									do
										local tos_arg=
										local tos_value=
										local tos_mask=
										case "$ttos" in
											any)	;;
											
											min-delay|minimize-delay|minimum-delay|low-delay|interactive)
												local tos_value="0x10"
												local tos_mask="0x10"
												;;
												
											maximize-throughput|maximum-throughput|max-throughput|high-throughput|bulk)
												local tos_value="0x08"
												local tos_mask="0x08"
												;;
												
											maximize-reliability|maximum-reliability|max-reliability|reliable)
												local tos_value="0x04"
												local tos_mask="0x04"
												;;
												
											min-cost|minimize-cost|minimum-cost|low-cost|cheap)
												local tos_value="0x02"
												local tos_mask="0x02"
												;;
												
											normal|normal-service)
												local tos_value="0x00"
												local tos_mask="0x1e"
												;;
												
											all)
												local tos_value="0x00"
												local tos_mask="0x00"
												;;
											
											*)
												local tos_value="`echo "$ttos/" | cut -d '/' -f 1`"
												local tos_mask="`echo "$ttos/" | cut -d '/' -f 2`"
												[ -z "$tos_mask" ] && local tos_mask="0xff"
												
												if [ -z "$tos_value" ]
												then
													error "Empty TOS value is not allowed."
													exit 1
												fi
												;;
										esac
										if [ ! -z "$tos_value" -a ! -z "$tos_mask" ]
										then
											if [ "$ipvx" = "6" ]
											then
												local tos_arg="match ip6 priority $tos_value $tos_mask"
											else
												local tos_arg="match ip tos $tos_value $tos_mask"
											fi
										fi
										
										local tmark=
										for tmark in $mark
										do
											local mark_arg=
											case "$tmark" in
												any)	;;
												
												*)	local mark_arg="handle $tmark fw"
													;;
											esac
											
											if [ "$tcproto_arg" = "arp" ]
											then
												local u32="u32 match u32 0 0"
											else
												local u32="u32"
												[ -z "$proto_arg$ip_arg$src_arg$dst_arg$port_arg$sport_arg$dport_arg$tos_arg$ack_arg$syn_arg" ] && local u32=
											fi
											
											[ ! -z "$u32" -a ! -z "$mark_arg" ] && local mark_arg="and $mark_arg"
											
											tc filter add dev $interface_realdev parent $parent protocol $tcproto_arg prio $prio $u32 $proto_arg $ip_arg $src_arg $dst_arg $port_arg $sport_arg $dport_arg $tos_arg $ack_arg $syn_arg $mark_arg $custom flowid $flowid
											
										done # mark
									done # tos
								
								done # dport
							done # sport
						done # port
						
					done # dst
				done # src
			done # ip
			
		done # proto
		
		# increase the counter between tc protocols
		local prio=$((prio + 1))
	done # tcproto (ipv4, ipv6)
	
	return 0
}

clear_everything() {
	local qdisc=
	for qdisc in `cat /proc/net/dev | grep ':' |  cut -d ':' -f 1 | sed "s/ //g" | grep -v "^lo$"`
	do
		# remove existing qdisc from all devices
		tc ignore-error qdisc del dev $qdisc ingress >/dev/null 2>&1
		tc ignore-error qdisc del dev $qdisc root >/dev/null 2>&1
	done
	
	rmmod ifb 2>/dev/null
	
	return 0
}

check_root() {
	if [ ! "${UID}" = 0 ]
	then
		echo >&2
		echo >&2
		echo >&2 "Only user root can run FireQOS."
		echo >&2
		exit 1
	fi
}


show_interfaces() {
	if [ -f $FIREQOS_DIR/interfaces ]
	then
		echo
		echo "The following interfaces are available:"
		cat $FIREQOS_DIR/interfaces
	else
		echo "No interfaces have been configured."
	fi
}

htb_stats() {
	local x=
	
	if [ -z "$1" -o ! -f "${FIREQOS_DIR}/$1.conf" ]
	then
		echo >&2 "There is no interface named '$1' to show."
		show_interfaces
		exit 1
	fi
	
	local banner_every_lines=20
	
	# load the interface configuration
	source "${FIREQOS_DIR}/$1.conf" || exit 1
	
	# pick the right unit for this interface (bit/s, Kbit, Mbit)
	local resolution=1
	[ $((interface_rate * 8)) -gt $((100 * 1000)) ] && local resolution=1000
	[ $((interface_rate * 8)) -gt $((200 * 1000000)) ] && local resolution=1000000
	
	local unit="bits/s"
	[ $resolution = 1000 ] && local unit="Kbit/s"
	[ $resolution = 1000000 ] && local unit="Mbit/s"
	
	# attempt to shrink the list horizontally
	# find how many digits we need
	local maxn="$(( interface_rate * 8 / resolution * 120 / 100))"
	local number_digits=${#maxn}
	local number_digits=$((number_digits + 1))
	[ $number_digits -lt 6 ] && local number_digits=6
	
	# find what number we have to add, to round to closest number
	# instead of round down (the only available in shell).
	local round=0
	if [ ${resolution} -gt 1 ]
	then
		local round=$((resolution / 2))
	fi
	
	getdata() {
		eval "`tc -s class show dev $1 | tr "\n,()" "|   " | sed \
			-e "s/ \+/ /g"			\
			-e "s/ *| */|/g"		\
			-e "s/||/\n/g"			\
			-e "s/|/ /g"			\
			-e "s/\([0-9]\+\)Mbit /\1000000 /g" \
			-e "s/\([0-9]\+\)Kbit /\1000 /g" \
			-e "s/\([0-9]\+\)bit /\1 /g"	\
			-e "s/\([0-9]\+\)pps /\1 /g"	\
			-e "s/\([0-9]\+\)b /\1 /g"	\
			-e "s/\([0-9]\+\)p /\1 /g" 	|\
			tr ":" "_"			|\
			awk '{
				if( $2 == "htb" ) {
					if ( $4 == "root" ) value = $14
					else if ( $6 == "rate" ) value = $15
					else value = $19
					
					print "TCSTATS_" $2 "_" $3 "=\$(( (" value "*8) - OLD_TCSTATS_" $2 "_" $3 "));"
					print "OLD_TCSTATS_" $2 "_" $3 "=\$((" value "*8));"
				}
				else {
					print "# Cannot parse " $2 " class " $3;
					value = 0
				}
			}'`"
	}
	
	getms() {
		local d=`date +'%s.%N'`
		local s=`echo $d | cut -d '.' -f 1`
		local n=`echo $d | cut -d '.' -f 2 | cut -b 1-3`
		echo "${s}${n}"
	}
	
	local startedms=0
	starttime() {
		startedms=`getms`
	}
	
	local endedms=0
	endtime() {
		endedms=`getms`
	}
	
	sleepms() {
		local timetosleep="$1"
	
		local diffms=$((endedms - startedms))
		[ $diffms -gt $timetosleep ] && return 0
	
		local sleepms=$((timetosleep - diffms))
		local secs=$((sleepms / 1000))
		local ms=$((sleepms - (secs * 1000)))
	
		# echo "Sleeping for ${secs}.${ms} (started ${startedms}, ended ${endedms}, diffms ${diffms})"
		sleep "${secs}.${ms}"
	}
	
	echo
	echo "$interface_name: $interface_dev $interface_inout => $interface_realdev, type: $interface_linklayer, overhead: $interface_overhead"
	echo "Rate: $((((interface_rate*8)+round)/resolution))$unit, min: $((((interface_minrate*8)+round)/resolution))$unit, r2q: $interface_r2q"
	echo "Values in $unit"
	echo
	
	getdata $interface_realdev
	
	# render the configuration
	local x=
	for x in $interface_classes_ids
	do
		eval local name="\${class_${x}_name}"
		[ "$name" = "TOTAL" ] && local name="CLASS"
		printf "% ${number_digits}.${number_digits}s " $name
	done
	echo
	
	for x in $interface_classes_ids
	do
		eval local classid="\${class_${x}_classid}"
		printf "% ${number_digits}.${number_digits}s " $classid
	done
	echo
	
	for x in $interface_classes_ids
	do
		eval local priority="\${class_${x}_priority}"
		printf "% ${number_digits}.${number_digits}s " $priority
	done
	echo
	
	for x in $interface_classes_ids
	do
		eval local rate="\${class_${x}_rate}"
		[ ! "${rate}" = "COMMIT" ] && local rate=$(( ((rate * 8) + round) / resolution ))
		printf "% ${number_digits}.${number_digits}s " $rate
	done
	echo
	
	for x in $interface_classes_ids
	do
		eval local ceil="\${class_${x}_ceil}"
		[ ! "${ceil}" = "MAX" ] && local ceil=$(( ((ceil * 8) + round) / resolution ))
		printf "% ${number_digits}.${number_digits}s " $ceil
	done
	echo
	echo
	
	# the main loop
	sleep 1
	starttime
	local c=$((banner_every_lines - 1))
	while [ 1 = 1 ]
	do
		local c=$((c+1))
		getdata $interface_realdev
		
		if [ $c -eq ${banner_every_lines} ]
		then
			echo
			echo "   $interface_name ($interface_dev $interface_inout => $interface_realdev) - values in $unit"
			for x in $interface_classes_ids
			do
				eval local name="\${class_${x}_name}"
				printf "% ${number_digits}.${number_digits}s " $name
			done
			echo
			local c=0
		fi
		
		for x in $interface_classes_ids
		do
			eval "local y=\$TCSTATS_htb_${x}"
			if [ "$y" = "0" ]
			then
				printf "% ${number_digits}.${number_digits}s " "-"
			elif [ "$y" -lt 0 ]
			then
				printf "% ${number_digits}.${number_digits}s " RESET
			else
				printf "% ${number_digits}d " $(( (y+round) / resolution ))
			fi
		done
		echo
		
		endtime
		sleepms 1000
		starttime
	done
}

FIREQOS_MONITOR_DEV=
FIREQOS_MONITOR_HANDLE=
remove_monitor() {
	if [ ! -z "$FIREQOS_MONITOR_DEV" -a ! -z "$FIREQOS_MONITOR_HANDLE" ]
	then
		tc filter del dev $FIREQOS_MONITOR_DEV parent $FIREQOS_MONITOR_HANDLE protocol all prio 1 u32 match u32 0 0 action mirred egress redirect dev ifb0
		ip link set dev ifb0 down
		echo "FireQOS: monitor removed from device '$FIREQOS_MONITOR_DEV', qdisc '$FIREQOS_MONITOR_HANDLE'."
		FIREQOS_MONITOR_DEV=
		FIREQOS_MONITOR_HANDLE=
	fi
	
	echo >&2 "bye..."
	
	[ -f "${FIREQOS_LOCK_FILE}" ] && rm -f "${FIREQOS_LOCK_FILE}" >/dev/null 2>&1
}

add_monitor() {
	FIREQOS_MONITOR_DEV="$1"
	FIREQOS_MONITOR_HANDLE="$2"
	
	check_root
	
	if [ -z "$FIREQOS_MONITOR_DEV" -o -z "$FIREQOS_MONITOR_HANDLE" ]
	then
		echo "Cannot setup monitor on device '$1' for handle '$2'."
		exit 1
	fi
	
	FIREQOS_LOCK_FILE_TIMEOUT=$((86400 * 30))
	fireqos_concurrent_run_lock
	
	ip link set dev ifb0 down >/dev/null 2>&1
	ip link set dev ifb0 up || exit 1
	
	tc filter add dev $FIREQOS_MONITOR_DEV parent $FIREQOS_MONITOR_HANDLE protocol all prio 1 u32 match u32 0 0 action mirred egress redirect dev ifb0
	
	trap remove_monitor EXIT
	trap remove_monitor SIGHUP
	
	echo "FireQOS: monitor added to device '$FIREQOS_MONITOR_DEV', qdisc '$FIREQOS_MONITOR_HANDLE'."
}

monitor() {
	if [ -z "$1" -o ! -f "${FIREQOS_DIR}/$1.conf" ]
	then
		echo >&2 "There is no interface named '$1' to show."
		show_interfaces
		exit 1
	fi
	
	# load the interface configuration
	source "${FIREQOS_DIR}/$1.conf" || exit 1
	
	local x=
	local foundname=
	local foundflow=
	for x in $interface_classes_monitor
	do
		local name=`echo "$x|" | cut -d '|' -f 1`
		local name2=`echo "$x|" | cut -d '|' -f 2`
		local flow=`echo "$x|" | cut -d '|' -f 3`
		local monitor=`echo "$x|" | cut -d '|' -f 4`
		
		if [ "$name" = "$2" -o "$flow" = "$2" -o "$name2" = "$2" -o "$monitor" = "$2" ]
		then
			local foundname="$name"
			local foundname2="$name2"
			local foundflow="$flow"
			local foundmonitor="$monitor"
			break
		fi
	done
	
	if [ -z "$foundname" ]
	then
		echo
		echo "No class found with name '$2' in interface '$1'."
		echo
		echo "Use one of the following names, class ids or qdisc handles:"
		
		local x=
		for x in `echo "$interface_classes_monitor" | tr ' ' '\n' | grep -v "^$"`
		do
			echo "$x" | (
				local name=
				local name2=
				local flow=
				local monitor=
				IFS="|" read name name2 flow monitor
				if [ "$name" = "$name2" -o "$name" = "default" ]
				then
					echo -e "  \e[1;33m $name2 \e[0m or classid \e[1;33m $flow \e[0m or handle \e[1;33m $monitor \e[0m"
				else
					echo -e "  \e[1;33m $name \e[0m or \e[1;33m $name2 \e[0m or classid \e[1;33m $flow \e[0m or handle \e[1;33m $monitor \e[0m"
				fi
			)
		done
		exit 1
	fi
	
	shift 2
	
	echo "Monitoring qdisc '$foundmonitor' for class '$foundname2' ($foundflow)..."
	add_monitor "$interface_realdev" "$foundmonitor" || exit 1
	
	echo
	printf "Running:\n: "
	printf " %q" tcpdump -i ifb0 "${@}"
	echo
	echo
	tcpdump -i ifb0 "${@}"
	
	# add_monitor() adds a trap that will remove the monitor on exit
}

cat <<EOF
FireQOS v1.0 DEVELOPMENT
(C) 2013 Costa Tsaousis, GPL
\$Id$

EOF

show_usage() {
cat <<USAGE

$me start|stop|status <name>

	start	activates traffic shapping rules
		according to rules given in ${FIREQOS_CONFIG}
		
	stop	stops all traffic shapping, on all interfaces
	
	debug	same as 'start', but shows also the generated tc commands
	
	status <name>
		shows live usage for the interface <name>
		the name given mathes the name of an interface statement
		given in the config.

USAGE

}

FIREQOS_MODE=
while [ ! -z "$1" ]
do
	case "$1" in

		stop)	
			clear_everything
			echo "Cleared all QOS on all interfaces."
			syslog info "Cleared all QoS on all interfaces"
			exit 0
			;;
		
		status) 
			shift
			if [ "$2" = "dump" -o "$2" = "tcpdump" ]
			then
				iface="$1"
				shift 2
				monitor $iface "$@"
			else
				htb_stats "$@"
			fi
			exit 0
			;;
		
		dump|tcpdump)
			shift
			monitor "$@"
			exit $?
			;;
		
		debug)	
			FIREQOS_MODE=START
			FIREQOS_DEBUG=1
			;;
		
		start)	
			FIREQOS_MODE=START
			;;
		
		--)
			shift
			break;
			;;
			
		--help|-h)
			FIREQOS_MODE=
			break;
			;;
			
		*)
			echo >&2 "Using file '$1' for FireQOS configuration..."
			FIREQOS_CONFIG="$1"
			;;
	esac
	
	shift
done

if [ -z "$FIREQOS_MODE" ]
then
	show_usage
	exit 1
fi

check_root

# ----------------------------------------------------------------------------
# Normal startup

if [ ! -f "${FIREQOS_CONFIG}" ]
then
	error "Cannot find file '${FIREQOS_CONFIG}'."
	exit 1
fi

if [ ! -d "${FIREQOS_DIR}" ]
then
	mkdir -p "${FIREQOS_DIR}" || exit 1
fi

# make sure we are not running in parallel
fireqos_concurrent_run_lock

# clear all QoS on all interfaces
clear_everything

# remove the existing interfaces list
[ -f $FIREQOS_DIR/interfaces ] && rm $FIREQOS_DIR/interfaces

# enable cleanup in case of failure
FIREQOS_COMPLETED=0
trap fireqos_exit EXIT
trap fireqos_exit SIGHUP

# Run the configuration
enable -n trap					# Disable the trap buildin shell command.
source ${FIREQOS_CONFIG} "$@"			# Run the configuration as a normal script.
if [ $? -ne 0 ]
then
	exit 1
fi
enable trap					# Enable the trap buildin shell command.

interface_close					# close the last interface.

echo
echo "All Done!. Enjoy..."

# inform the trap everything is ok
FIREQOS_COMPLETED=1

exit 0
