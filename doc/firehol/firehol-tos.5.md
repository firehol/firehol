% firehol-tos(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-tos - set the Type of Service (TOS) of packets

<!--
contents-table:helper:tos:keyword-firehol-tos-helper:Y:-:Set the Type of Service (TOS) of packets.
  -->

# SYNOPSIS

tos *value* *chain* [*rule-params*]

# DESCRIPTION

The `tos` helper command sets the Type of Service (TOS) field in packet
headers.

> **Note**
>
> There is also a `tos` parameter which allows matching TOS values
> within individual rules (see [firehol-params(5)][keyword-firehol-tos-param]).

The *value* can be an integer number (decimal or hexadecimal) or one of
the descriptive values accepted by iptables(8) (run
`iptables -j TOS --help` for a list).

The *chain* will be used to find traffic to mark. It can be any of the
iptables(8) built in chains belonging to the `mangle` table. The chain
names are: INPUT, FORWARD, OUTPUT, PREROUTING and POSTROUTING. These names
are case-sensitive.

The *rule-params* define a set of rule parameters to match the traffic
that is to be marked within the chosen chain.
See [firehol-params(5)][] for more details.

Any `tos` commands will affect all traffic matched. They must be
declared before the first `router` or `interface`.

# EXAMPLES

~~~~

 # set TOS to 16, packets sent by the local machine
 tos 16 OUTPUT

 # set TOS to 0x10 (16), packets routed by the local machine
 tos 0x10 FORWARD

 # set TOS to Maximize-Throughput (8), packets routed by the local
 #              machine, destined for port TCP/25 of 198.51.100.1
 tos Maximize-Throughput FORWARD proto tcp dport 25 dst 198.51.100.1
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [firehol-tosfix(5)][keyword-firehol-tosfix] - tosfix config helper
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
