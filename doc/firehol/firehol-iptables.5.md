% firehol-iptables(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-iptables - include custom iptables commands
<!--
extra-manpage: firehol-ip6tables.5
contents-table:subcommand:iptables ip6tables:keyword-firehol-iptables:N:*all forbidden*:A wrapper for the system iptables command, to add custom iptables statements to a FireHOL firewall.
contents-table:helper:iptables ip6tables:keyword-firehol-ip6tables:N:*all forbidden*:A wrapper for the system iptables command, to add custom iptables statements to a FireHOL firewall.
  -->

# SYNOPSIS

iptables *argument*...

ip6tables *argument*...

# DESCRIPTION

The `iptables` and `ip6tables` helper commands pass all of their *argument*s
to the real iptables(8) or ip6tables(8) at the appropriate point during
run-time.

> **Note**
>
> When used in an `interface` or `router`, the result will not have a
> direct relationship to the enclosing definition as the parameters
> passed are only those you supply.

You should not use `/sbin/iptables` or `/sbin/ip6tables` directly in a
FireHOL configuration as they will run before FireHOL activates its
firewall. This means that the commands are applied to the previously
running firewall, not the new firewall, and will be lost when the new
firewall is activated.

The `iptables` and `ip6tables` helpers are provided to allow you to hook
in commands safely.

When using the `-t` option to specify a table, ensure this is the first
option to `iptables`, otherwise "fast activation" will fail with an error
message such as:

    iptables-restore: The -t option cannot be used in iptables-restore

# EXAMPLES

Fix LXC DHCP on same host:

~~~~
iptables -t mangle -A POSTROUTING -p udp --dport 68 -j CHECKSUM --checksum-fill
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
