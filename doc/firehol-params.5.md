% firehol-params(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-params - optional rule parameters

<!--
extra-manpage: firehol-src.5
extra-manpage: firehol-src4.5
extra-manpage: firehol-src6.5
extra-manpage: firehol-dst.5
extra-manpage: firehol-dst4.5
extra-manpage: firehol-dst6.5
extra-manpage: firehol-srctype.5
extra-manpage: firehol-dsttype.5
extra-manpage: firehol-dport.5
extra-manpage: firehol-sport.5
extra-manpage: firehol-inface.5
extra-manpage: firehol-outface.5
extra-manpage: firehol-physin.5
extra-manpage: firehol-physout.5
extra-manpage: firehol-custom.5
extra-manpage: firehol-log.5
extra-manpage: firehol-loglimit.5
extra-manpage: firehol-proto.5
extra-manpage: firehol-uid.5
extra-manpage: firehol-gid.5
extra-manpage: firehol-mac-param.5
extra-manpage: firehol-mark-param.5
extra-manpage: firehol-tos-param.5
extra-manpage: firehol-dscp-param.5
extra-manpage: firehol-dport.5
extra-manpage: firehol-sport.5
-->

# SYNOPSIS

_Common_

{ src | src4 | src6 } [not] *host*

{ dst | dst4 | dst6 } [not] *host*

srctype [not] *type*

dsttype [not] *type*

proto [not] *protocol*

mac [not] *macaddr*

dscp [not] *value* *class* *classid*

mark [not] *id*

tos [not] *id*

custom "*iptables-options*..."

_Router Only_

inface [not] *interface*

outface [not] *interface*

physin [not] *interface*

physout [not] *interface*

_Interface Only_

uid [not] *user*

gid [not] *group*

_Logging_

log "log text" [level *loglevel*]

loglimit "log text" [level *loglevel*]

_Other_

sport *port*

dport *port*


# DESCRIPTION

Optional rule parameters are accepted by many commands to narrow the
match they make. Not all parameters are accepted by all commands so you
should check the individual commands for exclusions.

All matches are made against the REQUEST. FireHOL automatically sets up
the necessary  stateful rules to deal with replies in the reverse
direction.

Use the keyword `not` to match any value other than the one(s) specified.

The logging parameters are unusual in that they do not affect the match,
they just cause a log message to be emitted. Therefore, the logging
parameters don't support the `not` option.

FireHOL is designed so that if you specify a parameter that is also used
internally by the command then a warning will be issued (and the
internal version will be used).

# COMMON

## src, dst

Use `src` and `dst` to define the source and destination IP addresses of
the request respectively. *host* defines the IP or IPs to be matched.
Examples:

~~~~

server4 smtp accept src not 192.0.2.1
server4 smtp accept dst 198.51.100.1
server4 smtp accept src not 192.0.2.1 dst 198.51.100.1
server6 smtp accept src not 2001:DB8:1::/64
server6 smtp accept dst 2001:DB8:2::/64
server6 smtp accept src not 2001:DB8:1::/64 dst 2001:DB8:2::/64
~~~~

When attempting to create rules for both IPv4 and IPv6 it is generally
easier to use the `src4`, `src6`, `dst4` and `dst6` pairs:

~~~~

server46 smtp accept src4 192.0.2.1 src6 2001:DB8:1::/64
server46 smtp accept dst4 198.51.100.1 dst6 2001:DB8:2::/64
server46 smtp accept dst4 $d4 dst6 $d6 src4 not $d4 src6 not $s6
~~~~

To keep the rules sane, if one of the 4/6 pair specifies `not`, then so
must the other. If you do not want to use both IPv4 and IPv6 addresses,
you must specify the rule as IPv4 or IPv6 only. It is always possible to
write a second IPv4 or IPv6 only rule.

## srctype, dsttype

Use `srctype` or `dsttype` to define the source or destination IP
address type of the request. *type* is the address type category as used
in the kernel's network stack. It can be one of:

UNSPEC
:   an unspecified address (i.e. 0.0.0.0)

UNICAST
:   a unicast address

LOCAL
:   a local address

BROADCAST
:   a broadcast address

ANYCAST
:   an anycast address

MULTICAST
:   a multicast address

BLACKHOLE
:   a blackhole address

UNREACHABLE
:   an unreachable address

PROHIBIT
:   a prohibited address

THROW; NAT; XRESOLVE
:   undocumented

See iptables(8) or run `iptables -m addrtype --help` for more
information. Examples:

    server smtp accept srctype not "UNREACHABLE PROHIBIT"
        

## proto

Use `proto` to match by protocol. The *protocol* can be any accepted by
iptables(8).

## mac

Use `mac` to match by MAC address. The *macaddr* matches to the "remote"
host. In an `interface`, "remote" always means the non-local host. In a
`router`, "remote" refers to the source of requests for `server`s. It
refers to the destination of requests for `client`s. Examples:

~~~~

 # Only allow pop3 requests to the e6 host
 client pop3 accept mac 00:01:01:00:00:e6

 # Only allow hosts other than e7/e8 to access smtp
 server smtp accept mac not "00:01:01:00:00:e7 00:01:01:00:00:e8"
~~~~
        
## dscp

Use `dscp` to match the DSCP field on packets. For details on DSCP
values and classids, see [firehol-dscp(5)][keyword-firehol-dscp-helper].

~~~~

 server smtp accept dscp not "0x20 0x30"
 server smtp accept dscp not class "BE EF"
~~~~
        

## mark

Use `mark` to match marks set on packets. For details on mark ids, see
[firehol-mark(5)][keyword-firehol-mark-helper].

    server smtp accept mark not "20 55"
        

## tos

Use `tos` to match the TOS field on packets. For details on TOS ids, see
[firehol-tos(5)][keyword-firehol-tos-helper].

    server smtp accept tos not "Maximize-Throughput 0x10"
        

## custom

Use `custom` to pass arguments directly to iptables(8). All of the
parameters must be in a single quoted string. To pass an option to
iptables(8) that itself contains a space you need to quote strings in
the usual bash(1) manner. For example:

~~~~

server smtp accept custom "--some-option some-value"
server smtp accept custom "--some-option 'some-value second-value'"
~~~~


# ROUTER ONLY

## inface, outface

Use `inface` and `outface` to define the *interface* via which a request
is received and forwarded respectively. Use the same format as 
[firehol-interface(5)][keyword-firehol-interface].
Examples:

~~~~

server smtp accept inface not eth0
server smtp accept inface not "eth0 eth1"
server smtp accept inface eth0 outface eth1
~~~~

        
## physin, physout

Use `physin` and `physout` to define the physical *interface* via which a
request is received or send in cases where the inface or outface is
known to be a virtual interface; e.g. a bridge. Use the same format as
[firehol-interface(5)][keyword-firehol-interface]. Examples:

    server smtp accept physin not eth0
        

# INTERFACE ONLY

These parameters match information related to information gathered from
the local host. They apply only to outgoing packets and are silently
ignored for incoming requests and requests that will be forwarded.

> **Note**
>
> The Linux kernel infrastructure to match PID/SID and executable names
> with `pid`, `sid` and `cmd` has been removed so these options can no
> longer be used.

## uid

Use `uid` to match the operating system user sending the traffic. The
*user* is a username, uid number or a quoted list of the two.

For example, to limit which users can access POP3 and IMAP by preventing
replies for certain users from being sent:

    client "pop3 imap" accept user not "user1 user2 user3"
        

Similarly, this will allow all requests to reach the server but prevent
replies unless the web server is running as apache:

    server http accept user apache
        
## gid

Use `gid` to match the operating system group sending the traffic. The
*group* is a group name, gid number or a quoted list of the two.


# LOGGING

## log, loglimit

Use `log` or `loglimit` to log matching packets to syslog. Unlike
iptables(8) logging, this is not an action: FireHOL will produce
multiple iptables(8) commands to accomplish both the action for the rule
and the logging.

Logging is controlled using the FIREHOL\_LOG\_OPTIONS and
FIREHOL\_LOG\_LEVEL environment variables - see
[firehol-variables(5)][]. `loglimit`
additionally honours the FIREHOL\_LOG\_FREQUENCY and FIREHOL\_LOG\_BURST
variables.

Specifying `level` (which takes the same values as FIREHOL\_LOG\_LEVEL)
allows you to override the log level for a single rule.


# LESSER USED PARAMETERS

## dport, sport

FireHOL also provides `dport`, `sport` and `limit` which are used
internally and rarely needed within configuration files.

`dport` and `sport` require an argument *port* which can be a name, number,
range (FROM:TO) or a quoted list of ports.

For `dport` *port* specifies the destination port of a request and can be
useful when matching traffic to helper commands (such as nat) where there
is no implicit port.

For `sport` *port* specifies the source port of a request and can be useful
when matching traffic to helper commands (such as nat) where there is no
implicit port.

## limit

`limit` requires the arguments *frequency* and *burst* and will limit the
matching of traffic in both directions.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-server(5)][keyword-firehol-server] - server, route commands
* [firehol-client(5)][keyword-firehol-client] - client command
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-mark(5)][keyword-firehol-mark-helper] - mark config helper
* [firehol-tos(5)][keyword-firehol-tos-helper] - tos config helper
* [firehol-dscp(5)][keyword-firehol-dscp-helper] - dscp config helper
* [firehol-variables(5)][] - control variables
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
