% vnetbuild.conf(5) VNetBuild Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

vnetbuild.conf - VNetBuild configuration file

<!--
extra-manpage: vnetbuild.conf.5
extra-manpage: vnetbuild-host.5
extra-manpage: vnetbuild-switch.5
extra-manpage: vnetbuild-dev.5
extra-manpage: vnetbuild-bridgedev.5
extra-manpage: vnetbuild-route.5
extra-manpage: vnetbuild-exec.5
  -->

# SYNOPSIS

````
host *ID*
    dev *DEVICE* [ *ID*/*PAIRDEV* ] [ *IP*/*MASK*... ]
    ...
    bridgedev *BRIDGE* [ *DEVICE*... ] [ *IP*/*MASK*... ]
    ...
    route *ROUTECMD*
    ...
    exec *CUSTOMCMD*
    ...

...

switch *ID*
  dev *DEVICE* [ *ID*/*PAIRDEV* ]
  ...
  exec *CUSTOMCMD*
  ...

...
````

# DESCRIPTION

There is no default configuration file for [vnetbuild(1)][]; one must
always be specified on the command line.

The configuration file defines a set of namespaces that will be operated
on.

VNetBuild defines two types of namespace, a `host` and a `switch`. Any
number of each may be specified, with any number of configuration
statements in each.

Note
:   The Linux kernel does not see any difference between a `host` and
    a `switch` namespace. VNetBuild provides the distinction to make it
    easy build full virtual networks.


# NAMESPACE DEFINITIONS

Namespace definitions come in two types, `host` and `switch`. Simply
provide a simple unique alphanumeric *ID*. Any subsequent statements
apply to this namespace until the next `host` or `switch` statement.

A `host` definition is designed to work like a physical machine.
It allows you to specify any number of `dev` entries for network
interfaces, with their IP addresses.  You can also define any
number of Linux bridges with `bridgedev` to add your defined
interfaces to.

A `host` also allows any number of custom `exec` commands for
extensibility and provides a `route` statement to deal with the
common case of wanting to add network routes to the host.

A `switch` definition is designed to work like a physical network
switch. It allows you to add any number of `dev` entries (and also
custom `exec` commands for extensibility) but nothing else.

In addition, `dev` entries in a `switch` may only specify device names,
they cannot have an IP address associated. A `switch` has a bridge
automatically created in it and all `dev` entries are automatically
added to it.

# CONFIGURATION STATEMENTS

dev *DEVICE* ...
:   Define a virtual ethernet device, *DEVICE* in a `host` or `switch`.

    Devices must exist in pairs. A `dev` must first be defined unpaired
    in a namespace, then some subsequent `dev` must define the pair:

    ````
    host a
      dev veth0
    host b
      dev vppp0 a/veth0
    ````

    Any *DEVICE* name which is acceptable to the Linux kernel
    may be used. We recommend sticking to e.g. `veth0`, `vppp0` etc.
    to make it clear that they are virtual and also how you are
    thinking of the device in terms of your setup. Devices will
    be created as type `veth`, irrespective of what you call them.

    Hosts may optionally specify one or more *IP*/*MASK* values which
    will be applied (along with the calculated broadcast address)
    automatically, e.g.:

    ````
    host a
      dev veth0 10.0.0.1/8 192.168.1.2/24
    host b
      dev vppp0 a/veth0 10.0.0.2/8 192.168.1.3/24
    ````

    A `dev` may not specify an IP address if it is in a `switch`. Switches
    exist just to tie together multiple devices in hosts, just like a
    physical network switch.

bridgedev *BRIDGE* ...
:   Define an ethernet bridge, *BRIDGE* in a `host`. These are setup
    automatically using ip(8) and shown with bridge(8).

    A bridge can specify network devices from its own namespace to
    be automatically added, as well as its own IP address(es).

    ````
    host a
      dev veth0
      dev veth1 otherns/vdev0
      bridgedev vbr0 veth0 veth1 10.0.0.3/8
    ````

    Devices included in a bridge generally do not need their own IP
    address (although that is permitted).

    Bridges cannot have a pair themselves, but any devices added to
    a bridge need a pair as usual.

route *ROUTECMD*
:   Specify an additional network route for a `host`.

    Most commonly to add a default route from hosts on a "LAN" to
    the machine that acts as a gateway, e.g.:

    ````
    route default via 10.0.0.254
    ````

    The syntax of *ROUTECMD* is anything that can fit this pattern:

    ````
    ip route add ROUTECMD
    ````

    See ip(8) and ip-route(8) for help adding routes. If you want to do
    anything more complex than simply adding routes, use the `exec`
    configuration statement.

exec *CUSTOMCMD*
:   Execute a custom command in a `host` or `switch` once the rest
    of the namespace setup is complete.

    Once all the namespaces are created, the final step in setting
    each one up is to have its `exec` statements combined and executed.

    It is roughly the equivalent to writing your own script and executing
    it after `vnetbuild start` has finished:

    ````
    sudo iptables netns exec myns ./myscript.sh
    ````

    See below for some common uses for custom `exec` commands.

# COMMON CUSTOM COMMANDS

Forwarding is not enabled by the Linux kernel when a namespace is first
created. This can be easily done for any hosts that need to forward
traffic:

~~~~
host mygateway
    ...
    exec echo 1 > /proc/sys/net/ipv4/ip_forward
~~~~

The `exec` operates in the `mygateway` namespace so your host is not
affected.

Logs from network namespaces are not included in the normal system
logs. To enable iptables logging you must start an instance of
ulogd(8) in the namespace and use *ULOG* or *NFLOG* logging. For
FireHOL, that means set `FIREHOL_LOG_MODE=ULOG` or
`FIREHOL_LOG_MODE=NFLOG`. Note that *NFLOG* only works with ulogd
version 2.

The default configuration for ulogd(8) is `/etc/ulogd.conf`. Assuming
the default place it will write iptables logs to is
`/var/log/ulog/syslogemu.log` (otherwise change the `sed` command
as required), it is simple to set up per-namespace logging:

~~~~
host mygateway
  ...
  exec sed 's:/var/log/ulog/syslogemu.log:/var/log/ulog/mygateway.log:' /etc/ulogd.conf > $NSTMP/ulogd.conf
  exec /usr/sbin/ulogd -d -c $NSTMP/ulogd.conf
~~~~

The `-d` flag to ulogd(8) makes it become a daemon; when `vnetbuild stop`
executes it will automatically kill any programs running in the namespaces
is is stopping, which includes the logging daemon.

The configuration file will get cleaned as soon as `vnetbuild start`
is finished. To be able to access such files you need to write them to
a location not under `$NSTMP` or create them up outside the `vnetbuild`
configuration altogether.

# EXAMPLE

A simple LAN arrangement with two hosts, one of which is a gateway
to third host:

````
host host01
  dev veth0 10.0.0.1/8
  dev vppp0 192.168.0.1/24
  exec echo 1 > /proc/sys/net/ipv4/ip_forward
  route default via 192.168.0.1

host host02
  dev veth0 10.0.0.2/8
  route default via 10.0.0.1

switch lan
  dev d01 host01/veth0
  dev d02 host02/veth0

host extern01
  dev veth0 host01/vppp0 192.168.0.254/24
  route default via 192.168.0.1
  exec echo 1 > /proc/sys/net/ipv4/ip_forward
````

# LIMITATIONS

When created, the namespaces setup by `vnetbuild` are completely
disconnected from any real network. There is no way of defining
such a connection in the `vnetbuild` configuration as allowing it
would lead to conflicts with the normal network setup tools and
configuration files in most distributions.

It is possible to arrange your network so you can connect real
devices into one or more network namespaces. For the general
approach see this [mailing list post][ml].

[ml]: http://lists.firehol.org/pipermail/firehol-support/2015-April/003043.html

# SEE ALSO

* [vnetbuild(1)][] - VNetBuild program
* [FireHOL Website](http://firehol.org/)
* [VNetBuild Online PDF Manual](http://firehol.org/vnetbuild-manual.pdf)
* [VNetBuild Online Documentation](http://firehol.org/documentation/)
* [ip(8)](http://manpages.ubuntu.com/manpages/trusty/man8/ip.8.html) - show/manipulate network devices
* [ip-route(8)](http://manpages.ubuntu.com/manpages/trusty/man8/ip-route.8.html) - routing table management
* [bridge(8)](http://manpages.ubuntu.com/manpages/trusty/man8/bridge.8.html) - routing table management
* [ulogd(8)](http://manpages.ubuntu.com/manpages/trusty/man8/ulogd.8.html) - netfilter/iptables logging daemon
