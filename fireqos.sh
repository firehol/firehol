#!/bin/bash

# FireQOS - BETA
# A traffic shapper for humans...
# (C) Copyright 2013, Costa Tsaousis
# GPL
# $Id$

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

# The default and minimum rate for all classes is 1/100
# of the interface bandwidth
FIREQOS_MIN_RATE_DIVISOR=100

# if set to 1, it will print a line per match statement
FIREQOS_SHOW_MATCHES=0

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

firehol_concurrent_run_lock() {
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
		:
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
			local label="Bytes per second"
			local identifier="bps"
			local multiplier=8
			r=$((r * multiplier))
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
	
	eval local base_rate="\$${parent}_rate"
	
	# find all work_X arguments
	while [ ! -z "$1" ]
	do
		case "$1" in
			prio|priority)
					local prio="$2"
					shift 2
					;;
			qdisc)	
					local qdisc="$2"
					shift 2
					;;
			
			sfq|pfifo|bfifo)
					local qdisc="$1"
					shift
					;;
					
			rate|min|commit)
					local rate="`rate2bps $2 $base_rate`"
					shift 2
					;;
					
			ceil|max)
					local ceil="`rate2bps $2 $base_rate`"
					shift 2
					;;
					
			r2q)
					local r2q="$2"
					shift 2
					;;
					
			burst)
					local burst="$2"
					shift 2
					;;
					
			cburst)
					local cburst="$2"
					shift 2
					;;
					
			quantum)
					# must be as small as possible, but larger than mtu
					local quantum="$2"
					shift 2
					;;
					
			mtu)
					local mtu="$2"
					shift 2
					;;
			
			mpu)
					local mpu="$2"
					shift 2
					;;
			
			tsize)
					local tsize="$2"
					shift 2
					;;
			
			overhead)
					local overhead="$2"
					shift 2
					;;
			
			adsl)
					local linklayer="$1"
					local diff=0
					case "$2" in
						local)	local diff=0
								;;
						remote)	local diff=-14
								;;
						*)		error "Unknown adsl option '$2'."
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
								local mtu=1478
								;;
						PPPoA-LLC/SNAP|pppoa-llcsnap|pppoa-llc|pppoa-snap)
								local overhead=$((14 + diff))
								;;
						PPPoE-VC/Mux|pppoe-vcmux|pppoe-vc|pppoe-mux)
								local overhead=$((32 + diff))
								;;
						PPPoE-LLC/SNAP|pppoe-llcsnap|pppoe-llc|pppoe-snap)
								local overhead=$((40 + diff))
								local mtu=1492
								;;
						*)
								error "Cannot understand adsl protocol '$3'."
								return 1
								;;
					esac
					shift 3
					;;
					
			atm|ethernet)
					local linklayer="$1"
					shift
					;;
					
			*)		error "Cannot understand what '${1}' means."
					return 1
					;;
		esac
	done
	
	# export our parameters for the caller
	# for every parameter not set, use the parent value
	# for every one set, use the set value
	for x in ceil burst cburst quantum qdisc
	do
		eval local value="\$$x"
		if [ -z "$value" ]
		then
			eval export ${prefix}_${x}="\${${parent}_${x}}"
		else
			eval export ${prefix}_${x}="\$$x"
		fi
	done
	
	# no inheritance for these parameters
	for x in rate mtu mpu tsize overhead linklayer r2q prio
	do
		eval export ${prefix}_${x}="\$$x"
	done
	
	return 0
}

parent_stack_size=0
parent_push() {
	local prefix="$1"; shift
	local vars="classid major sumrate default_class default_added filters_to name ceil burst cburst quantum qdisc rate mtu mpu tsize overhead linklayer r2q prio"
	
	# refresh the existing parent_* values to stack
	#-- eval "local before=\$parent_stack_${parent_stack_size}"
	#-- echo "BEFORE(${parent_stack_size}): $before"
	eval "parent_stack_${parent_stack_size}="
	for x in $vars
	do
		eval "parent_stack_${parent_stack_size}=\"\${parent_stack_${parent_stack_size}}parent_$x=\$parent_$x;\""
	done
	#-- eval "local after=\$parent_stack_${parent_stack_size}"
	#-- echo "AFTER(${parent_stack_size}): $after"
	
	# now push the new values into the stack
	parent_stack_size=$((parent_stack_size + 1))
	eval "parent_stack_${parent_stack_size}="
	for x in $vars
	do
		eval "parent_$x=\$${prefix}_$x"
		eval "parent_stack_${parent_stack_size}=\"\${parent_stack_${parent_stack_size}}parent_$x=\$${prefix}_$x;\""
	done
	eval "local push=\$parent_stack_${parent_stack_size}"
	#-- echo "PUSH(${parent_stack_size}): $push"
	#-- set | grep ^parent
	
	set_tabs
}

parent_pull() {
	if [ $parent_stack_size -lt 1 ]
	then
		error "Cannot pull a not pushed set of values from stack."
		exit 1
	fi
	
	parent_stack_size=$((parent_stack_size - 1))
	
	#-- eval "local pull=\$parent_stack_${parent_stack_size}"
	#-- echo "PULL(${parent_stack_size}): $pull"
	
	eval "eval \${parent_stack_${parent_stack_size}}"
	
	#-- set | grep ^parent
	
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
interface_sumrate=0
interface_classid=
class_matchid=

ifb_counter=

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
	interface_sumrate=0
	interface_classid=
	class_matchid=1
	parent_stack_size=0
	
	return 0
}

FIREQOS_LOADED_IFBS=0
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
			ifb_counter=0
		else
			ifb_counter=$((ifb_counter + 1))
		fi
		interface_realdev=ifb$ifb_counter
		
		# check if we run out of IFB devices
		if [ $ifb_counter -ge ${FIREQOS_IFBS} ]
		then
			error "You don't have enough IFB devices. Please add FIREQOS_IFBS=XX at the top of your config. Replace XX with a number high enough for the 'input' interfaces you define."
			exit 1
		fi
		
		if [ $FIREQOS_LOADED_IFBS -eq 0 ]
		then
			modprobe ifb numifbs=${FIREQOS_IFBS} || exit 1
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
	
	# check important arguments
	if [ -z "$interface_rate" ]
	then
		error "Cannot figure out the rate of interface '${interface_dev}'."
		return 1
	fi
	
	# fix stab
	# we do this before calculating mtu ourselves
	local stab=
	if [ ! -z "$interface_linklayer" -o ! -z "$interface_overhead" -o ! -z "$interface_mtu" -o ! -z "$interface_mpu" -o ! -z "$interface_overhead" ]
	then
		local stab="stab"
		test ! -z "$interface_mtu"		&& local stab="$stab mtu $interface_mtu"
		test ! -z "$interface_mpu"		&& local stab="$stab mpu $interface_mpu"
		test ! -z "$interface_tsize"		&& local stab="$stab tsize $interface_tsize"
		test ! -z "$interface_overhead"		&& local stab="$stab overhead $interface_overhead"
		test ! -z "$interface_linklayer"	&& local stab="$stab linklayer $interface_linklayer"
	fi
	
	# the default ceiling for the interface, is the rate of the interface
	# if we don't respect this, all unclassified traffic will get just 1kbit!
	[ -z "$interface_ceil" ] && interface_ceil=$interface_rate
	
	[ -z "$interface_mtu" ] && interface_mtu=`device_mtu $interface_realdev`
	[ -z "$interface_mtu" ] && interface_mtu=1500
	
	# set the default qdisc for all classes
	[ -z "$interface_qdisc" ] && interface_qdisc="sfq"
	
	# the desired minimum rate
	interface_minrate=$((interface_rate / FIREQOS_MIN_RATE_DIVISOR))
	
	# calculate the default r2q for this interface
	if [ -z "$interface_r2q" ]
	then
		interface_r2q=`calc_r2q $interface_minrate $interface_mtu`
	fi
	
	# the actual minimum rate we can get
	local r=$((interface_r2q * interface_mtu))
	[ $r -gt $interface_minrate ] && interface_minrate=$r
	
	local rate="rate $((interface_rate * 8 / 1000))kbit"
	local minrate="rate $((interface_minrate * 8 / 1000))kbit"
	[ ! -z "$interface_ceil" ]			&& local ceil="ceil $((interface_ceil * 8 / 1000))kbit"
	[ ! -z "$interface_burst" ]			&& local burst="burst $interface_burst"
	[ ! -z "$interface_cburst" ]			&& local cburst="cburst $interface_cburst"
	[ ! -z "$interface_quantum" ]			&& local quantum="quantum $interface_quantum"
	[ ! -z "$interface_r2q" ]			&& local r2q="r2q $interface_r2q"
	
	echo -e "\e[1;34m real device '$interface_realdev'\e[0m"
	
	# Add root qdisc with proper linklayer and overheads
	tc qdisc add dev $interface_realdev $stab root handle $interface_major: htb default $interface_default_class $r2q
	
	# redirect all incoming traffic to ifb
	if [ $interface_inout = input ]
	then
		# Redirect all incoming traffic to ifbX
		# We then shape the traffic in the output of ifbX
		tc qdisc add dev $interface_dev ingress
		tc filter add dev $interface_dev parent ffff: protocol ip prio 1 u32 match u32 0 0 action mirred egress redirect dev $interface_realdev
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
class_${interface_major}1_name=TOTAL
class_${interface_major}1_priority=PRIORITY
class_${interface_major}1_rate=COMMIT
class_${interface_major}1_ceil=MAX
class_${interface_major}1_burst=BURST
class_${interface_major}1_cburst=CBURST
class_${interface_major}1_quantum=QUANTUM
class_${interface_major}1_qdisc=QDISC
EOF

	return 0
}

class_name=
class_classid=
class_major=
class_group=0

class() {
	# check if the have to push into the stack the last class (if it was a group class)
	if [ $class_group -eq 1 ]
	then
		# the last class was a group 
		
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
			match all class default flowid $interface_major:$parent_default_class prio 0xffff
			
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
	class_classid="$interface_major:$id"
	local ncid="$interface_major$id"
	
	# the handle of the new qdisc we will create
	interface_qdisc_counter=$((interface_qdisc_counter + 1))
	local class_major=$interface_qdisc_counter
	
	parse_class_params class parent "${@}"
	
	# the priority of this class, compared to the others in the same interface
	[ -z "$class_prio" ] && class_prio=$((interface_class_counter - 10))
	
	# if not specified, set the minimum rate
	[ -z "$class_rate" ] && class_rate=$interface_minrate
	
	# class rate cannot go bellow 1/100 of the interface rate
	[ $class_rate -lt $interface_minrate ] && class_rate=$interface_minrate
	
	[ ! -z "$class_rate" ]		&& local rate="rate $((class_rate * 8 / 1000))kbit"
	[ ! -z "$class_ceil" ]		&& local ceil="ceil $((class_ceil * 8 / 1000))kbit"
	[ ! -z "$class_burst" ]		&& local burst="burst $class_burst"
	[ ! -z "$class_cburst" ]	&& local cburst="cburst $class_cburst"
	[ ! -z "$class_quantum" ]	&& local quantum="quantum $class_quantum"
	
	case "$class_qdisc" in
		htb)	local qdisc="htb"
			;;
		
		sfq)	local qdisc="sfq perturb 10"
			;;
		
		*)	local qdisc="$class_qdisc"
			;;
	esac
	
	class_default_class=
	if [ $class_group -eq 1 ]
	then
		class_default_class="$((interface_default_class + interface_qdisc_counter))"
		local qdisc="htb default $class_default_class"
	fi
	
	echo -e "\e[1;34m class $class_classid, priority $class_prio\e[0m"
	
	interface_classes="$interface_classes $class_name|$class_classid"
	parent_sumrate=$((parent_sumrate + $class_rate))
	if [ $parent_sumrate -gt $parent_rate ]
	then
		echo -e ":	\e[1;31mWARNING! The classes under $parent_name commit more bandwidth (+$(( (parent_sumrate - parent_rate) * 8 / 1000 ))kbit) than the available rate.\e[0m"
	fi
	
	tc class add dev $interface_realdev parent $parent_classid classid $class_classid htb $rate $ceil $burst $cburst prio $class_prio $quantum
	tc qdisc add dev $interface_realdev parent $class_classid handle $class_major: $qdisc
	
	# if this is the default, make sure we don't added again
	[ "$class_name" = "default" ] && parent_default_added=1
	
	local name="$class_name"
	[ $parent_stack_size -gt 1 ] && local name="${parent_name:0:2}/$class_name"
	
	class_filters_to="$class_classid"
	
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

expand_port_range() {
	if [ -z "$2" ]
	then
		echo "$1"
		return 0
	fi
	
	local x=
	for x in `seq $1 $2`
	do
		echo $x
	done
	return 0
}

expand_ports() {
	while [ ! -z "$1" ]
	do
		local p=`echo $1 | tr ":-" "  "`
		expand_port_range $p
		shift
	done
	return 0
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
	local flowid=$class_classid
	local ack=0
	local syn=0
	local at=
	
	while [ ! -z "$1" ]
	do
		case "$1" in
			at)
				local at="$2"
				shift 2
				;;
			
			syn|syns)
				local syn=1
				shift
				;;
				
			ack|acks)
				local ack=1
				shift
				;;
				
			tcp|udp|icmp|all)
				local proto="$1"
				shift
				;;
				
			tos)
				local tos="$2"
				shift 2
				;;
				
			mark|marks)
				local mark="$2"
				shift 2
				;;
				
			proto|protocol|protocols)
				local proto="$2"
				shift 2
				;;
			
			port|ports)
				local port="$2"
				shift 2
				;;
			
			sport|sports)
				local sport="$2"
				shift 2
				;;
			
			dport|dports)
				local dport="$2"
				shift 2
				;;
			
			src)
				local src="$2"
				shift 2
				;;
			
			dst)
				local dst="$2"
				shift 2
				;;
			
			prio)
				local prio="$2"
				shift 2
				;;
			
			ip|ips|net|nets|host|hosts)
				local ip="$2"
				shift 2
				;;
			
			class)
				local class="$2"
				shift 2
				;;
			
			flowid)
				local flowid="$2"
				shift 2
				;;
			
			*)	error "Cannot understand what the filter '${1}' is."
				return 1
				;;
		esac
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
	
	# create all tc filter statements
	local tproto=
	for tproto in $proto
	do
		local ack_arg=
		local syn_arg=
		local proto_arg=
		case $tproto in
				any)	;;
				
				all)
						local proto_arg="match ip protocol 0 0x00"
						;;
				
				icmp|ICMP)
						local proto_arg="match ip protocol 1 0xff"
						;;
						
				tcp|TCP)
						local proto_arg="match ip protocol 6 0xff"
						
						# http://www.lartc.org/lartc.html#LARTC.ADV-FILTER
						[ $ack -eq 1 ] && local ack_arg="match u8 0x10 0xff at 33 match u16 0x0000 0xffc0 at 2"
						
						# I figured this out, based on the above - It seems to work
						[ $syn -eq 1 ] && local syn_arg="match u8 0x02 0x02 at 33"
						;;
				
				udp|UDP)
						local proto_arg="match ip protocol 17 0xff"
						;;
				
				gre|GRE)
						local proto_arg="match ip protocol 47 0xff"
						;;
				
				*)		local pid=`cat /etc/protocols | egrep -i "^$tproto[[:space:]]" | tail -n 1 | sed "s/[[:space:]]\+/ /g" | cut -d ' ' -f 2`
						if [ -z "$pid" ]
						then
							error "Cannot find protocol '$tproto' in /etc/protocols."
							return 1
						fi
						local proto_arg="match ip protocol $pid 0xff"
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
					local ip_arg="match ip $mtip 0.0.0.0/0"
					;;
				
				*)	local ip_arg="match ip $mtip $tip"
					;;
			esac
			
			local tsrc=
			for tsrc in $src
			do
				local src_arg=
				case "$tsrc" in
					any)	;;
					
					all)
						local ip_arg="match ip src 0.0.0.0/0"
						;;
					
					*)	local ip_arg="match ip src $tsrc"
						;;
				esac
				
				local tdst=
				for tdst in $dst
				do
					local dst_arg=
					case "$tdst" in
						any)	;;
						
						all)	local ip_arg="match ip dst 0.0.0.0/0"
							;;
							
						*)	local ip_arg="match ip dst $tdst"
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
							
							all)	local port_arg="match ip $mtport 0 0x0000"
								;;
							
							*)	local port_arg="match ip $mtport $tport 0xffff"
								;;
						esac
						
						local tsport=
						for tsport in $sport
						do
							local sport_arg=
							case "$tsport" in
								any)	;;
								
								all)	local ip_arg="match ip sport 0 0x0000"
									;;
								
								*)	local ip_arg="match ip sport $tsport 0xffff"
									;;
							esac
						
							local tdport=
							for tdport in $dport
							do
								local dport_arg=
								case "$tdport" in
									any)	;;
									
									all)	local ip_arg="match ip dport 0 0x0000"
										;;
									
									*)	local ip_arg="match ip dport $tdport 0xffff"
										;;
								esac
							
								local ttos=
								for ttos in $tos
								do
									local tos_arg=
									case "$ttos" in
										any)	;;
										
										all)	local tos_arg="match ip tos 0 0x00"
											;;
										
										*)	local tos_arg="match ip tos $ttos 0xff"
											;;
									esac
									
									local tmark=
									for tmark in $mark
									do
										local mark_arg=
										case "$tmark" in
											any)	;;
											
											*)	local mark_arg="handle $tmark fw"
												;;
										esac
										
										local u32="u32"
										[ -z "$proto_arg$ip_arg$src_arg$dst_arg$port_arg$sport_arg$dport_arg$tos_arg$ack_arg$syn_arg" ] && local u32=
										[ ! -z "$u32" -a ! -z "$mark_arg" ] && local mark_arg="and $mark_arg"
										
										tc filter add dev $interface_realdev parent $parent protocol all prio $prio $u32 $proto_arg $ip_arg $src_arg $dst_arg $port_arg $sport_arg $dport_arg $tos_arg $ack_arg $syn_arg $mark_arg flowid $flowid
										
									done # mark
								done # tos
							
							done # dport
						done # sport
					done # port
					
				done # dst
			done # src
		done # ip
		
	done # proto
	
	return 0
}

clear_everything() {
	local x=
	for x in `cat /proc/net/dev | grep ':' |  cut -d ':' -f 1 | sed "s/ //g" | grep -v "^lo$"`
	do
		# remove existing qdisc from all devices
		tc ignore-error qdisc del dev $x ingress >/dev/null 2>&1
		tc ignore-error qdisc del dev $x root	>/dev/null 2>&1
	done
	
	rmmod ifb 2>/dev/null
	
	return 0
}

htb_stats() {
	if [ -z "$1" -o ! -f "${FIREQOS_DIR}/$1.conf" ]
	then
		error "There is no interface named '$1' to show."
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
	local number_digits=$((number_digits + 2))
	[ $number_digits -lt 7 ] && local number_digits=7
	
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
			sort -n 			|\
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
	for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 3- | sed "s/_//g"`
	do
		eval local name="\${class_${x}_name}"
		[ "$name" = "TOTAL" ] && local name="CLASS"
		printf "% ${number_digits}.${number_digits}s " $name
	done
	echo
	
	for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 3- | sed "s/_//g"`
	do
		eval local priority="\${class_${x}_priority}"
		printf "% ${number_digits}.${number_digits}s " $priority
	done
	echo
	
	for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 3- | sed "s/_//g"`
	do
		eval local rate="\${class_${x}_rate}"
		[ ! "${rate}" = "COMMIT" ] && local rate=$(( ((rate * 8) + round) / resolution ))
		printf "% ${number_digits}.${number_digits}s " $rate
	done
	echo
			
	for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 3- | sed "s/_//g"`
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
			local x=
			for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 3- | sed "s/_//g"`
			do
				eval local name="\${class_${x}_name}"
				printf "% ${number_digits}.${number_digits}s " $name
			done
			echo
			local c=0
		fi
		
		for x in `set | grep ^TCSTATS_ | cut -d '=' -f 1 | cut -d '_' -f 2-`
		do
			eval "y=\$TCSTATS_${x}"
			if [ "$y" = "0" ]
			then
				printf "% ${number_digits}.${number_digits}s " "-"
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

case "$1" in

	stop)	clear_everything
		echo "Cleared all QOS on all interfaces."
		syslog info "Cleared all QoS on all interfaces"
		exit 0
		;;
	
	status) shift
		htb_stats "$@"
		;;
	
	debug)	FIREQOS_DEBUG=1
		;;
	
	start)	;;
	
	*)	show_usage
		exit 1
		;;
esac


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
firehol_concurrent_run_lock

# clear all QoS on all interfaces
clear_everything

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
