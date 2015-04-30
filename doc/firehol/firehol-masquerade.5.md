% firehol-masquerade(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-masquerade - set up masquerading (NAT) on an interface

<!--
contents-table:subcommand:masquerade:keyword-firehol-masquerade:Y:inface outface:Change the source IP of packets leaving `outface`, with the IP of the interface they are using to leave.
contents-table:helper:masquerade:keyword-firehol-masquerade:Y:-:Change the source IP of packets leaving `outface`, with the IP of the interface they are using to leave.
  -->

# SYNOPSIS

masquerade *real-interface* *rule-params*

masquerade [reverse] *rule-params*

# DESCRIPTION


The `masquerade` helper command sets up masquerading on the output of a
real network interface (as opposed to a FireHOL `interface` definition).

If a *real-interface* is specified the command should be used before any
`interface` or `router` definitions. Multiple values can be given separated
by whitespace, so long as they are enclosed in quotes.

If used within an `interface` definition the definition's *real-interface*
will be used.

If used within a router definition the definition's `outface`(s) will be
used, if specified. If the `reverse` option is gived, then the
definition's `inface`(s) will be used, if specified.

Unlike most commands, `masquerade` does not inherit its parent
definition's *rule-params*, it only honours its own. The `inface` and
`outface` parameters should not be used (iptables(8) does not support
inface in the POSTROUTING chain and outface will be overwritten by
FireHOL using the rules above).

> **Note**
>
> The masquerade always applies to the output of the chosen network
> interfaces.
>
> FIREHOL\_NAT will be turned on automatically (see
> [firehol-variables(5)][] ) and FireHOL will
> enable packet-forwarding in the kernel.

# MASQUERADING AND SNAT

Masquerading is a special form of Source NAT (SNAT) that changes the
source of requests when they go out and replaces their original source
when they come in. This way a Linux host can become an Internet router
for a LAN of clients having unroutable IP addresses. Masquerading takes
care to re-map IP addresses and ports as required.

Masquerading is expensive compare to SNAT because it checks the IP
address of the outgoing interface every time for every packet. If your
host has a static IP address you should generally prefer SNAT.

# EXAMPLES

~~~~

 # Before any interface or router
 masquerade eth0 src 192.0.2.0/24 dst not 192.0.2.0/24

 # In an interface definition to masquerade the output of its real-interface
 masquerade

 # In a router definition to masquerade the output of its outface
 masquerade

 # In a router definition to masquerade the output of its inface
 masquerade reverse
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [firehol-nat(5)][] - nat, snat, dnat, redirect config helpers
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
