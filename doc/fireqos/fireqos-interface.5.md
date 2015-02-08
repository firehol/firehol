% fireqos-interface(5) FireQOS Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

fireqos-interface - create an interface definition

# SYNOPSIS

{ interface | interface4 } *device* *name* *direction* [*optional-class-params*] { rate | commit | min } *speed*

interface46 *...*

interface6 *...*

<!--
extra-manpage: fireqos-interface46.5
extra-manpage: fireqos-interface4.5
extra-manpage: fireqos-interface6.5
  -->

# DESCRIPTION


Writing `interface` or `interface4` applies traffic shaping rules only
to IPv4 traffic.

Writing `interface6` applies traffic shaping rules only to IPv6 traffic.

Writing `interface46` applies traffic shaping rules to both IPv4 and
IPv6 traffic.

The actual traffic shaping behaviour of a class is defined by adding
classes. See [fireqos-class(5)][keyword-fireqos-class-definition].

> **Note**
>
> To achieve best results with `incoming` traffic shaping, you should
> not use 100% of the available bandwidth at the interface level.
>
> If you use all there is, at 100% utilisation of the link, the
> neighbour routers will start queuing packets. This will destroy
> prioritisation. Try 85% or 90% instead.


# PARAMETERS


*device*
:   This is the interface name as shown by `ip link show` (e.g. eth0,
    ppp1, etc.)

*name*
:   This is a single-word name for this interface and is used for
    retrieving status information later.

*direction*
:   If set to `input`, traffic coming in to the interface is shaped.

    If set to `output`, traffic going out via the interface is shaped.

*optional-class-params*
:   For a list of optional class parameters which can be applied to an
    interface, see [fireqos-params-class(5)][].

*speed*
:   For an interface, the committed *speed* must be specified with the
    `rate` option. The speed can be expressed in any of the units
    described in [fireqos.conf(5)][].

# EXAMPLES

To create an input policy on eth0, capable of delivering up to 1Gbit of
traffic:

    interface eth0 lan-in input rate 1Gbit

# SEE ALSO

* [fireqos.conf(5)][] - FireQOS configuration file
* [fireqos-class(5)][keyword-fireqos-class-definition] - QOS class definition
* [fireqos-params-class(5)][] - QOS class parameters
* [FireHOL Website](http://firehol.org/)
* [FireQOS Online PDF Manual](http://firehol.org/fireqos-manual.pdf)
* [FireQOS Online Documentation](http://firehol.org/documentation/)
