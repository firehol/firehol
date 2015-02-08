% firehol-tosfix(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-tosfix - apply suggested TOS values to packets

# SYNOPSIS

tosfix

# DESCRIPTION

The `tosfix` helper command sets the Type of Service (TOS) field in
packet headers based on the suggestions given by Erik Hensema in
[iptables and tc shaping
tricks](http://www.docum.org/docum.org/faq/cache/49.html).

The following TOS values are set:

-   All TCP ACK packets with length less than 128 bytes are assigned
    Minimize-Delay, while bigger ones are assigned Maximize-Throughput

-   All packets with TOS Minimize-Delay, that are bigger than 512 bytes
    are set to Maximize-Throughput, except for short bursts of 2 packets
    per second

The `tosfix` command must be used before the first router or interface.

# EXAMPLE

~~~~
tosfix
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-tos(5)][keyword-firehol-tos-helper] - tosfix config helper
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
