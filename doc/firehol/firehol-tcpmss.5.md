% firehol-tcpmss(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-tcpmss - set the MSS of TCP SYN packets for routers

# SYNOPSIS

tcpmss { *mss* | auto } [*if-list*]

# DESCRIPTION

The `tcpmss` helper command sets the MSS (Maximum Segment Size) of TCP
SYN packets routed through the firewall. This can be used to overcome
situations where Path MTU Discovery is not working and packet
fragmentation is not possible.

A numeric *mss* will set MSS of TCP connections to the value given. Using
the word `auto` will set the MSS to the MTU of the outgoing interface
minus 40 (clamp-mss-to-pmtu).

If used within a `router` or `interface` definition the MSS will be applied
to outgoing traffic on the `outface`(s) of the router or interface.

If used before any router or interface definitions it will be applied to
all traffic passing through the firewall. If *if-list* is given, the MSS
will be applied only to those interfaces.

# EXAMPLES

~~~~

tcpmss auto

tcpmss 500

tcpmss 500 "eth1 eth2 eth3"
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
* [TCPMSS target in the iptables tutorial](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html#TCPMSSTARGET)
