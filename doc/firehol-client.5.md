% firehol-client(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-client - client command

# SYNOPSIS

{ client | client46 } *service* *action* [*rule-params*]

client4 *service* *action* [*rule-params*]

client6 *service* *action* [*rule-params*]

<!--
extra-manpage: firehol-client46.5
extra-manpage: firehol-client4.5
extra-manpage: firehol-client6.5
  -->

# DESCRIPTION

The `client` subcommand defines a client of a service on an interface or
router. Any *rule-params* given to a parent interface or router are
inherited by the client, but are reversed.

For FireHOL a client is the source of a request. Even though this is
more complex for some multi-socket services, to FireHOL a client always
initiates the connection.

The *service* parameter is one of the supported service names from
[firehol-services(5)][]. Multiple services may be
specified, space delimited in quotes.

The *action* can be any of the actions listed in
[firehol-actions(5)][].

The *rule-params* define a set of rule parameters to further restrict
the traffic that is matched to this service. See
[firehol-params(5)][] for more details.

> **Note**
>
> Writing `client4` is equivalent to writing `ipv4 client` and ensures
> this subcommand is applied only in the IPv4 firewall rules.
>
> Writing `client6` is equivalent to writing `ipv6 client` and ensures
> this subcommand is applied only in the IPv6 firewall rules.
>
> Writing `client46` is equivalent to writing `both client` and ensures
> this subcommand is applied in both the IPv4 and IPv6 firewall rules;
> it cannot be used as part an interface or router that is IPv4 or IPv6
> only.
>
> The default `client` inherits its behaviour from the enclosing
> interface or router.


# EXAMPLES

~~~~
client smtp accept

client "smtp pop3" accept

client smtp accept src 192.0.2.1

client smtp accept log "mail packet" src 192.0.2.1
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-modifiers(5)][] - ipv4/ipv6 selection
* [firehol-services(5)][] - services list
* [firehol-actions(5)][] - actions for rules
* [firehol-params(5)][] - optional rule parameters
* [firehol-server(5)][keyword-firehol-server] - server subcommand
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
