% firehol-mark(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-mark - set a stateful mark from the usermark group

# SYNOPSIS

{ mark | mark46 } *value* *chain* *rule-params*

mark4 *value* *chain* *rule-params*

mark6 *value* *chain* *rule-params*

<!--
contents-table:helper:mark:keyword-firehol-mark-helper:Y:-:Set a stateful mark from the `usermark` group.
extra-manpage: firehol-mark46.5
extra-manpage: firehol-mark4.5
extra-manpage: firehol-mark6.5
  -->

# DESCRIPTION

Marks on packets can be matched by traffic shaping, routing, and
firewall rules for controlling traffic.

> **Note**
> Behaviour changed significantly in FireHOL v3 compared to earlier versions
>
> There is also a `mark` parameter which allows matching marks within
> individual rules (see [firehol-params(5)][keyword-firehol-mark-param]).

FireHOL uses iptables `masks` to break the single 32-bit integer mark
value into smaller groups and allows you to set and match them
independently. The `markdef` group definitions to set this up are
found in `firehol-defaults.conf`

The `mark` helper command sets values within the `usermark` group. You
can set *value* between 0 (no mark) and `size`-1. The default size for
`usermark` is 128, so 127 is highest *value* possible. The default
`usermark` types are `stateful`+`permanent`, meaning the initial
match will only be done on `NEW` packets and the mark will be restored
to all packets in the connection.

The *chain* will be used to find traffic to mark. It can be any of the
iptables(8) built in chains belonging to the `mangle` table. The chain
names are: INPUT, FORWARD, OUTPUT, PREROUTING and POSTROUTING. The names
are case-sensitive.

The *rule-params* define a set of rule parameters to match the traffic
that is to be marked within the chosen chain. See
[firehol-params(5)][] for more details.

Any `mark` commands must be declared before the first router or interface.

> **Note**
>
> If you want to do policy based routing based on iptables(8) marks, you
> will need to disable the Root Path Filtering on the interfaces
> involved (rp\_filter in sysctl).
>
> FireQOS will read the FireHOL mark definitions and set up suitable
> offsets and marks for the various groups. If you are using a different
> tool, you should look at the emitted firewall to determine the final
> masks and values to use.


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
* [firehol-connmark(5)][keyword-firehol-connmark] - set a stateful mark from the connmark group
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* ip(8) - show / manipulate routing, devices, policy routing and tunnels
* [FireHOL Website](http://firehol.org/)
* [Working With Marks Wiki Page](https://github.com/firehol/firehol/wiki/Working-with-MARKs)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [Linux Advanced Routing & Traffic Control HOWTO](http://lartc.org/howto/)
