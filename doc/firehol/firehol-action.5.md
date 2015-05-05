% firehol-action(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-action - set up custom filtering actions

# SYNOPSIS

action *name* [table *table_name*] *type* *type_params* [ next [ type *type_params* [ next ... ] ] ]

<!--
contents-table:helper:action:keyword-firehol-action:Y:-:Define new actions that can differentiate the final action based on rules. `action` can be used to define traps.
  -->

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
`rule`, `iptrap`, `ipuntrap` or `sockets_suspects_trap`.


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
 # a simple version of TRAP_AND_REJECT
 # this uses just 2 ipsets, one for counting packets (policytrap)
 # and one to store the banned IPs (trap).
 # it also needs a ipset called whitelist, for excluded source IPs.
 # it will ban IPs when they have 50+ reject packets
 action4 TRAP_AND_REJECT \
	rule iptrap src policytrap 30 inface "${wan}" \
		src not "${UNROUTABLE_IPS} ipset:whitelist" \
		state NEW log "POLICY TRAP" \
    next iptrap trap src 86400 \
        state NEW log "POLICY TRAP - BANNED" \
        ipset policytrap src no-counters packets-above 50 \
	next action reject

 # a complete TRAP_AND_REJECT
 # this uses 3 ipset, one for keeping track of the rejected sockets
 # per source IP (called 'sockets'), one for counting the sockets
 # per source IP (called 'suspects') and one to store the banned IPs
 # (called 'trap').
 # it also needs a ipset called whitelist, for excluded source IPs.
 # it will ban IPs when they have 3 or more rejected sockets
 action4 TRAP_AND_REJECT \
    iptrap sockets src,dst,dst 3600 method hash:ip,port,ip counters \
        state NEW log "TRAP AND REJECT - NEW SOCKET" \
        inface "${wan}" \
        src not "${UNROUTABLE_IPS} ipset:whitelist" \
    next iptrap suspects src 3600 counters \
        state NEW log "TRAP AND REJECT - NEW SUSPECT" \
        ipset sockets src,dst,dst no-counters packets 1 \
    next iptrap trap src 86400 \
        state NEW log "TRAP AND REJECT - BANNED" \
        ipset suspects src no-counters packets-above 2 \
    next action REJECT

 interface any world
	policy TRAP_AND_REJECT
	protection bad-packets
	...

 router wan2lan inface "${wan}" outface "${lan}"
 	policy TRAP_AND_REJECT
 	protection bad-packets
 	...
~~~~

Since we used the action TRAP_AND_REJECT as an interface policy, it will
get all the traffic not accepted, rejected, or dropped by the server and
client statements.

For all these packets, the action TRAP_AND_REJECT will first check that
they are coming in from wan0, that their src IP is not in `UNROUTABLE_IPS`
list and in the `whitelist` ipset, that they are NEW connections, and if
all these conditions are met, it will log with the tag `POLICY TRAP` and
add the src IP of the packets in the `policytrap` ipset for 30 seconds.

All traffic not matched by the above, will be just rejected.

## sockets_suspects_trap type actions

The type `sockets_suspects_trap` will automatically a custom trap using
the following template:

~~~
action4 *name* sockets_suspects_trap *SUSPECTS_TIMEOUT* *TRAP_TIMEOUT* *VALID_CONNECTIONS* [*optional params*] next ...
~~~

This will:

1. Create the ipset `${name}_sockets` where the matched sockets will be stored for `SUSPECTS_TIMEOUT` seconds.
2. Create the ipset `${name}_suspects` where the source IPs of the matched sockets will be stored for `SUSPECTS_TIMEOUT` seconds.
3. Create the ipset `${name}_trap` where the trapped IPs will be stored for `TRAP_TIMEOUT` seconds. IPs will be added to this ipset only if more than `VALID_CONNECTIONS` have been matched by this IP.

`optional params` are FireHOL optional rule parameters ([firehol-params(5)][]) that can be used to limit the match for the first ipset (sockets).

So, to design the same TRAP_AND_REJECT as above, this statement is needed:

~~~
action4 TRAP_AND_REJECT \
    sockets_suspects_trap 3600 86400 2 \
        inface "${wan}" \
        src not "${UNROUTABLE_IPS} ipset:whitelist" \
    next action REJECT
~~~

The ipsets that will be created will be named: `TRAP_AND_REJECT_sockets`, `TRAP_AND_REJECT_suspects` and `TRAP_AND_REJECT_trap`.

> **Note**
> Always terminate `sockets_suspects_trap` with a `next action DROP` or `next action REJECT`, or the traffic will continue to flow.


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-actions(5)][] - optional rule parameters
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
