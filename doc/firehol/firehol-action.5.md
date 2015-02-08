% firehol-action(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-action - set up custom filtering actions

# SYNOPSIS

action *name* [table *table_name*] *type* *type_params* [ next [ type *type_params* [ next ... ] ] ]

# DESCRIPTION


The `action` helper creates custom actions that can be used everywhere
in FireHOL, like this:

~~~~
action ACT1 chain accept

interface any world
    server smtp ACT1

router myrouter
	policy ACT1
~~~~

The `action` helper allows linking multiple actions together and having
some logic to select which action to execute, like this:

~~~~
action ACT1 \
	     rule src 192.168.0.0/16 action reject \
	next rule dst 192.168.0.0/16 action reject \
	next rule inface eth2 action drop \
	next rule outface eth2 action drop \
	next action accept

interface any world
    server smtp ACT1

router myrouter
	policy ACT1
~~~~

There is no limit on the number of actions that can be linked together.

`type` can be `chain` or `action` (`chain` and `action` are aliases),
`rule` or `ipset`.


## Chain type actions

This is the simpler action. It creates an iptables(8) chain which can be
used to control the action of other firewall rules once the firewall is
running.

For example, you can setup the custom action ACT1, which by default is
ACCEPT, but can be dynamically changed to DROP, REJECT or RETURN (and
back) without restarting the firewall.

The *name* can be any chain name accepted by iptables. You should try to
keep it within 5 and 10 characters.

> **Note**
>
> The *name*s created with this command are case-sensitive.

The *action* can be any of those supported by FireHOL (see
[firehol-actions(5)][]). Only ACCEPT, REJECT, DROP,
RETURN have any meaning in this instance.

Once the firewall is running you can dynamically modify the behaviour of
the chain from the Linux command-line, as detailed below:

~~~~
action ACT1 chain accept

interface any world
    server smtp ACT1
    client smtp ACT1
~~~~

To insert a DROP action at the start of the chain to override the
default action (ACCEPT):

    iptables -t filter -I ACT1 -j DROP

To delete the DROP action from the start of the chain to return to the
default action:

    iptables -t filter -D ACT1 -j DROP

> **Note**
>
> If you delete all of the rules in the chain, the default will be to
> RETURN, in which case the behaviour will be as if any rules with the
> action were not present in the configuration file.


## Rule type actions

`rule` type actions define a few conditions that will lead to an action.

All optional rule parameters FireHOL supports can be used here (see
[firehol-params(5)][]).


~~~~
action ACT1 \
	rule inface eth0 action accept
	next rule outface eth0 action accept
	next action reject

interface any world
    server smtp ACT1
~~~~

In the above example the smtp server can only be accessed from eth0.

It is important to remember that actions will be applied for all the
traffic, both requests and replies. The type of traffic can be filtered
with the `state` optional rule parameter, like this:

~~~~
action ACT1 \
	rule inface eth0 state NEW action reject
	next action accept

interface any world
    server smtp ACT1
    client smtp ACT1
~~~~

In the above example, the smtp server will not accept NEW connections
from eth0, but the smtp client will be able to connect to servers on eth0
(and everywhere else).


## iptrap type actions

`iptrap` (see [firehol-iptrap(5)][]) is a helper than copies (traps)
an IP to an ipset (see [firehol-ipset(5)][]). It does not perform any
action on the traffic.

Using the `iptrap` action, the `iptrap` helper can be linked to filtering
actions, like this:


~~~~
action TRAP_AND_REJECT \
	rule iptrap src policytrap 30 inface wan0 \
		src not "${UNROUTABLE_IPS} ipset:whitelist" \
		state NEW log "POLICY TRAP" \
	next action reject

interface any world
	policy TRAP_AND_REJECT
    server smtp accept
~~~~

Since we used the action TRAP_AND_REJECT as an interface policy, it will
get all the traffic not accepted, rejected, or droped by the server and
client statements.

For all these packets, the action TRAP_AND_REJECT will first check that
they are coming in from wan0, that their src IP is not in `UNROUTABLE_IPS`
list and in the `whitelist` ipset, that they are NEW connections, and if
all these conditions are met, it will log with the tag `POLICY TRAP` and
add the src IP of the packets in the `policytrap` ipset for 30 seconds.

All traffic not matched by the above, will be just rejected.


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-actions(5)][] - optional rule parameters
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
