% firehol-nat(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-nat - set up NAT and port redirections

<!--
extra-manpage: firehol-dnat.5
extra-manpage: firehol-snat.5
extra-manpage: firehol-redirect.5
-->

# SYNOPSIS 

{ nat to-destination | dnat [to] } *ipaddr*[:*port*] [*rule-params*]

{ nat to-source | snat [to] } *ipaddr*[:*port*] [*rule-params*]

{ nat redirect-to | redirect [to] } *port*[-*range*] [*rule-params*]

# DESCRIPTION

Destination NAT is provided by `nat to-destination` and its synonym `dnat`.

Source NAT is provided by `nat to-source` and its synonym `snat`.

Redirection to a port on the local host is provided by `nat redirect-to`
and its synonym `redirect`.

The *port* part of the new address is optional with SNAT and DNAT; if not
specified it will not be changed.

When you apply NAT to a packet, the Linux kernel will track the changes
it makes, so that when it sees replies the transformation will be
applied in the opposite direction. For instance if you changed the
destination port of a packet from 80 to 8080, when a reply comes back,
its source is set as 80. This means the original sender is not aware
a transformation is happening.

> **Note**
>
> The *rule-params* are used only to determine the traffic that will be
> matched for NAT in these commands, not to permit traffic to flow.
>
> Applying NAT does not automatically create rules to allow the traffic to
> pass. You will still need to include client or server entries in an
> interface or router to allow the traffic.
>
> When using `dnat` or `redirect`, the transformation is in the PREROUTING
> chain of the NAT table and happens before normal rules are matched, so
> your client or server rule should match the "modified" traffic.
>
> When using `snat`, the transformation is in the POSTROUTING chain of the
> NAT table and happens after normal rules are matched, so your client or
> server rule should match the "unmodified" traffic.
>
> See the [netfilter flow diagram][netfilter flow diagram] if you would
> like to see how  network packets are processed by the kernel in detail.

The `nat` helper takes one of the following sub-commands:

to-destination *ipaddr*[:*port*]
:   Defines a Destination NAT (DNAT). Commonly thought of as
    port-forwarding (where packets destined for the firewall with a
    given port and protocol are sent to a different IP address and
    possibly port), DNAT is much more flexible in that any number of
    parameters can be matched before the destination information is
    rewritten.

    *ipaddr*[:*port*] is the destination address to be set in packets
    matching *rule-params*.

    If no rules are given, all forwarded traffic will be matched.
    `outface` should not be used in DNAT since the information is not
    available at the time the decision is made.

    *ipaddr*[:*port*] accepts any `--to-destination` values that
    iptables(8) accepts. Run `iptables -j DNAT --help` for more
    information. Multiple *ipaddr*[:*port*] may be specified by
    separating with spaces and enclosing with quotes.

to-source *ipaddr*[:*port*]
:   Defines a Source NAT (SNAT). SNAT is similar to masquerading but is
    more efficient for static IP addresses. You can use it to give a
    public IP address to a host which does not have one behind the
    firewall. See also [firehol-masquerade(5)][keyword-firehol-masquerade].

    *ipaddr*[:*port*] is the source address to be set in packets
    matching *rule-params*.

    If no rules are given, all forwarded traffic will be matched.
    `inface` should not be used in SNAT since the information is not
    available at the time the decision is made.

    *ipaddr*[:*port*] accepts any `--to-source` values that iptables(8)
    accepts. Run `iptables -j SNAT --help` for more information.
    Multiple *ipaddr*[:*port*] may be specified by separating with spaces
    and enclosing with quotes.

redirect-to *port*[-*range*]
:   Redirect matching traffic to the local machine. This is typically
    useful if you want to intercept some traffic and process it on the
    local machine.

    *port*[-*range*] is the port range (from-to) or single port that packets
    matching *rule-params*  will be redirected to.

    If no rules are given, all forwarded traffic will be matched.
    `outface` should not be used in REDIRECT since the information is
    not available at the time the decision is made.

# EXAMPLES

~~~~

 # Port forwarding HTTP
 dnat to 192.0.2.2 proto tcp dport 80

 # Port forwarding HTTPS on to a different port internally
 dnat to 192.0.2.2:4443 proto tcp dport 443

 # Fix source for traffic leaving the firewall via eth0 with private address
 snat to 198.51.100.1 outface eth0 src 192.168.0.0/24

 # Transparent squid (running on the firewall) for some hosts
 redirect to 8080 inface eth0 src 198.51.100.0/24 proto tcp dport 80

 # Send to 192.0.2.1
 #  - all traffic arriving at or passing through the firewall
 nat to-destination 192.0.2.1

 # Send to 192.0.2.1
 #  - all traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1
 nat to-destination 192.0.2.1 dst 203.0.113.1

 # Send to 192.0.2.1
 #  - TCP traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1
 nat to-destination 192.0.2.1 proto tcp dst 203.0.113.1

 # Send to 192.0.2.1
 #  - TCP traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1, port 25
 nat to-destination 192.0.2.1 proto tcp dport 25 dst 203.0.113.1
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [NAT HOWTO](http://www.netfilter.org/documentation/HOWTO/NAT-HOWTO-6.html)
* [netfilter flow diagram][netfilter flow diagram]

[netfilter flow diagram]: http://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg
