% firehol-router(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-router - create a router definition

# SYNOPSIS

{ router | router46 } *name* *rule-params*

router4 *name* *rule-params*

router6 *name* *rule-params*

<!--
extra-manpage: firehol-router46.5
extra-manpage: firehol-router4.5
extra-manpage: firehol-router6.5
  -->

# DESCRIPTION

A `router` definition consists of a set of rules for traffic passing
through the host running the firewall.

The default policy for router definitions is RETURN, meaning packets are
not dropped by any particular router. Packets not matched by any router
are dropped at the end of the firewall.

The behaviour of the defined router is controlled by adding subcommands
from those listed in [ROUTER SUBCOMMANDS][].

> **Note**
>
> Writing `router4` is equivalent to writing `ipv4 router` and ensures
> the defined router is created only in the IPv4 firewall along with any
> rules within it.
>
> Writing `router6` is equivalent to writing `ipv6 router` and ensures
> the defined router is created only in the IPv6 firewall along with any
> rules within it.
>
> Writing `router46` is equivalent to writing `both router` and ensures
> the defined router is created in both the IPv4 and IPv6 firewalls. Any
> rules within it will also be applied to both, unless they specify
> otherwise.


# PARAMETERS


*name*
:   This is a name for this router. You should use short names (10
    characters maximum) without spaces or other symbols.

    A name should be unique for all FireHOL interface and router
    definitions.

*rule-params*
:   The set of rule parameters to further restrict the traffic that is
    matched to this router.

    See [firehol-params(5)][] for information on the
    parameters that can be used. Some examples:

        router mylan inface ppp+ outface eth0 src not ${UNROUTABLE_IPS}

        router myrouter
                  

    See [firehol.conf(5)][] for an explanation
    of \${UNROUTABLE\_IPS}.


# WORKING WITH ROUTERS


Routers create stateful iptables(8) rules which match traffic in both
directions.

To match some client or server traffic, the input/output interface or
source/destination of the request must be specified. All
`inface`/`outface` and `src`/`dst` [firehol-params(5)][]
can be given on the router statement (in which case they will be applied
to all subcommands for the router) or just within the subcommands of the
router.

For example, to define a router which matches requests from any PPP
interface and destined for eth0, and on this allowing HTTP servers (on
eth0) to be accessed by clients (from PPP) and SMTP clients (from eth0)
to access any servers (on PPP):

~~~~

router mylan inface ppp+ outface eth0
  server http accept
  client smtp accept
~~~~

> **Note**
>
> The `client` subcommand reverses any optional rule parameters passed
> to the `router`, in this case the `inface` and `outface`.

Equivalently, to define a router which matches all forwarded traffic and
within the the router allow HTTP servers on eth0 to be accessible to PPP
and any SMTP servers on PPP to be accessible from eth0:

~~~~

router mylan
  server http accept inface ppp+ outface eth0
  server smtp accept inface eth0 outface ppp
~~~~
        

> **Note**
>
> In this instance two `server` subcommands are used since there are no
> parameters on the `router` to reverse. Avoid the use of the `client`
> subcommand in routers unless the inputs and outputs are defined as
> part of the `router`.

Any number of routers can be defined and the traffic they match can
overlap. Since the default policy is RETURN, any traffic that is not
matched by any rules in one will proceed to the next, in order, until
none are left.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [firehol-modifiers(5)][] - ipv4/ipv6 selection
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-iptables(5)][keyword-firehol-iptables] - iptables helper
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)

## Router Subcommands

* [firehol-policy(5)][keyword-firehol-policy] - policy command
* [firehol-protection(5)][keyword-firehol-protection] - protection command
* [firehol-server(5)][keyword-firehol-server] - server, route commands
* [firehol-client(5)][keyword-firehol-client] - client command
* [firehol-group(5)][keyword-firehol-group] - group command
* [firehol-tcpmss(5)][keyword-firehol-tcpmss] - tcpmss helper
