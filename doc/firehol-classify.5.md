% firehol-classify(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-classify - classify traffic for traffic shaping tools

# SYNOPSIS

classify *class* [*rule-params*]

# DESCRIPTION

The `classify` helper command puts matching traffic into the specified
traffic shaping class.

The *class* is a class as used by iptables(8) and tc(8) (e.g. MAJOR:MINOR).

The *rule-params* define a set of rule parameters to match the traffic
that is to be classified. See [firehol-params(5)][] for
more details.

Any classify commands will affect all traffic matched. They must be
declared before the first router or interface.


# EXAMPLES

~~~~

 # Put all smtp traffic leaving via eth1 in class 1:1
 classify 1:1 outface eth1 proto tcp dport 25
~~~~

# SEE ALSO

* [firehol-params(5)][] - optional rule parameters
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* tc(8) - show / manipulate traffic control settings
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
* [Linux Advanced Routing & Traffic Control HOWTO](http://lartc.org/howto/)
