% firehol-server(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-server - server, route commands: accept requests to a service

<!--
contents-table:subcommand:server:keyword-firehol-server:Y:sport dport:Allow access to a server running on the `interface` or the protected `router` hosts.
  -->

# SYNOPSIS

{ server | server46 } *service* *action* *rule-params*

server4 *service* *action* *rule-params*

server6 *service* *action* *rule-params*

{ route | route46 } *service* *action* *rule-params*

route4 *service* *action* *rule-params*

route6 *service* *action* *rule-params*

<!--
extra-manpage: firehol-server46.5
extra-manpage: firehol-server4.5
extra-manpage: firehol-server6.5
extra-manpage: firehol-route46.5
extra-manpage: firehol-route4.5
extra-manpage: firehol-route6.5
  -->

# DESCRIPTION

The `server` subcommand defines a server of a service on an `interface` or
`router`. Any *rule-params* given to a parent interface or router are
inherited by the server.

For FireHOL a server is the destination of a request. Even though this
is more complex for some multi-socket services, to FireHOL a server
always accepts requests.

The `route` subcommand is an alias for `server` which may only be used
in routers.

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
> Writing `server4` is equivalent to writing `ipv4 server` and ensures
> this subcommand is applied only in the IPv4 firewall rules.
>
> Writing `server6` is equivalent to writing `ipv6 server` and ensures
> this subcommand is applied only in the IPv6 firewall rules.
>
> Writing `server46` is equivalent to writing `both server` and ensures
> this subcommand is applied in both the IPv4 and IPv6 firewall rules;
> it cannot be used as part an interface or router that is IPv4 or IPv6
> only.
>
> The default `server` inherits its behaviour from the enclosing
> interface or router.
>
> The same rules apply to the variations of `route`.


# EXAMPLES

~~~~
server smtp accept

server "smtp pop3" accept

server smtp accept src 192.0.2.1

server smtp accept log "mail packet" src 192.0.2.1
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-modifiers(5)][] - ipv4/ipv6 selection
* [firehol-services(5)][] - services list
* [firehol-actions(5)][] - actions for rules
* [firehol-params(5)][] - optional rule parameters
* [firehol-client(5)][keyword-firehol-client] - client subcommand
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
