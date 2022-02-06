% firehol-protection(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-protection - add extra protections to a definition

<!--
contents-table:subcommand:protection:keyword-firehol-protection:N:*all forbidden*:Examine incoming packets per `interface` or `router` and filter out bad packets or limit request frequency.
  -->

# SYNOPSIS

protection [reverse] strong [*requests/period* [*burst*]]

protection [reverse] *flood-protection-type* [*requests/period* [*burst*]]

protection [reverse] { bad-packets | *packet-protection-type* }

protection [reverse] connlimit *connections* [mask *prefix*]

protection [reverse] connrate *rate* [burst *amount*] [srcmask *prefix*] [htable-size *buckets*] [htable-max *entries*] [htable-expire *msec*] [htable-gcinterval *msec*]


# DESCRIPTION


The `protection` subcommand sets protection rules on an interface or
router.

Flood protections honour the values *requests/period* and *burst*. They
are used to limit the rate of certain types of traffic.

The default rate FireHOL uses is 100 operations per second with a burst
of 50. Run `iptables -m limit --help` for more information.

The protection type `strong` will switch on all protections (both packet
and flood protections) except `all-floods`. It has aliases `full` and
`all`.

The protection type `bad-packets` will switch on all packet protections
but not flood protections.

You can specify multiple protection types by using multiple `protection`
commands or by using a single command and enclosing the types in quotes.

> **Note**
>
> On a router, protections are normally set up on inface.
>
> The `reverse` option will set up the protections on outface. You must
> use it as the first keyword.


# PACKET PROTECTION TYPES

bad-packets:
:   Drops all the bad packets detected by these rules.

invalid
:   Drops all incoming invalid packets, as detected INVALID by the
    connection tracker.

    See also FIREHOL\_DROP\_INVALID in
    [firehol-defaults.conf(5)][] which allows setting this
    function globally.

fragments
:   Drops all packet fragments.

    This rule will probably never match anything since iptables(8)
    reconstructs all packets automatically before the firewall rules are
    processed whenever connection tracking is running.

new-tcp-w/o-syn
:   Drops all TCP packets that initiate a socket but have not got the
    SYN flag set.

malformed-xmas
:   Drops all TCP packets that have all TCP flags set.

malformed-null
:   Drops all TCP packets that have all TCP flags unset.

malformed-bad
:   Drops all TCP packets that have illegal combinations of TCP flags
    set.

## EXAMPLES

~~~~
protection bad-packets
~~~~


# FLOOD PROTECTION TYPES

icmp-floods [*requests/period* [*burst*]]
:   Allows only a certain amount of ICMP echo requests.

syn-floods [*requests/period* [*burst*]]
:   Allows only a certain amount of new TCP connections.

    Be careful to not set the rate too low as the rule is applied to all
    connections regardless of their final result (rejected, dropped,
    established, etc).

all-floods [*requests/period* [*burst*]]
:   Allows only a certain amount of new connections.

    Be careful to not set the rate too low as the rule is applied to all
    connections regardless of their final result (rejected, dropped,
    established, etc).

## EXAMPLES

~~~~
protection all-floods 90/sec 40
~~~~


# CLIENT LIMITING TYPES

These protections were added in v3.

These protections are used to limit the connections client make, per
`interface` or `router`.

They support appending `optional rule parameters` to limit their scope
to certain clients only.

protection [reverse] connlimit *connections* [mask *prefix*]
:   Allow only a number of connections per client (implemented with `connlimit` with fixed type=*saddr*).

protection [reverse] connrate *rate* [burst *amount*] [srcmask *prefix*] [htable-size *buckets*] [htable-max *entries*] [htable-expire *msec*] [htable-gcinterval *msec*]
:   Allow up to a rate of new connections per client (implemented with `hashlimit` with fixed type=*upto* and mode=*srcip*).

## EXAMPLES

Limit the number of concurrent connections to 10 per client

~~~~
protection connlimit 10 mask 32
~~~~

Limit the number of concurrent connections to 100 per client class-C
and also limit it to 5 for 1.2.3.4

~~~~
protection connlimit 100 mask 24
protection connlimit 5 src 1.2.3.4
~~~~

In the last example above, if you want to give client 1.2.3.4 more
connections than all others, you should exclude it from the first
connlimit statement, like this:

~~~~
protection connlimit 100 mask 24 src not 1.2.3.4
protection connlimit 200 src 1.2.3.4
~~~~

Limit all clients to 10 concurrent connections and 60 connections/minute

~~~~
protection connlimit 10
protection connrate 60/minute
~~~~


# KNOWN ISSUES

When using multiple types in a single command, if the quotes are
forgotten, incorrect rules will be generated without warning.

When using multiple types in a single command, FireHOL will silently
ignore any types that come after a group type (`bad-packets`, `strong`
and its aliases). Only use group types on their own line.


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
