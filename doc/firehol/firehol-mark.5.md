% firehol-mark(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-mark - mark traffic for traffic shaping tools

# SYNOPSIS

mark *value* *chain* *rule-params*

# DESCRIPTION

The `mark` helper command sets a mark on packets that can be matched by
traffic shaping tools for controlling the traffic.

> **Note**
>
> To set a mark on whole connections, see
> [firehol-connmark(5)][keyword-firehol-connmark]. There is also a `mark`
> parameter which allows matching marks within individual rules (see 
> [firehol-params(5)][keyword-firehol-mark-param]).

The *value* is the mark value to set (a 32 bit integer).

The *chain* will be used to find traffic to mark. It can be any of the
iptables(8) built in chains belonging to the `mangle` table. The chain
names are: INPUT, FORWARD, OUTPUT, PREROUTING and POSTROUTING. The names
are case-sensitive.

The *rule-params* define a set of rule parameters to match the traffic
that is to be marked within the chosen chain. See
[firehol-params(5)][] for more details.

Any `mark` commands will affect all traffic matched. They must be
declared before the first router or interface.

> **Note**
>
> If you want to do policy based routing based on iptables(8) marks, you
> will need to disable the Root Path Filtering on the interfaces
> involved (rp\_filter in sysctl).


# EXAMPLES

~~~~
 # mark with 1, packets sent by the local machine
 mark 1 OUTPUT

 # mark with 2, packets routed by the local machine
 mark 2 FORWARD

 # mark with 3, packets routed by the local machine, sent from
 #              192.0.2.2 destined for port TCP/25 of 198.51.100.1
 mark 3 FORWARD proto tcp dport 25 dst 198.51.100.1 src 192.0.2.2
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [firehol-connmark(5)][keyword-firehol-connmark] - set a stateful mark on a connection
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* ip(8) - show / manipulate routing, devices, policy routing and tunnels
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [Linux Advanced Routing & Traffic Control HOWTO](http://lartc.org/howto/)
