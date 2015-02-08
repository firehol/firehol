% firehol-actions(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-actions - actions for rules

<!--
extra-manpage: firehol-accept.5
extra-manpage: firehol-reject.5
extra-manpage: firehol-drop.5
extra-manpage: firehol-deny.5
extra-manpage: firehol-return.5
extra-manpage: firehol-tarpit.5
-->

# SYNOPSIS

accept

accept with limit *requests/period burst* [overflow *action*]

accept with recent *name* *seconds* *hits*

accept with knock *name*

reject [with *message*]

drop | deny

return

tarpit


# DESCRIPTION

These actions are the actions to be taken on traffic that has been
matched by a particular rule.

FireHOL will also pass through any actions that iptables(8) accepts,
however these definitions provide lowercase versions which accept
arguments where appropriate and which could otherwise not be passed
through.

> **Note**
>
> The iptables(8) LOG action is best used through the optional rule
> parameter `log` since the latter can be combined with one of these
> actions (FireHOL will generate multiple firewall rules to make this
> happen). For more information see [log][keyword-firehol-log]
> and [loglimit][keyword-firehol-log].

The following actions are defined:

## accept

`accept` allows the traffic matching the rules to reach its
destination.

For example, to allow SMTP requests and their replies to flow:

    server smtp accept
                    
## accept with limit *requests/period burst* [overflow *action*]

`accept with limit` allows the traffic, with new connections limited
to *requests/period* with a maximum *burst*. Run
`iptables -m limit --help` for more information.

The default `overflow` *action* is to REJECT the excess connections
(DROP would produce timeouts on otherwise valid service clients).

Examples:

~~~~

server smtp accept with limit 10/sec 100

server smtp accept with limit 10/sec 100 overflow drop
~~~~
                    
## accept with recent *name* *seconds* *hits*

`accept with recent` allows the traffic matching the rules to reach
its destination, limited per remote IP to *hits* per *seconds*. Run
`iptables -m recent --help` for more information.

The *name* parameter is used to allow multiple rules to share the
same table of recent IPs.

For example, to allow only 2 connections every 60 seconds per remote
IP, to the smtp server:

    server smtp accept with recent mail 60 2
                  

> **Note**
>
> When a new connection is not allowed, the traffic will continue to
> be matched by the rest of the firewall. In other words, if the
> traffic is not allowed due to the limitations set here, it is not
> dropped, it is just not matched by this rule.

## accept with knock *name*

`accept with knock` allows easy integration with
[knockd](http://www.zeroflux.org/projects/knock/), a server that allows you
to control access to services by sending certain packets to "knock"
on the door, before the door is opened for service.

The *name* is used to build a special chain knock\_\<`name`\> which
contains rules to allow established connections to work. If knockd
has not allowed new connections any traffic entering this chain will
just return back and continue to match against the other rules until
the end of the firewall.

For example, to allow HTTPS requests based on a knock write:

    server https accept with knock hidden
                    
then configure knockd to enable the HTTPS service with:

    iptables -A knock_hidden -s %IP% -j ACCEPT
                    
and disable it with:

    iptables -D knock_hidden -s %IP% -j ACCEPT
                    
You can use the same knock *name* in more than one FireHOL rule to
enable/disable all the services based on a single knockd
configuration entry.

> **Note**
>
> There is no need to match anything other than the IP in knockd.
> FireHOL already matches everything else needed for its rules to
> work.

## reject

`reject` discards the traffic matching the rules and sends a
rejecting message back to the sender.

## reject with *message*

When used with `with` the specific message to return can be
specified. Run `iptables -j REJECT --help` for a list of the
`--reject-with` values which can be used for *message*. See
[REJECT WITH MESSAGES][] for some examples.

The default (no *message* specified) is to send `tcp-reset` when
dealing with TCP connections and `icmp-port-unreachable` for all
other protocols.

For example:

~~~~

UNMATCHED_INPUT_POLICY="reject with host-prohib"

policy reject with host-unreach

server ident reject with tcp-reset
~~~~
                  

## drop; deny

`drop` discards the traffic matching the rules. It does so silently
and the sender will need to timeout to conclude it cannot reach the
service.

`deny` is a synonym for `drop`. For example, either of these would
silently discard SMTP traffic:

~~~~
server smtp drop

server smtp deny
~~~~
                  

## return

`return` will return the flow of processing to the parent of the
current command.

Currently, the only time `return` can be used meaningfully used is
as a policy for an interface definition. Unmatched traffic will
continue being processed with the possibility of being matched by a
later definition. For example:

    policy return
                  

## tarpit

`tarpit` captures and holds incoming TCP connections open.

Connections are accepted and immediately switched to the persist
state (0 byte window), in which the remote side stops sending data
and asks to continue every 60-240 seconds.

Attempts to close the connection are ignored, forcing the remote
side to time out the connection after 12-24 minutes.

Example:

    server smtp tarpit

> **Note**
>
> As the kernel conntrack modules are always loaded by FireHOL, some
> per-connection resources will be consumed. See this [bug
> report](http://bugs.sanewall.org/sanewall/issues/10) for details.

The following actions also exist but should not be used under normal
circumstances:

## mirror

`mirror` returns the traffic it receives by switching the source and
destination fields. REJECT will be used for traffic generated by the
local host.

> **Warning**
>
> The MIRROR target was removed from the Linux kernel due to its
> security implications.
>
> MIRROR is dangerous; use it with care and only if you understand
> what you are doing.

## redirect; redirect to-port port

`redirect` is used internally by FireHOL helper commands.

Only FireHOL developers should need to use this action directly.


# REJECT WITH MESSAGES

The following RFCs contain information relevant to these messages:

* [RFC 1812](http://www.ietf.org/rfc/rfc1812.txt)
* [RFC 1122](http://www.ietf.org/rfc/rfc1122.txt)
* [RFC 792](http://www.ietf.org/rfc/rfc0792.txt)

icmp-net-unreachable; net-unreach
:   ICMP network unreachable

    Generated by a router if a forwarding path (route) to the
    destination network is not available.

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 792.

    > **Note**
    >
    > Use with care. The sender and the routers between you and the
    > sender may conclude that the whole network your host resides in is
    > unreachable, and prevent other traffic from reaching you.

icmp-host-unreachable; host-unreach
:   ICMP host unreachable

    Generated by a router if a forwarding path (route) to the
    destination host on a directly connected network is not available
    (does not respond to ARP).

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 792.

    > **Note**
    >
    > Use with care. The sender and the routers between you and the
    > sender may conclude that your host is entirely unreachable, and
    > prevent other traffic from reaching you.

icmp-proto-unreachable; proto-unreach
:   ICMP protocol unreachable

    Generated if the transport protocol designated in a datagram is not
    supported in the transport layer of the final destination.

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 792.

icmp-port-unreachable; port-unreach
:   ICMP port unreachable

    Generated if the designated transport protocol (e.g. TCP, UDP, etc.)
    is unable to demultiplex the datagram in the transport layer of the
    final destination but has no protocol mechanism to inform the
    sender.

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 792.

    Generated by hosts to indicate that the required port is not active.

icmp-net-prohibited; net-prohib
:   ICMP communication with destination network administratively
    prohibited

    This code was intended for use by end-to-end encryption devices used
    by U.S. military agencies. Routers SHOULD use the newly defined Code
    13 (Communication Administratively Prohibited) if they
    administratively filter packets.

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 1122.

    > **Note**
    >
    > This message may not be widely understood.

icmp-host-prohibited; host-prohib
:   ICMP communication with destination host administratively prohibited

    This code was intended for use by end-to-end encryption devices used
    by U.S. military agencies. Routers SHOULD use the newly defined Code
    13 (Communication Administratively Prohibited) if they
    administratively filter packets.

    From RFC 1812, section 5.2.7.1. See RFC 1812 and RFC 1122.

    > **Note**
    >
    > This message may not be widely understood.

tcp-reset
:   TCP RST

    The port unreachable message of the TCP stack.

    See RFC 1122.

    > **Note**
    >
    > `tcp-reset` is useful when you want to prevent timeouts on
    > rejected TCP services where the client incorrectly ignores ICMP
    > port unreachable messages.


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
