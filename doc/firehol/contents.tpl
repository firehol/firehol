% FireHOL Reference
% Copyright (c) 2004,2013-2015 Costa Tsaousis <costa@firehol.org>; Copyright (c) 2012-2015 Phil Whineray <phil@firehol.org>
% Version VERSION (Built DATE)

\newpage

<!--
  This file is processed to include inline the individual pages
  single-page HTML and PDF. It is used as-is as a contents page
  for multi-page formats.
  -->

The latest version of this manual is available online as a
[PDF](http://firehol.org/firehol-manual.pdf), as
[single page HTML](http://firehol.org/firehol-manual.html)
and also as
[multiple pages within the website](http://firehol.org/firehol-manual/).

# FireHOL Reference

* [Introduction](introduction.md) <!-- include introduction.md -->

# Setting up and running FireHOL

FireHOL is started and stopped using the [firehol][firehol(1)] script.
The default firewall configuration is to be found in
[/etc/firehol/firehol.conf][firehol.conf(5)], with some behaviours
governed by variables in
[/etc/firehol/firehol-defaults.conf][firehol-variables(5)].

# Primary commands

These are the primary packet filtering building blocks. Below each of
these, sub-commands can be added.

<!-- INSERT TABLE primary -->

# Sub-commands

A rule in an `interface` or `router` definition typically consists of
a subcommand to apply to a [service][firehol-services(5)] using one of
the standard [actions][firehol-actions(5)] provided it matches certain
[optional rule parameters][firehol-params(5)]. e.g.

~~~~{.firehol}
server ssh accept src 10.0.0.0/8
~~~~

The following sub-commands can be used below **primary commands** to form
rules.

<!-- INSERT TABLE subcommand -->

# Helper commands

The following commands are generally used to set things up before the
first **primary command**. Some can be used below an `interface` or
`router` and also appear in the [subcommands](#sub-commands) table.

<!-- INSERT TABLE helper -->


# Manual Pages in Alphabetical Order

* [firehol(1)](firehol.1.md) <!-- include firehol.1.md -->
* [firehol.conf(5)](firehol-conf.5.md) <!-- include firehol-conf.5.md -->
* [firehol-action(5)](firehol-action.5.md) <!-- include firehol-action.5.md -->
* [firehol-actions(5)](firehol-actions.5.md) <!-- include firehol-actions.5.md -->
* [firehol-blacklist(5)](firehol-blacklist.5.md) <!-- include firehol-blacklist.5.md -->
* [firehol-classify(5)](firehol-classify.5.md) <!-- include firehol-classify.5.md -->
* [firehol-client(5)](firehol-client.5.md) <!-- include firehol-client.5.md -->
* [firehol-connmark(5)](firehol-connmark.5.md) <!-- include firehol-connmark.5.md -->
* [firehol-dscp(5)](firehol-dscp.5.md) <!-- include firehol-dscp.5.md -->
* [firehol-group(5)](firehol-group.5.md) <!-- include firehol-group.5.md -->
* [firehol-interface(5)](firehol-interface.5.md) <!-- include firehol-interface.5.md -->
* [firehol-ipset(5)](firehol-ipset.5.md) <!-- include firehol-ipset.5.md -->
* [firehol-iptables(5)](firehol-iptables.5.md) <!-- include firehol-iptables.5.md -->
* [firehol-iptrap(5)](firehol-iptrap.5.md) <!-- include firehol-iptrap.5.md -->
* [firehol-mac(5)](firehol-mac.5.md) <!-- include firehol-mac.5.md -->
* [firehol-mark(5)](firehol-mark.5.md) <!-- include firehol-mark.5.md -->
* [firehol-masquerade(5)](firehol-masquerade.5.md) <!-- include firehol-masquerade.5.md -->
* [firehol-modifiers(5)](firehol-modifiers.5.md) <!-- include firehol-modifiers.5.md -->
* [firehol-nat(5)](firehol-nat.5.md) <!-- include firehol-nat.5.md -->
* [firehol-params(5)](firehol-params.5.md) <!-- include firehol-params.5.md -->
* [firehol-policy(5)](firehol-policy.5.md) <!-- include firehol-policy.5.md -->
* [firehol-protection(5)](firehol-protection.5.md) <!-- include firehol-protection.5.md -->
* [firehol-proxy(5)](firehol-proxy.5.md) <!-- include firehol-proxy.5.md -->
* [firehol-router(5)](firehol-router.5.md) <!-- include firehol-router.5.md -->
* [firehol-server(5)](firehol-server.5.md) <!-- include firehol-server.5.md -->
* [firehol-services(5)](firehol-services.5.md) <!-- include firehol-services.5.md -->
* [firehol-synproxy(5)](firehol-synproxy.5.md) <!-- include firehol-synproxy.5.md -->
* [firehol-tcpmss(5)](firehol-tcpmss.5.md) <!-- include firehol-tcpmss.5.md -->
* [firehol-tos(5)](firehol-tos.5.md) <!-- include firehol-tos.5.md -->
* [firehol-tosfix(5)](firehol-tosfix.5.md) <!-- include firehol-tosfix.5.md -->
* [firehol-variables(5)](firehol-variables.5.md) <!-- include firehol-variables.5.md -->
* [firehol-version(5)](firehol-version.5.md) <!-- include firehol-version.5.md -->
