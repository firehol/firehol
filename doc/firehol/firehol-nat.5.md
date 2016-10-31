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

{ nat to-destination | dnat [to] } *ipaddr*[:*port*] [random] [persistent] [id *id*] [at *chain*] [*rule-params*]

{ nat to-source | snat [to] } *ipaddr*[:*port*] [random] [persistent] [id *id*] [at *chain*] [*rule-params*]

{ nat redirect-to | redirect [to] } *port*[-*range*] [random] [id *id*] [at *chain*] [*rule-params*]

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

`random` will randomise the port mapping involved, to ensure the ports
used are not predictable.

`persistent` is used when the statement is given alternatives (i.e.
many destination servers for `dnat`, many source IPs for `snat`, many
ports for `redirect`). It will attempt to keep each client on the same
nat map. See below for more information about persistence.

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

FireHOL can also setup balancing using a round-robin or weighted
average distribution of requests. However `persistent` cannot be used
(the Linux kernel applies persistence on a single NAT statement).

## Round Robin distribution
To enable round robin distribution, give multiple `to` values, space
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

## PERSISTENCE

The kernel supports persistence only if the NAT alternatives are
contiguous (i.e. dnat to A-B, snat to A-B, redirect to 1000:1010, etc).
If they are contiguous, persistence is left at the kernel. FireHOL does
nothing.

If the alternatives are not contiguous, FireHOL will use the *recent*
iptables module to apply persistence itself.

FireHOL supports mixed mode persistence. For example, you can have
something like this:

~~~~~
dnat to A-B/70,C-D/20,F/10 persistence id mybalancer
~~~~~

The above is a weighted distribution of persistence. Group A-B will get
70%, C-D 20% and server F 10%.

Using the above, FireHOL will apply its persistence to pick one of
the groups A-B, or C-D, or F. Once the group has been picked by
FireHOL, the kernel will apply persistence within the group, to pick
the server that will handle the request.

The FireHOL persistence works like this:

1. A packet is received that should be NATed
2. A lookup is made using the *recent* module to find if it has been seen
   before. The source IP of packet is looked up.
3. If it has been seen before, the connection is mapped the same way the
   last time was mapped. The *recent* module is updated too.
4. If it has not been seen before, the connection is mapped using the
   distribution method specified. The *recent* module is updated too,
   to be ready for the next connection.

The *recent* module has a few limitations:

1. It has lookup tables. We need one lookup table for each member of
   of the NAT. FireHOL uses the `id` parameter and the definition of
   each alternative in the NAT statement to form a name for the
   lookup table. These lookup tables are persistent to firewall
   restarts, this is why FireHOL requires from you to set an `id`.

2. It can keep entries in its lookup tables for a given time.
   FireHOL sets this to 3600 seconds.
   You can control it by setting `FIREHOL_NAT_PERSISTENCE_SECONDS`.

3. It has a limit on the number of entries in the lookup tables.
   FireHOL cannot set this. This is kernel module option.
   The default is 200 entries.

   Check this:

   ~~~~
    # modinfo xt_recent
    filename:       /lib/modules/4.1.12-gentoo/kernel/net/netfilter/xt_recent.ko
    alias:          ip6t_recent
    alias:          ipt_recent
    license:        GPL
    description:    Xtables: "recently-seen" host matching
    author:         Jan Engelhardt <jengelh@medozas.de>
    author:         Patrick McHardy <kaber@trash.net>
    depends:        x_tables
    intree:         Y
    vermagic:       4.1.12-gentoo SMP preempt mod_unload modversions
    parm:           ip_list_tot:number of IPs to remember per list (uint)
    parm:           ip_list_hash_size:size of hash table used to look up IPs (uint)
    parm:           ip_list_perms:permissions on /proc/net/xt_recent/* files (uint)
    parm:           ip_list_uid:default owner of /proc/net/xt_recent/* files (uint)
    parm:           ip_list_gid:default owning group of /proc/net/xt_recent/* files (uint)
    parm:           ip_pkt_list_tot:number of packets per IP address to remember (max. 255) (uint)
    ~~~~

    You have to consult your distribution documentation to set these.
    You can find their current values by examining files found in
    `/sys/module/xt_recent/parameters/` Unfortunately, these files
    are not writable, so to change parameters you have unload and
    reload the module (i.e. apply a firewall that does not use the
    *recent* module, `rmmod xt_recent`, change the parameter,
    re-apply a firewall that uses the *recent* module).

    Normaly, you will need a line in `/etc/modprobe.d/netfitler.conf`
    like this:

    ~~~~
    options xt_recent ip_list_tot=16384
    ~~~~

    The number 16384 I used is the max number of unique client IPs
    I expect to have per hour (`FIREHOL_NAT_PERSISTENCE_SECONDS`)
    for this service.

    `ip_list_hash_size` is calculated by kernel when the module
    is loaded to be bigger and up to twice `ip_list_tot`.

Once you have the balancer running, you can find its lookup tables in
`/proc/net/xt_recent/`. There you will find files starting with the
*id* parameter, one file for every alternative of the NAT rule.


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
