% fireqos-class(5) FireQOS Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

fireqos-class - traffic class definition

# SYNOPSIS

{class|class4|class6|class46} [group] *name* [*optional-class-params*]

{class|class4|class6|class46} group end

<!--
extra-manpage: fireqos-class46.5
extra-manpage: fireqos-class4.5
extra-manpage: fireqos-class6.5
  -->

# DESCRIPTION

There is also an optional `match` parameter called `class`;
see [fireqos-params-match(5)][keyword-fireqos-class-param].

Writing `class` inherits the IPv4/IPv6 version from its enclosing
interface (see [fireqos-interface(5)][]).

Writing `class4` includes only IPv4 traffic in the class.

Writing `class6` includes only IPv6 traffic in the class.

Writing `class46` includes both IPv4 and IPv6 traffic in the class.

The actual traffic to be matched by a class is defined by adding
matches. See [fireqos-match(5)][keyword-fireqos-match].

The sequence that classes appear in the configuration defines their
priority. The first class is the most important one. Unless otherwise
limited it will get all available bandwidth if it needs to.

The second class is less important than the first, the third is even
less important than the second, etc. The idea is very simple: just put
the classes in the order of importance to you.

Classes can have their priority assigned explicitly with the `prio`
parameter. See [fireqos-params-class(5)][keyword-fireqos-prio-class].

> **Note**
>
> The underlying Linux qdisc used by FireQOS, HTB, supports only 8
> priorities, from 0 to 7. If you use more than 8 priorities, all after
> the 8th will get the same priority (`prio` 7).

All classes in FireQOS share the `interface` bandwidth. However, every
class has a *committed* rate (the minimum guaranteed speed it will get
if it needs to) and a *ceiling* (the maximum rate this class can reach,
provided there is capacity available and even if there is spare).

Classes may be nested to any level by using the `class group` syntax.

By default FireQOS creates nested classes as *classes directly attached
to their parent class*. This way, nesting does not add any delays.

FireQOS can also *emulate new hardware* at the `group class` level. This
may be needed, when for example you have an ADSL router that you connect
to via Ethernet: you want the LAN traffic to be at Ethernet speed, but
WAN traffic at ADSL speed with proper ADSL overheads calculation.

To accomplish hardware emulation nesting, you add a `linklayer`
definition (`ethernet`, `adsl`, `atm`, etc.), or just an `mtu` to the
`group class`. FireQOS will create a qdisc within the class, where the
linklayer parameters will be assigned and the child classes will be
attached to this qdisc. This adds some delay to the packets of the child
classes, but allows you to emulate new hardware. For linklayer options,
see [fireqos-params-class(5)][].

There is special class, called `default`. Default classes can be given
explicitly in the configuration file. If they are not found in the
config, FireQOS will append one at the end of each `interface` or
`class group`.


# PARAMETERS


`group`
:   It is possible to nest classes by using a group. Grouped classes
    must be closed with the `class group end` command.
    Class groups can be nested.

*name*
:   This is a single-word name for this class and is used for displaying
    status information.

*optional-class-params*
:   The set of optional class parameters to apply to this class.

    The following optional class parameters are inherited from the
    `interface` the class is in:

    * `ceil`
    * `burst`
    * `cburst`
    * `quantum`
    * `qdisc`

    If you define one of these at the interface level, then all classes
    within the interface will get the value by default. These values can
    be overwritten by defining the parameter on the class too.
    The same inheritance works on class groups.

    Optional class parameters not in the above list are *not* inherited
    from interfaces.

    FireQOS will by default `commit` 1/100th of the parent bandwidth
    to each class. This can be overwritten per class by adding a
    `commit` to the class, or adding a `minrate` at the parent.

# EXAMPLES

To create a nested class, called servers, containing http and smtp:

~~~~
interface eth0 lan input rate 1Gbit
  class voip commit 1Mbit
    match udp ports 5060,10000:10100

  class group servers commit 50%  # define the parent class
    match tcp                     # apply to all child classes

    class mail commit 50%         # 50% of parent ('servers')
      match port 25               # matches within parent ('servers')

    class web commit 50%
      match port 80
  class group end                 # end the group 'servers'

  class streaming commit 30%
~~~~

To create a nested class which emulates an ADSL modem:

~~~~

interface eth0 lan output rate 1Gbit ethernet
  class lan
    match dst 192.168.0.0/24 # LAN traffic

  class group adsl rate 10Mbit ceil 10Mbit adsl remote pppoe-llc
    match all # all non-lan traffic in this emulated hardware group

    class voip # class within adsl
      match udp port 5060

    class web # class within adsl
      match tcp port 80,443
  class group end
~~~~

# SEE ALSO

* [fireqos-params-class(5)][] - QOS class parameters
* [fireqos(1)][] - FireQOS program
* [fireqos.conf(5)][] - FireQOS configuration file
* [fireqos-interface(5)][keyword-fireqos-interface] - QOS interface definition
* [fireqos-match(5)][keyword-fireqos-match] - QOS traffic match
* [FireHOL Website](http://firehol.org/)
* [FireQOS Online PDF Manual](http://firehol.org/fireqos-manual.pdf)
* [FireQOS Online Documentation](http://firehol.org/documentation/)
