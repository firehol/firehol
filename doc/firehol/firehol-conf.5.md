% firehol.conf(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol.conf - FireHOL configuration

<!--
extra-manpage: firehol.conf.5
  -->

# DESCRIPTION


`/etc/firehol/firehol.conf` is the default configuration file for
[firehol(1)][]. It defines the stateful firewall that will
be produced.

A configuration file starts with an optional version indicator which
looks like this:

    version 6

See [firehol-version(1)][keyword-firehol-version] for full details.

A configuration file contains one or more `interface` definitions, which
look like this:

~~~~
 interface eth0 lan
   client all accept # This host can access any remote service
   server ssh accept # Remote hosts can access SSH on local server
   # ...
~~~~
        

The above definition has name "lan" and specifies a network interface
(eth0). A definition may contain zero or more subcommands. See
[firehol-interface(5)][keyword-firehol-interface] for full details.

By default FireHOL will try to create both IPv4 and IPv6 rules for each
interface. To make this explicit or restrict which rules are created
write `both interface`, `ipv4 interface` or `ipv6 interface`.

Note that IPv6 will be disabled silently if your system is not configured
to use it. You can test this by looking for the file `/proc/net/if_inet6`. The
[IPv6 HOWTO](http://www.tldp.org/HOWTO/Linux+IPv6-HOWTO/systemcheck-kernel.html)
has more information.

A configuration file contains zero or more `router` definitions, which
look like this:

~~~~
DMZ_IF=eth0
WAN_IF=eth1
router wan2dmz inface ${WAN_IF} outface ${DMZ_IF}
  route http accept  # Hosts on WAN may access HTTP on hosts in DMZ
  server ssh accept  # Hosts on WAN may access SSH on hosts in DMZ
  client pop3 accept # Hosts in DMZ may access POP3 on hosts on WAN
  # ...
~~~~
        

The above definition has name "wan2dmz" and specifies incoming and
outgoing network interfaces (eth1 and eth0) using variables. A
definition may contain zero or more subcommands. Note that a router is
not required to specify network interfaces to operate on. See
[firehol-router(5)][keyword-firehol-router] for full details.

By default FireHOL will try to create both IPv4 and IPv6 rules for each
router. To make this explicit or restrict which rules are created
write `both router`, `ipv4 router` or `ipv6 router`.

It is simple to add extra service definitions which can then be used in
the same way as those provided as standard. See
[ADDING SERVICES][].

The configuration file is parsed as a bash(1) script, allowing you to
set up and use variables, flow control and external commands.

Special control variables may be set up and used outside of any definition,
see [firehol-variables(5)][] as can the functions in
[CONFIGURATION HELPER COMMANDS][] and
[HELPER COMMANDS][].

# VARIABLES AVAILABLE

The following variables are made available in the FireHOL configuration
file and can be accessed as \${*VARIABLE*}.

UNROUTABLE\_IPS
:   This variable includes the IPs from both PRIVATE\_IPS and
    RESERVED\_IPS. It is useful to restrict traffic on interfaces and
    routers accepting Internet traffic, for example:

        interface eth0 internet src not "${UNROUTABLE_IPS}"
                  

PRIVATE\_IPS
:   This variable includes all the IP addresses defined as Private or
    Test by [RFC 3330](https://tools.ietf.org/html/rfc3330).

    You can override the default values by creating a file called
    `/etc/firehol/PRIVATE_IPS`.

RESERVED\_IPS
:   This variable includes all the IP addresses defined by
    [IANA](http://www.iana.org/) as reserved.

    You can override the default values by creating a file called
    `/etc/firehol/RESERVED_IPS`.

    Now that IPv4 address space has all been allocated there is very
    little reason that this value will need to change in future.

MULTICAST\_IPS
:   This variable includes all the IP addresses defined as Multicast by
    [RFC 3330](https://tools.ietf.org/html/rfc3330).

    You can override the default values by creating a file called
    `/etc/firehol/MULTICAST_IPS`.

# ADDING SERVICES

To define new services you add the appropriate lines before using them
later in the configuration file.

The following are required:

> server\_*myservice*\_ports="*proto*/*sports*"

> client\_*myservice*\_ports="*cports*"

*proto* is anything iptables(8) accepts e.g. "tcp", "udp", "icmp",
including numeric protocol values.

*sports* is the ports the server is listening at. It is a space-separated
list of port numbers, names and ranges (from:to). The keyword `any` will
match any server port.

*cports* is the ports the client may use to initiate a connection. It is a
space-separated list of port numbers, names and ranges (from:to). The
keyword `any` will match any client port. The keyword `default` will
match default client ports. For the local machine (e.g. a `client`
within an `interface`) it resolves to sysctl(8) variable
net.ipv4.ip\_local\_port\_range (or `/proc/sys/net/ipv4/ip_local_port_range`).
For a remote machine (e.g. a client within an interface or anything
in a router) it resolves to the variable DEFAULT\_CLIENT\_PORTS (see
[firehol-variables(5)][]).

The following are optional:

> require\_*myservice*\_modules="*modules*"

> require\_*myservice*\_nat\_modules="*nat-modules*"

The named kernel modules will be loaded when the definition is used. The
NAT modules will only be loaded if FIREHOL\_NAT is non-zero (see
[firehol-variables(5)][]).

For example, for a service named `daftnet` that listens at two ports,
port 1234 TCP and 1234 UDP where the expected client ports are the
default random ports a system may choose, plus the same port numbers the
server listens at, with further dynamic ports requiring kernel modules
to be loaded:

~~~~
    # Setup service
    server_daftnet_ports="tcp/1234 udp/1234"
    client_daftnet_ports="default 1234"
    require_daftnet_modules="ip_conntrack_daftnet"
    require_daftnet_nat_modules="ip_nat_daftnet
    
    interface eth0 lan0
      server daftnet accept
     
    interface eth1 lan1
      client daftnet reject
    
    router lan2lan inface eth0 outface eth1
      route daftnet accept
~~~~

Where multiple ports are provides (as per the example), FireHOL simply
determines all of the combinations of client and server ports and
generates multiple iptables(8) statements to match them.

To create more complex rules, or stateless rules, you will need to
create a bash function prefixed `rules_` e.g. `rules_myservice`. The
best reference is the many such functions in the main firehol(1)
script.

When adding a service which uses modules, or via a custom function, you
may also wish to include the following:

> ALL\_SHOULD\_ALSO\_RUN="${ALL\_SHOULD\_ALSO\_RUN} *myservice*"

which will ensure your service is set-up correctly as part of the `all`
service.

> **Note**
>
> To allow definitions to be shared you can instead create files and
> install them in the `/etc/firehol/services` directory with a `.conf`
> extension.
>
> The first line must read:
>
>     #FHVER: 1:213
>
> 1 is the service definition API version. It will be changed if the API
> is ever modified. The 213 originally referred to a FireHOL 1.x minor
> version but is no longer checked.
>
> FireHOL will refuse to run if the API version does not match the
> expected one.


# DEFINITIONS

 * [firehol-interface(5)][keyword-firehol-interface] - interface definition
 * [firehol-router(5)][keyword-firehol-router] - router definition

# SUBCOMMANDS

 * [firehol-policy(5)][keyword-firehol-policy] - policy command
 * [firehol-protection(5)][keyword-firehol-protection] - protection command
 * [firehol-server(5)][keyword-firehol-server] - server, route commands
 * [firehol-client(5)][keyword-firehol-client] - client command
 * [firehol-group(5)][keyword-firehol-group] - group command

# HELPER COMMANDS

These helpers can be used in `interface` and `router` definitions as
well as before them:

 * [firehol-iptables(5)][keyword-firehol-iptables] - iptables helper
 * [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper

This helper can be used in `router` definitions as well as before any
`router` or `interface`:

 * [firehol-tcpmss(5)][keyword-firehol-tcpmss] - tcpmss helper

# CONFIGURATION HELPER COMMANDS

These helpers should only be used outside of `interface` and `router`
definitions (i.e. before the first interface is defined).

* [firehol-version(5)][keyword-firehol-version] - version config helper
* [firehol-action(5)][keyword-firehol-action] - action config helper
* [firehol-blacklist(5)][keyword-firehol-blacklist] - blacklist config helper
* [firehol-classify(5)][keyword-firehol-classify] - classify config helper
* [firehol-connmark(5)][keyword-firehol-connmark] - connmark config helper
* [firehol-dscp(5)][keyword-firehol-dscp-helper] - dscp config helper
* [firehol-mac(5)][keyword-firehol-mac-helper] - mac config helper
* [firehol-mark(5)][keyword-firehol-mark-helper] - mark config helper
* [firehol-nat(5)][keyword-firehol-nat] - nat, snat, dnat, redirect helpers
* [firehol-proxy(5)][] - transparent proxy/squid helpers
* [firehol-tos(5)][keyword-firehol-tos-helper] - tos config helper
* [firehol-tosfix(5)][keyword-firehol-tosfix] - tosfix config helper

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol-variables(5)][] - control variables
* [firehol-services(5)][] - services list
* [firehol-actions(5)][] - actions for rules
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
