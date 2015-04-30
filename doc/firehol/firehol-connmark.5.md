% firehol-connmark(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-connmark - set a stateful mark on a connection

<!--
contents-table:helper:connmark:keyword-firehol-connmark:Y:-:Set a stateful mark from the `connmark` group.
  -->

# SYNOPSIS

*Warning - this manual page is out of date for nightly build/v3 behaviour*

{ connmark | connmark46 } { value | save | restore } *chain* *rule-params*

connmark4 { value | save | restore } *chain* *rule-params*

connmark6 { value | save | restore } *chain* *rule-params*

# DESCRIPTION

The `connmark` helper command sets a mark on a whole connection. It
applies to both directions.

> **Note**
>
> To set a mark on packets matching particular rules, regardless of any
> connection, see [firehol-mark(5)][keyword-firehol-mark-helper].

The *value* is the mark value to set (a 32 bit integer). If you specify
`save` then the mark on the matched packet will be turned into a
connmark. If you specify `restore` then the matched packet will have its
mark set to the current connmark.

The *chain* will be used to find traffic to mark. It can be any of the
iptables(8) built in chains belonging to the `mangle` table. The chain
names are: INPUT, FORWARD, OUTPUT, PREROUTING and POSTROUTING. The names
are case-sensitive.

The *rule-params* define a set of rule parameters to match the traffic
that is to be marked within the chosen chain. See
[firehol-params(5)][] for more details.

Any `connmark` commands will affect all traffic matched. They must be
declared before the first router or interface.

# EXAMPLES

Consider a scenario with 3 ethernet ports, where eth0 is on the local
LAN, eth1 connects to ISP 'A' and eth2 to ISP 'B'. To ensure traffic
leaves via the same ISP as it arrives from you can mark the traffic.

~~~~
 # mark connections when they arrive from the ISPs
 connmark 1 PREROUTING inface eth1
 connmark 2 PREROUTING inface eth2

 # restore the mark (from the connmark) when packets arrive from the LAN
 connmark restore OUTPUT
 connmark restore PREROUTING inface eth0
~~~~

It is then possible to use the commands from iproute2 such as ip(8), to
pick the correct routing table based on the mark on the packets.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [firehol-mark(5)][keyword-firehol-mark-helper] - mark traffic for traffic shaping tools
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* ip(8) - show / manipulate routing, devices, policy routing and tunnels
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [Linux Advanced Routing & Traffic Control HOWTO](http://lartc.org/howto/)
