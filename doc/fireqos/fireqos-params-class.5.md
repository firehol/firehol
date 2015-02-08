% fireqos-params-class(5) FireQOS Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

fireqos-params-class - optional class parameters

<!--
extra-manpage: fireqos-class-params.5
extra-manpage: fireqos-rate.5
extra-manpage: fireqos-commit.5
extra-manpage: fireqos-min.5
extra-manpage: fireqos-ceil.5
extra-manpage: fireqos-max.5
extra-manpage: fireqos-minrate.5
extra-manpage: fireqos-qdisc.5
extra-manpage: fireqos-pfifo.5
extra-manpage: fireqos-bfifo.5
extra-manpage: fireqos-sfq.5
extra-manpage: fireqos-fq_codel.5
extra-manpage: fireqos-codel.5
extra-manpage: fireqos-none.5
extra-manpage: fireqos-linklayer.5
extra-manpage: fireqos-ethernet.5
extra-manpage: fireqos-atm.5
extra-manpage: fireqos-adsl.5
extra-manpage: fireqos-mpu.5
extra-manpage: fireqos-mtu.5
extra-manpage: fireqos-tsize.5
extra-manpage: fireqos-overhead.5
extra-manpage: fireqos-r2q.5
extra-manpage: fireqos-burst.5
extra-manpage: fireqos-cburst.5
extra-manpage: fireqos-quantum.5
extra-manpage: fireqos-balanced.5
  -->

# SYNOPSIS

rate | commit | min *speed*

ceil | max *speed*

minrate *speed*

{ qdisc *qdisc-name* | pfifo|bfifo|sfq|fq\_codel|codel|none } [options "*qdisc-options*"]

prio { 0..7 | keep | last }

{ linklayer *linklayer-name* } | { adsl {local|remote} *encapsulation* } | ethernet | atm

mtu *bytes*

mpu *bytes*

tsize *size*

overhead *bytes*

r2q *factor*

burst *bytes*

cburst *bytes*

quantum *bytes*

priority | balanced

# DESCRIPTION

All of the options apply to `interface` and `class` statements.

Units for speeds are defined in [fireqos.conf(5)][].

## rate, commit, min

When a committed rate of *speed* is provided to a class, it means that the
bandwidth will be given to the class when it needs it. If the class does
not need the bandwidth, it will be available for any other class to use.

> For interfaces, a rate must be defined.

> For classes the rate defaults to 1/100 of the interface capacity.

# ceil, max

Defines the maximum *speed* a class can use. Even there is available
bandwidth, a class will not exceed its ceil speed.

For interfaces, the default is the `rate` speed of the interface.

For classes, the defaults is the `ceil` of the their interfaces.

## minrate

Defines the default committed *speed* for all classes not specifically
given a rate in the config file. It forces a recalculation of tc(8) r2q.

When minrate is not given, FireQOS assigns a default value of 1/100
of the interface `rate`.

## qdisc *qdisc-name*, pfifo, bfifo, sfq, fq_codel, codel, none

The qdisc defines the method to distribute class bandwidth to its
sockets. It is applied within the class itself and is useful in
cases where a class gets saturated. For information about these, see
the [Traffic Control Howto](http://www.tldp.org/HOWTO/Traffic-Control-HOWTO/classless-qdiscs.html)

A qdisc is only useful when applied to a class. It can be specified
at the interface level in order to set the default for all of the
included classes.

To pass options to a qdisc, you can specify them through an environment
variable or explicitly on each class.

Set the variable FIREQOS\_DEFAULT\_QDISC\_OPTIONS\_qdiscname in the config
file. For example, for sfq:

    FIREQOS_DEFAULT_QDISC_OPTIONS_sfq="perturb 10 quantum 2000".

Using this variable each sfq will get these options by default. You can
still override this by specifying explicit `options` for individual qdiscs,
for example to add some `sfq` options you would write:

    class classname sfq options "perturb 10 quantum 2000"

The `options` keyword must appear just after the qdisc name.

## prio (class)

> *Note*
>
> There is also a match parameter called `prio`, see
> [fireqos-params-match(5)][keyword-fireqos-prio-match].

HTB supports 8 priorities, from 0 to 7. Any number less than 0 will
give priority 0. Any number above 7 will give priority 7.

By default, FireQOS gives the first class priority 0, and increases
this number by 1 for each class it encounters in the config file. If
there are more than 8 classes, all classes after the 8th will get
priority 7. In `balanced` mode (see [balanced][keyword-fireqos-balanced],
below), all classes will get priority 4 by default.

FireQOS restarts priorities for each interface and class group.

The class priority defines how the spare bandwidth is spread among
the classes. Classes with higher priorities (lower `prio`) will get
all spare bandwidth. Classes with the same priority will get a
percentage of the spare bandwidth, proportional to their committed
rates.

The keywords `keep` and `last` will make a class use the priority of
the class just above / before it. So to make two consecutive classes
have the same prio, just add `prio keep` to the second one.

## linklayer *linklayer-name*, ethernet, atm

The `linklayer` can only be given on interfaces. It is used by the
kernel to calculate the overheads in the packets.

## adsl

`adsl` is a special `linklayer` that automatically calculates ATM
overheads for the link.

`local` is used when the ADSL modem is directly attached to your
computer (for example a PCI card, or a USB modem).

`remote` is used when you have an ADSL router attached to an
ethernet port of your computer.

When one is using PPPoE pass-through, so there is an ethernet ADSL
modem (not router) and PPP is running on the Linux host, the option
to choose is `local`.

> **Note**
>
> This special case has not yet been demonstrated for sure.
> Experiment a bit and if you find out, let us know to update this
> page. In practice, this parameter lets the kernel know that the
> packets it sees, have already an ethernet header on them.

*encapsulation* can be one of (all the labels on the same line are
aliases):

* IPoA-VC/Mux or ipoa-vcmux or ipoa-vc or ipoa-mux,
* IPoA-LLC/SNAP or ipoa-llcsnap or ipoa-llc or ipoa-snap
* Bridged-VC/Mux or bridged-vcmux or bridged-vc or bridged-mux
* Bridged-LLC/SNAP or bridged-llcsnap or bridged-llc or bridged-snap
* PPPoA-VC/Mux or pppoa-vcmux or pppoa-vc or pppoa-mux
* PPPoA-LLC/SNAP or pppoa-llcsnap or pppoa-llc or pppoa-snap
* PPPoE-VC/Mux or pppoe-vcmux or pppoe-vc or pppoe-mux
* PPPoE-LLC/SNAP or pppoe-llcsnap or pppoe-llc or pppoe-snap

If your adsl router can give you the mtu, it would be nice to add an
`mtu` parameter too. For detailed info, see
[here](http://ace-host.stuart.id.au/russell/files/tc/tc-atm/).

## mtu

Defines the MTU of the interface in *bytes*.

FireQOS will query the interface to find its MTU. You can overwrite
this behaviour by giving this parameter to a class or interface.

## mpu

Defines the MPU of the interface in *bytes*.

FireQOS does not set a default value. You can set your own using
this parameter.

## tsize

FireQOS does not set a default *size*. You can set your own using
this parameter.

## overhead

FireQOS automatically calculates the *bytes* `overhead` for ADSL.
For all other technologies, you can specify the overhead in the config file.

## r2q

FireQOS calculates the proper r2q *factor*, so that you can control speeds
in steps of 1/100th of the interface speed (if that is possible).

> **Note**
>
> The HTB manual states that this parameter is ignored when a
> quantum have been set. By default, FireQOS sets quantum to
> interface MTU, so `r2q` is probably is ignored by the kernel.

## burst

`burst` specifies the number of *bytes* that will be sent at once, at ceiling
speed, when a class is allowed to send traffic. It is like a 'traffic unit'.
A class is allowed to send at least `burst` bytes before trying to serve
any other class.

`burst` should never be lower that the interface mtu and class
groups and interfaces should never have a smaller `burst` value than
their children. If you do specify a higher `burst` for a child
class, its parent may get stuck sometimes (the child will drain the
parent).

By default, FireQOS lets the kernel decide this parameter, which
calculates the lowest possible value (the minimum value depends on
the rate of the interface and the clock speed of the CPU).

`burst` is inherited from interfaces to classes and from group
classes to their subclasses. FireQOS will not allow you to set a
`burst` at a subclass, higher than its parent. Setting a `burst` of
a subclass higher than its parent will drain the parent class, which
may be stuck for up to a minute when this happens. For this check to
work, FireQOS uses just its configuration (it does not query the
kernel to check how the value specified in the config file for a
subclass relates to the actual value of its parent).

## cburst

`cburst` is like `burst`, but at hardware speed (not just ceiling speed).

By default, FireQOS lets the kernel decide this parameter.

`cburst` is inherited from interfaces to classes and from group
classes to their subclasses. FireQOS will not allow you to set a
`cburst` at a subclass, higher to its parent. Setting a `cburst` of
a subclass higher than its parent, will drain the parent class,
which may be stuck for up to a minute when this happens. For this
check to work, FireQOS uses just its configuration (it does not
query the kernel to check how the value specified in the config file
for a subclass relates to the actual value of its parent).

## quantum

`quantum` specifies the number of *bytes* a class is allowed to send at once,
when it is borrowing spare bandwidth from other classes.

By default, FireQOS sets `quantum` to the interface mtu.

`quantum` is inherited from interfaces to classes and from group
classes to their subclasses.

## priority, balanced

These parameters set the priority mode of the child classes.

`priority`
:   `priority` is the default mode, where FireQOS assigns an incremental
    priority to each class. In this mode, the first class takes
    `prio 0`, the second `prio 1`, etc. When a class has a higher prio
    than the others (higher = smaller number), this high priority class
    will get all the spare bandwidth available, when it needs it. Spare
    bandwidth will be allocate to lower priority classes only when the
    higher priority ones do not need it.

`balanced`
:   `balanced` mode gives `prio 4` to all child classes. When multiple
    classes have the same `prio`, the spare bandwidth available is
    spread among them, proportionally to their committed rate. The value
    4 can be overwritten by setting FIREQOS\_BALANCED\_PRIO at the top
    of the config file to the `prio` you want the balanced mode to
    assign for all classes.

The priority mode can be set in interfaces and class groups. The
effect is the same. The classes that are defined as child classes,
will get by default the calculated class `prio` based on the priority
mode given.

These options affect only the default `prio` that will be assigned
by FireQOS. The default is used only if you don't explicitly use a
`prio` parameter on a class.

> *Note*
>
> There is also a match parameter called `priority`, see
> [fireqos-params-match(5)][keyword-fireqos-priority-match].

# SEE ALSO

* [fireqos(1)][] - FireQOS program
* [fireqos.conf(5)][] - FireQOS configuration file
* [fireqos-interface(5)][keyword-fireqos-interface] - QOS interface definition
* [fireqos-class(5)][keyword-fireqos-class-definition] - QOS class definition
* [FireHOL Website](http://firehol.org/)
* [FireQOS Online PDF Manual](http://firehol.org/fireqos-manual.pdf)
* [FireQOS Online Documentation](http://firehol.org/documentation/)
