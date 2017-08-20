% firehol-cthelper(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-cthelper - control connection tracking helpers

<!--
contents-table:helper:cthelper:keyword-firehol-cthelper:4/6:-:Control connection tracking helpers.
extra-manpage: firehol-cthelper46.5
extra-manpage: firehol-cthelper4.5
extra-manpage: firehol-cthelper6.5
  -->

# SYNOPSIS

{ cthelper | cthelper4 | cthelper6 } *protocol helper* *where* [*rule-params*]

# DESCRIPTION


The netfilter team has included in the Linux kernel protocol helpers that
monitor traffic and allow them to work under the connection tracker.

The following protocol helpers have been provided:

- `amanda`
- `ftp`
- `tftp` (cannot be configured)
- `h323` (cannot be configured)
- `irc` (does not support IPv6) 
- `netbios_ns` (cannot be configured)
- `pptp` (does not support IPv6)
- `gre` (cannot be configured)
- `sane`
- `sip`

By default, the helpers will trust either side of the communication.
This is considered a security issue and should be avoided.

Using `cthelper` the helpers that can be configured, can be instructed
to trust a specific side of the communication.

Before doing so, the variable `FIREHOL_CONNTRACK_HELPERS_ASSIGNMENT`
should be set to `manual`.

`where` defines where the trusted traffic is expected. It can be:

- `IN`, `INPUT`, or `PREROUTING` to match incoming packets
- `OUT`, `OUTPUT` to match outgoing packets
- `BOTH`, `BIDIRECTIONAL`, or `INOUT` to match all packets

The *rule-params* define a set of rule parameters to further restrict
the traffic that is matched. See
[firehol-params(5)][] for more details.

`FIREHOL_CONNTRACK_HELPERS_ASSIGNMENT` accepts the following values:

- `kernel` which is the default, allows the kernel to determine by itself which side to trust.

- `firehol` to have FireHOL automatically generate `cthelper` statements keeping `src`, `dst`, `inface` and `outface` from the statements that require each helper. Keep in mind this will only generate valid statements if you don't use NAT at all. `cthelper` statements are executed by iptables before any NAT is applied, while packet filtering is configured after DNAT and before SNAT, resulting in wrong statements when NAT is applied.

- `manual` to use the `cthelper` helper to configure the trusts in `firehol.conf`.

When set to `kernel`, FireHOL will set `net.netfilter.nf_conntrack_helper=1`. In all other cases, FireHOL will set `net.netfilter.nf_conntrack_helper=0`.

# EXAMPLES

~~~~
 # enable manual protocol helpers mode
 FIREHOL_CONNTRACK_HELPERS_ASSIGNMENT="manual"

 # trust SIP packets we send via interface dsl0
 cthelper sip out outface dsl0

 # trust SIP packets we receive from 10.0.0.1 via eth0
 cthelper sip in inface eth0 src 10.0.0.1

 # trust pptp packets we send via interface wan0 (IPv4 only)
 cthelper4 pptp out outface wan0
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
