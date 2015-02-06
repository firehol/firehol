% firehol-iptrap(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-iptrap - dynamically put IP addresses in an ipset

# SYNOPSIS

{ iptrap | iptrap4 | iptrap6 } *type* *ipset* *timeout* [*rule-params*]...


# DESCRIPTION


The `trap` puts the IP addresses of the matching packets to `ipset`. It does
not affect the flow of traffic. It does not `ACCEPT`, `REJECT`, `DROP`
packets or affect the firewall in any way.

Type selects which of the IP addresses of the matching packets will be saved
in the `ipset`. Type can be `src`, `dst`, `src,dst`, `dst,src`.

iptrap will create the `ipset` specified, if that ipset is not already
created by other statements. When the ipset is created by the `iptrap` helper,
the ipset will not be reset (emptied) when the firewall is restarted.

`timeout` is the duration in seconds of the lifetime of each IP
address in the ipset. Every matching packet will refresh this duration
for the IP address in the ipset. The Linux kernel will automatically remove
the IP from the ipset when this time expires. The user may monitor the
remaining time for each IP, by running `ipset list NAME` (where `NAME` is
the `ipset` parameter given in the `iptrap` command).

The *rule-params* define a set of rule parameters to restrict
the traffic that is matched to this service. See
[firehol-params(5)][] for more details.

`iptrap` is hooked on PREROUTING so it is only useful for incoming traffic.

`iptrap` cannot setup both IPv4 and IPv6 traps with one call. The reason
is that the `ipset` can either be IPv4 or IPv6.


# EXAMPLES

~~~~
iptrap4 src trap 3600 inface eth0 proto tcp dport 80 log "TRAPPED HTTP"
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
