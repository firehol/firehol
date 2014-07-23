% firehol-policy(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-policy - set default action for an interface or router

# SYNOPSIS

policy *action*

# DESCRIPTION

The `policy` subcommand defines the default policy for an interface or
router.

The *action* can be any of the actions listed in
[firehol-actions(5)][].

> **Note**
>
> Change the default policy of a router only if you understand clearly
> what will be matched by the router statement whose policy is being
> changed.
>
> It is common to define overlapping router definitions. Changing the
> policy to anything other than the default `return` may cause strange
> results for your configuration.

> **Warning**
>
> Do not set a policy to `accept` unless you fully trust all hosts that
> can reach the interface. FireHOL CANNOT be used to create valid "accept by
> default" firewalls.

# EXAMPLE

~~~~

interface eth0 intranet src 192.0.2.0/24
  # I trust this interface absolutely
  policy accept
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
