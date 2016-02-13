#!/bin/bash

# (C) Copyright 2016, Costa Tsaousis
# For FireHOL, a firewall for humans...

# This script can activate any IP list in kernel.
# It can also update existing (in kernel) ipsets.
# The source file can be whatever iprange accepts
# including IPs, CIDRs, ranges, hostnames, etc.

# ipset activation is atomic.
# There is no point at which the system is left
# with the ipset empty or incomplete.
# The new ipset is either applied at once, or
# the old ipset will remain untouched.

# Call this script with just a filename.

ipset="${1}"
file=""
hash=""
tmpname="tmp-$$-${RANDOM}-$(date +%s)"
exists="no"

# ipsets are searched in this path too.
base="/etc/firehol/ipsets"

# Default values for iprange reduce mode
# which optimizes netsets for optimal
# kernel performance.
IPSET_REDUCE_FACTOR=20
IPSET_REDUCE_ENTRIES=65535

if [ -z "${ipset}" -o "${ipset}" = "-h" -o "${ipset}" = "--help" ]
	then
	echo >&2 "This script can load any IPv4 ipset in kernel."
	echo >&2 "Just give an ipset name (or filename) to load."
	echo >&2
	echo >&2 "Files, if not given as absolute pathnames will"
	echo >&2 "be searched in ${base} with .ipset or .netset"
	exit 1
fi

if [ -f "${base}/${ipset}.ipset" ]
	then
	hash="ip"
	file="${base}/${ipset}.ipset"

elif [ -f "${base}/${ipset}.netset" ]
	then
	hash="net"
	file="${base}/${ipset}.netset"

elif [ -f "${ipset}" ]
	then
	if [[ "${ipset}" =~ .*\.ipset ]]
		then
		hash="ip"
		file="${ipset}"
		ipset=$( basename "${ipset}" )
		ipset=${ipset/.ipset/}

	elif [[ "${ipset}" =~ .*\.netset ]]
		then
		hash="net"
		file="${ipset}"
		ipset=$( basename "${ipset}" )
		ipset=${ipset/.netset/}
	
	else
		echo >&2 "I cannot understand if the file ${ipset} is ipset or netset. You should rename it to *.ipset or *.netset"
		exit 1
	fi
else
	echo >&2 "I cannot find the file ${base}/${ipset}.ipset or ${base}/${ipset}.netset"
	exit 1
fi

list_active_ipsets() {
	ipset list -n || ( ipset -L | grep "^Name:" | cut -d: -f 2 )
}

# get all the active ipsets in the system
for x in  $( list_active_ipsets )
do
	if [ "${x}" = "${ipset}" ]
		then
		exists="yes"
		break
	fi
done

# make sure we cleanup properly
FINISHED=0
cleanup() {
	# remove the temporary file
	rm "/tmp/${tmpname}" 2>/dev/null

	# destroy the temporary ipset
	ipset -X "${tmpname}" 2>/dev/null

	# remove our cleanup handler
	trap - EXIT
	trap - SIGHUP

	if [ $FINISHED -eq 0 ]
		then
		echo >&2 "FAILED, sorry!"
		exit 1
	fi

	echo >&2 "OK, all done!"
	exit 0
}
trap cleanup EXIT
trap cleanup SIGHUP

entries=0
ips=$( iprange -C "${file}" )
ips=${ips/*,/}

# create the ipset restore file
if [ "${hash}" = "net" ]
	then
	iprange "${file}" \
		--ipset-reduce ${IPSET_REDUCE_FACTOR} \
		--ipset-reduce-entries ${IPSET_REDUCE_ENTRIES} \
		--print-prefix "-A ${tmpname} " >"/tmp/${tmpname}" || exit 1
	entries=$( wc -l <"/tmp/${tmpname}" )

elif [ "${hash}" = "ip" ]
	then
	iprange -1 "${file}" \
		--print-prefix "-A ${tmpname} " >"/tmp/${tmpname}" || exit 1
	entries=${ips}
fi
echo "COMMIT" >>"/tmp/${tmpname}"

cat <<EOF

ipset     : ${ipset}
hash      : ${hash}
entries   : ${entries}
unique IPs: ${ips}
file      : ${file}
tmpname   : ${tmpname}
exists in kernel already: ${exists}

EOF

opts=
if [ ${entries} -gt 65536 ]
	then
	opts="maxelem ${entries}"
fi

if [ ${exists} = no ]
	then
	echo >&2 "Creating the ${ipset} ipset..."
	ipset -N "${ipset}" ${hash}hash ${opts} || exit 1
fi

echo >&2 "Creating a temporary ipset..."
ipset -N "${tmpname}" ${hash}hash ${opts} || exit 1

echo >&2 "Flushing the temporary ipset..."
ipset -F "${tmpname}" || exit 1

echo >&2 "Loading the temporary ipset with the IPs in file ${file}..."
ipset -R <"/tmp/${tmpname}" || exit 1

echo >&2 "Swapping the temporary ipset with ${ipset}, to activate it..."
ipset -W "${tmpname}" "${ipset}" || exit 1

# let the cleanup handler know we did it
FINISHED=1

exit 0
