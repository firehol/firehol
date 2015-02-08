% firehol-dscp(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-dscp - set the DSCP field in the packet header

# SYNOPSIS

dscp { *value* | class *classid* } *chain* *rule-params*

# DESCRIPTION

The `dscp` helper command sets the DSCP field in the header of packets
traffic, to allow QoS shaping.

> **Note**
>
> There is also a `dscp` parameter which allows matching DSCP values
> within individual rules (see [firehol-params(5)][keyword-firehol-dscp-param]).

Set *value* to a decimal or hexadecimal (0xnn) number to set an explicit
DSCP value or use `class` *classid* to use an iptables(8) DiffServ class,
such as EF, BE, CSxx or AFxx (see `iptables -j DSCP --help` for more
information).

The *chain* will be used to find traffic to mark. It can be any of the
iptables(8) built in chains belonging to the `mangle` table. The chain
names are: INPUT, FORWARD, OUTPUT, PREROUTING and POSTROUTING. The names
are case-sensitive.

The *rule-params* define a set of rule parameters to match the traffic
that is to be marked within the chosen chain. See
[firehol-params(5)][] for more details.

Any `dscp` commands will affect all traffic matched. They must be
declared before the first router or interface.

# EXAMPLES

~~~~

 # set DSCP field to 32, packets sent by the local machine
 dscp 32 OUTPUT

 # set DSCP field to 32 (hex 20), packets routed by the local machine
 dscp 0x20 FORWARD

 # set DSCP to DiffServ class EF, packets routed by the local machine
 #              and destined for port TCP/25 of 198.51.100.1
 dscp class EF FORWARD proto tcp dport 25 dst 198.51.100.1
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* ip(8) - show / manipulate routing, devices, policy routing and tunnels
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [Linux Advanced Routing & Traffic Control HOWTO](http://lartc.org/howto/)
