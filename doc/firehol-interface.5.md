% firehol-interface(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-interface - interface definition

# SYNOPSIS

{ interface | interface46 } *real-interface* *name* *rule-params*

interface4 *real-interface* *name* *rule-params*

interface6 *real-interface* *name* *rule-params*

<!--
extra-manpage: firehol-interface46.5
extra-manpage: firehol-interface4.5
extra-manpage: firehol-interface6.5
  -->

# DESCRIPTION


An `interface` definition creates a firewall for protecting the host on
which the firewall is running.

The default policy is DROP, so that if no subcommands are given, the
firewall will just drop all incoming and outgoing traffic using this
interface.

The behaviour of the defined interface is controlled by adding subcommands
from those listed in [INTERFACE SUBCOMMANDS][].

> **Note**
>
> Forwarded traffic is never matched by the `interface` rules, even if
> it was originally destined for the firewall but was redirected using
> NAT. Any traffic to be passed through the firewall for whatever reason
> must be in a `router` (see [firehol-router(5)][keyword-firehol-router]).

> **Note**
>
> Writing `interface4` is equivalent to writing `ipv4 interface` and
> ensures the defined interface is created only in the IPv4 firewall
> along with any rules within it.
>
> Writing `interface6` is equivalent to writing `ipv6 interface` and
> ensures the defined interface is created only in the IPv6 firewall
> along with any rules within it.
>
> Writing `interface46` is equivalent to writing `both interface` and
> ensures the defined interface is created in both the IPv4 and IPv6
> firewalls. Any rules within it will also be applied to both, unless
> they specify otherwise.

# PARAMETERS

*real-interface*
:   This is the interface name as shown by `ip link show`. Generally
    anything iptables(8) accepts is valid.

    The + (plus sign) after some text will match all interfaces that
    start with this text.

    Multiple interfaces may be specified by enclosing them within
    quotes, delimited by spaces for example:

        interface "eth0 eth1 ppp0" myname
                  

*name*
:   This is a name for this interface. You should use short names (10
    characters maximum) without spaces or other symbols.

    A name should be unique for all FireHOL interface and router
    definitions.

*rule-params*
:   The set of rule parameters to further restrict the traffic that is
    matched to this interface.

    See [firehol-params(5)][] for information on the
    parameters that can be used. Some examples:

    ~~~~

    interface eth0 intranet src 192.0.2.0/24

    interface eth0 internet src not "${UNROUTABLE_IPS}"
    ~~~~
                  

    See [firehol.conf(5)][] for an explanation
    of \${UNROUTABLE\_IPS}.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [firehol-modifiers(5)][] - ipv4/ipv6 selection
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-iptables(5)][keyword-firehol-iptables] - iptables helper
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)

## Interface Subcommands

* [firehol-policy(5)][keyword-firehol-policy] - policy command
* [firehol-protection(5)][keyword-firehol-protection] - protection command
* [firehol-server(5)][keyword-firehol-server] - server, route commands
* [firehol-client(5)][keyword-firehol-client] - client command
* [firehol-group(5)][keyword-firehol-group] - group command
