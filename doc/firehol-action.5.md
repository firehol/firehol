% firehol-action(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-action - set up custom filter actions

# SYNOPSIS

action chain *name* *action*

# DESCRIPTION


The `action` helper command creates an iptables(8) chain which can be used
to control the action of other firewall rules once the firewall is
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

# EXAMPLES

To create a custom chain and have some rules use it:

~~~~
action chain ACT1 accept

interface any world
    server smtp ACT1
    client smtp ACT1
~~~~
        
Once the firewall is running you can dynamically modify the behaviour of
the chain from the Linux command-line, as detailed below:

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

You can also create multiple chains simultaneously. To create 3 ACCEPT
and 3 DROP chains you can do the following:

~~~~
action chain "ACT1 ACT2 ACT3" accept
action chain "ACT4 ACT5 ACT6" drop
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-actions(5)][] - optional rule parameters
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
