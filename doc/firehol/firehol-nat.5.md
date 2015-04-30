% firehol-nat(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-nat - set up NAT and port redirections

<!--
extra-manpage: firehol-dnat.5
extra-manpage: firehol-snat.5
extra-manpage: firehol-redirect.5

contents-table:helper:dnat:keyword-firehol-dnat:Y:-:Change the destination IP or port of packets received, to fixed values or fixed ranges. `dnat` can be used to implement load balancers.
contents-table:helper:snat:keyword-firehol-snat:Y:-:Change the source IP or port of packets leaving, to fixed values or fixed ranges.
contents-table:helper:redirect:keyword-firehol-redirect-helper:Y:-:Redirect packets to the firewall host, possibly changing the destination port. Can support load balancers if multiple daemons run on localhost.
  -->

# SYNOPSIS 

{ nat to-destination | dnat [to] } *ipaddr*[:*port*] [random] [persistent] [at *chain*] [*rule-params*]

{ nat to-source | snat [to] } *ipaddr*[:*port*] [random] [persistent] [at *chain*] [*rule-params*]

{ nat redirect-to | redirect [to] } *port*[-*range*] [random] [at *chain*] [*rule-params*]

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

This means that NAT is only applied on the first packet of each connection
(the nat FireHOL helper always appends `state NEW` to NAT statements).

The NAT helper can be used to setup load balancing. Check the section
BALANCING below.

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

The `at` keyword allows setting a different chain to attach the rules.
For `dnat` and `redirect` the default is PREROUTING, but OUTPUT is also
supported. For `snat` the default is POSTROUTING, but INPUT is also
supported.

`random` will randomize the port mapping involved, to ensure the ports
used are not predictable.

`persistent` will attempt to map to the same source or destination address.

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

# BALANCING

NAT can balance multiple servers (or IPs in case of `snat`) when a range
is specified. This is handled by the kernel.

Example:

~~~
dnat4 to 10.0.0.1-10.0.0.10 persistent proto tcp dst 1.1.1.1 dport 80
~~~

In the above example, the Linux kernel will give a `persistent` server to
all the sockets of any single client.

FireHOL can also setup balancing using a round-robbin or weighted
average distribution of requests. However `persistent` cannot be used
(the Linux kernel applies persistance on a single NAT statement).

## Round Robbin distribution
To enable round robbin distribution, give multiple `to` values, space
separated and enclosed in quotes, or comma separated.

Example:

~~~
 dnat4 to 10.0.0.1,10.0.0.2,10.0.0.3 proto tcp dst 1.1.1.1 port 80
 # or
 dnat4 to "10.0.0.1 10.0.0.2 10.0.0.3" proto tcp dst 1.1.1.1 port 80
~~~

Ports can also be given per IP:

~~~
 dnat4 to 10.0.0.1:70,10.0.0.2:80,10.0.0.3:90 proto tcp dst 1.1.1.1 port 80
 # or
 dnat4 to "10.0.0.1:70 10.0.0.2:80 10.0.0.3:90" proto tcp dst 1.1.1.1 port 80
~~~

## Weighted distribution
To enable weighted distribution, append a slash with the weight requested
for each entry.

FireHOL adds all the weights given and calculates the percentage of traffic
each entry should receive.

Example:

~~~
 dnat4 to 10.0.0.1/30,10.0.0.2/30,10.0.0.3/40 proto tcp dst 1.1.1.1 port 80
 # or
 dnat4 to "10.0.0.1/30 10.0.0.2/30 10.0.0.3/40" proto tcp dst 1.1.1.1 port 80
 # or
 dnat4 to 10.0.0.1:70/30,10.0.0.2:80/30,10.0.0.3:90/40 proto tcp dst 1.1.1.1 port 80
 # or
 dnat4 to "10.0.0.1:70/30 10.0.0.2:80/30 10.0.0.3:90/40" proto tcp dst 1.1.1.1 port 80
~~~


# EXAMPLES

~~~~

 # Port forwarding HTTP
 dnat4 to 192.0.2.2 proto tcp dport 80

 # Port forwarding HTTPS on to a different port internally
 dnat4 to 192.0.2.2:4443 proto tcp dport 443

 # Fix source for traffic leaving the firewall via eth0 with private address
 snat4 to 198.51.100.1 outface eth0 src 192.168.0.0/24

 # Transparent squid (running on the firewall) for some hosts
 redirect4 to 8080 inface eth0 src 198.51.100.0/24 proto tcp dport 80

 # Send to 192.0.2.1
 #  - all traffic arriving at or passing through the firewall
 nat4 to-destination 192.0.2.1

 # Send to 192.0.2.1
 #  - all traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1
 nat4 to-destination 192.0.2.1 dst 203.0.113.1

 # Send to 192.0.2.1
 #  - TCP traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1
 nat4 to-destination 192.0.2.1 proto tcp dst 203.0.113.1

 # Send to 192.0.2.1
 #  - TCP traffic arriving at or passing through the firewall
 #  - which WAS going to 203.0.113.1, port 25
 nat4 to-destination 192.0.2.1 proto tcp dport 25 dst 203.0.113.1
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
