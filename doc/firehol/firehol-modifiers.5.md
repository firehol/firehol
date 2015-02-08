% firehol-modifiers(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-modifiers - select IPv4 or IPv6 mode
<!--
extra-manpage: firehol-ipv4.5
extra-manpage: firehol-ipv6.5
-->

# SYNOPSIS

ipv4 *definition-or-command* *argument*...

ipv6 *definition-or-command* *argument*...

# DESCRIPTION

Without a modifier, interface and router definitions and commands that
come before either will be applied to both IPv4 and IPV6. Commands
within an `interface` or `router` assume the same behaviour as the enclosing
definition.

When preceded by a modifier, the command or definition can be made to
apply to IPv4 or IPv6 only. Note that you cannot create an IPv4 only
command within and IPv6 interface or vice-versa.

Examples:

~~~~

 interface eth0 myboth src4 192.0.2.0/24 src6 2001:DB8::/24
   ipv4 server http accept
   ipv6 server http accept

 ipv4 interface eth0 my4only src 192.0.2.0/24
   server http accept

 ipv6 interface eth0 my6only src 2001:DB8::/24
   server http accept
~~~~

Many definitions and commands have explicitly named variants (such as
router4, router6, router46) which can be used as shorthand.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-policy(5)][keyword-firehol-policy] - policy command
* [firehol-protection(5)][keyword-firehol-protection] - protection command
* [firehol-server(5)][keyword-firehol-server] - server, route commands
* [firehol-client(5)][keyword-firehol-client] - client command
* [firehol-group(5)][keyword-firehol-group] - group command
* [firehol-iptables(5)][keyword-firehol-iptables] - iptables helper
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
