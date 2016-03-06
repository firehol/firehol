% firehol-variables(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-variables - control variables for FireHOL

# SYNOPSIS

Defaults:

* DEFAULT\_INTERFACE\_POLICY="DROP"
* DEFAULT\_ROUTER\_POLICY="RETURN"
* UNMATCHED\_INPUT\_POLICY="DROP"
* UNMATCHED\_OUTPUT\_POLICY="DROP"
* UNMATCHED\_FORWARD\_POLICY="DROP"
* FIREHOL\_INPUT\_ACTIVATION\_POLICY="ACCEPT"
* FIREHOL\_OUTPUT\_ACTIVATION\_POLICY="ACCEPT"
* FIREHOL\_FORWARD\_ACTIVATION\_POLICY="ACCEPT"
* FIREHOL\_LOG\_MODE="LOG"
* FIREHOL\_LOG\_LEVEL=*see notes*
* FIREHOL\_LOG\_OPTIONS="--log-level warning"
* FIREHOL\_LOG\_FREQUENCY="1/second"
* FIREHOL\_LOG\_BURST="5"
* FIREHOL\_LOG\_PREFIX=""
* FIREHOL\_DROP\_INVALID="0"
* DEFAULT\_CLIENT\_PORTS="1000:65535"
* FIREHOL\_NAT="0"
* FIREHOL\_ROUTING="0"
* FIREHOL\_AUTOSAVE=*see notes*
* FIREHOL\_AUTOSAVE6=*see notes*
* FIREHOL\_LOAD\_KERNEL\_MODULES="1"
* FIREHOL\_TRUST\_LOOPBACK="1"
* FIREHOL\_DROP\_ORPHAN\_TCP\_ACK\_FIN="1"
* FIREHOL\_DROP\_ORPHAN\_TCP\_ACK\_RST="1"
* FIREHOL\_DROP\_ORPHAN\_TCP\_ACK="1"
* FIREHOL\_DROP\_ORPHAN\_TCP\_RST="1"
* FIREHOL\_DROP\_ORPHAN\_IPV4\_ICMP\_TYPE3="1"
* FIREHOL\_DEBUGGING=""
* WAIT\_FOR\_IFACE=""

# DESCRIPTION

There are a number of variables that control the behaviour of FireHOL.

All variables may be set in the main FireHOL configuration file
`/etc/firehol/firehol.conf`.

Variables which affect the runtime but not the created firewall may also
be set as environment variables before running
[firehol(1)][]. These can change the default values but will
be overwritten by values set in the configuration file. If a variable
can be set by an environment variable it is specified below.

FireHOL also sets some variables before processing the configuration
file which you can use as part of your configuration. These are
described in [firehol.conf(5)][].


# VARIABLES


DEFAULT\_INTERFACE\_POLICY
:   This variable controls the default action to be taken on traffic not
    matched by any rule within an interface. It can be overridden using
    [firehol-policy(5)][keyword-firehol-policy].

    Packets that reach the end of an interface without an action of
    return or accept are logged. You can control the frequency of this
    logging by altering FIREHOL\_LOG\_FREQUENCY.

    Example:

    ~~~~

    DEFAULT_INTERFACE_POLICY="REJECT"
    ~~~~

                  

DEFAULT\_ROUTER\_POLICY
:   This variable controls the default action to be taken on traffic not
    matched by any rule within a router. It can be overridden using
    [firehol-policy(5)][keyword-firehol-policy].

    Packets that reach the end of a router without an action of return
    or accept are logged. You can control the frequency of this logging
    by altering FIREHOL\_LOG\_FREQUENCY.

    Example:

    ~~~~

    DEFAULT_ROUTER_POLICY="REJECT"
    ~~~~

                  

UNMATCHED\_{INPUT|OUTPUT|FORWARD}\_POLICY
:   These variables control the default action to be taken on traffic
    not matched by any interface or router definition that was incoming,
    outgoing or for forwarding respectively. Any supported value from
    [firehol-actions(5)][] may be set.

    All packets that reach the end of a chain are logged, regardless of
    these settings. You can control the frequency of this logging by
    altering FIREHOL\_LOG\_FREQUENCY.

    Example:

    ~~~~

    UNMATCHED_INPUT_POLICY="REJECT"
    UNMATCHED_OUTPUT_POLICY="REJECT"
    UNMATCHED_FORWARD_POLICY="REJECT"
    ~~~~
                  

FIREHOL\_{INPUT|OUTPUT|FORWARD}\_ACTIVATION\_POLICY
:   These variables control the default action to be taken on traffic
    during firewall activation for incoming, outgoing and forwarding
    respectively. Acceptable values are `ACCEPT`, `DROP` and `REJECT`.
    They may be set as environment variables.

    FireHOL defaults all values to `ACCEPT` so that your communications
    continue to work uninterrupted.

    If you wish to prevent connections whilst the new firewall is
    activating, set these values to `DROP`. This is important to do if
    you are using `all` or `any` to match traffic; connections
    established during activation will continue even if they would not
    be allowed once the firewall is established.

    Example:

    ~~~~

    FIREHOL_INPUT_ACTIVATION_POLICY="DROP"
    FIREHOL_OUTPUT_ACTIVATION_POLICY="DROP"
    FIREHOL_FORWARD_ACTIVATION_POLICY="DROP"
    ~~~~


FIREHOL\_LOG\_MODE
:   This variable controls method that FireHOL uses for logging.

    Acceptable values are `LOG` (normal syslog) and `ULOG` (netfilter
    ulogd). When `ULOG` is selected, FIREHOL\_LOG\_LEVEL is ignored.

    Example:

    ~~~~

    FIREHOL_LOG_MODE="ULOG"
    ~~~~

    To see the available options run: `/sbin/iptables -j LOG --help` or
    `/sbin/iptables -j ULOG --help`

FIREHOL\_LOG\_LEVEL
:   This variable controls the level at which events will be logged to
    syslog.

    To avoid packet logs appearing on your console you should ensure
    klogd only logs traffic that is more important than that produced by
    FireHOL.

    Use the following option to choose an iptables(8) log level (alpha or
    numeric) which is higher than the `-c` of klogd.

      iptables           klogd     description
      ------------------ --------- ---------------------------------------------
      emerg (0)          0         system is unusable
      alert (1)          1         action must be taken immediately
      crit (2)           2         critical conditions
      error (3)          3         error conditions
      warning (4)        4         warning conditions
      notice (5)         5         normal but significant condition
      info (6)           6         informational
      debug (7)          7         debug-level messages

      : iptables/klogd levels

    > **Note**
    >
    > The default for klogd is generally to log everything (7 and lower)
    > and the default level for iptables(4) is to log as warning (4).

FIREHOL\_LOG\_OPTIONS
:   This variable controls the way in which events will be logged to
    syslog.

    Example:

    ~~~~

    FIREHOL_LOG_OPTIONS="--log-level info \
                         --log-tcp-options --log-ip-options"
    ~~~~

    To see the available options run: `/sbin/iptables -j LOG --help`

FIREHOL\_LOG\_FREQUENCY; FIREHOL\_LOG\_BURST
:   These variables control the frequency that each logging rule will
    write events to syslog. FIREHOL\_LOG\_FREQUENCY is set to the
    maximum average frequency and FIREHOL\_LOG\_BURST specifies the
    maximum initial number.

    Example:

    ~~~~

    FIREHOL_LOG_FREQUENCY="30/minute"
    FIREHOL_LOG_BURST="2"
    ~~~~

    To see the available options run: `/sbin/iptables -m limit --help`

FIREHOL\_LOG\_PREFIX
:   This value is added to the contents of each logged line for easy
    detection of FireHOL lines in the system logs. By default it is
    empty.

    Example:

    ~~~~

    FIREHOL_LOG_PREFIX="FIREHOL:"
    ~~~~

FIREHOL\_DROP\_INVALID
:   If set to 1, this variable causes FireHOL to drop all packets
    matched as `INVALID` in the iptables(8) connection tracker.

    You may be better off using
    [firehol-protection(5)][keyword-firehol-protection] to control
    matching of `INVALID` packets and others on a per-interface
    and per-router basis.

    > **Note**
    >
    > Care must be taken on IPv6 interfaces, since ICMPv6 packets such
    > as Neighbour Discovery are not tracked, meaning they are marked
    > as INVALID.

    Example:

    ~~~~

    FIREHOL_DROP_INVALID="1"
    ~~~~

DEFAULT\_CLIENT\_PORTS
:   This variable controls the port range that is used when a remote
    client is specified. For clients on the local host, FireHOL finds
    the exact client ports by querying the kernel options.

    Example:

    ~~~~

    DEFAULT_CLIENT_PORTS="0:65535"
    ~~~~

FIREHOL\_NAT
:   If set to 1, this variable causes FireHOL to load the NAT kernel
    modules. If you make use of the NAT helper commands, the variable
    will be set to 1 automatically. It may be set as an environment
    variable.

    Example:

    ~~~~

    FIREHOL_NAT="1"
    ~~~~

FIREHOL\_ROUTING
:   If set to 1, this variable causes FireHOL to enable routing in the
    kernel. If you make use of `router` definitions or certain helper
    commands the variable will be set to 1 automatically. It may be set
    as an environment variable.

    Example:

    ~~~~

    FIREHOL_ROUTING="1"
    ~~~~

FIREHOL\_AUTOSAVE; FIREHOL\_AUTOSAVE6
:   These variables specify the file of IPv4/IPv6 rules that will be
    created when [firehol(1)][] is called with the `save`
    argument. It may be set as an environment variable.

    If the variable is not set, a system-specific value is used which
    was defined at configure-time. If no value was chosen then the save
    fails.

    Example:

    ~~~~

    FIREHOL_AUTOSAVE="/tmp/firehol-saved-ipv4.txt"
    FIREHOL_AUTOSAVE6="/tmp/firehol-saved-ipv6.txt"
    ~~~~

FIREHOL\_LOAD\_KERNEL\_MODULES
:   If set to 0, this variable forces FireHOL to not load any kernel
    modules. It is needed only if the kernel has modules statically
    included and in the rare event that FireHOL cannot access the kernel
    configuration. It may be set as an environment variable.

    Example:

    ~~~~

    FIREHOL_LOAD_KERNEL_MODULES="0"
    ~~~~

FIREHOL\_TRUST\_LOOPBACK
:   If set to 0, the loopback device "lo" will not be trusted and you
    can write standard firewall rules for it.

    > **Warning**
    >
    > If you do not set up appropriate rules, local processes will not
    > be able to communicate with each other which can result in serious
    > breakages.

    By default "lo" is trusted and all `INPUT` and `OUTPUT` traffic is
    accepted (forwarding is not included).

    Example:

    ~~~~

    FIREHOL_TRUST_LOOPBACK="0"
    ~~~~

FIREHOL\_DROP\_ORPHAN\_TCP\_ACK\_FIN
:   If set to 1, FireHOL will drop all orphan such packets
    without logging them.

    In busy environments the iptables(8) connection tracker removes
    connection tracking list entries as soon as it receives a FIN. This
    makes the ACK FIN appear as an invalid packet which will normally be
    logged by FireHOL.

    Example:

    ~~~~

    FIREHOL_DROP_ORPHAN_TCP_ACK_FIN="1"
    ~~~~

FIREHOL\_DROP\_ORPHAN\_TCP\_ACK\_RST
:   If set to 1, FireHOL will drop all orphan such packets
    without logging them.

    In busy environments the iptables(8) connection tracker removes
    connection tracking list entries as soon as it receives a RST. This
    makes the ACK RST appear as an invalid packet which will normally be
    logged by FireHOL.

    Example:

    ~~~~

    FIREHOL_DROP_ORPHAN_TCP_ACK_RST="1"
    ~~~~

FIREHOL\_DROP\_ORPHAN\_TCP\_ACK
:   If set to 1, FireHOL will drop all orphan such packets
    without logging them.

    In busy environments the iptables(8) connection tracker removes
    uneeded connection tracking list entries. This makes ACK packets
    appear as an invalid packet which will normally be logged by FireHOL.

    Example:

    ~~~~

    FIREHOL_DROP_ORPHAN_TCP_ACK="1"
    ~~~~

FIREHOL\_DROP\_ORPHAN\_TCP\_RST
:   If set to 1, FireHOL will drop all orphan such packets
    without logging them.

    In busy environments the iptables(8) connection tracker removes
    uneeded connection tracking list entries. This makes RST packets
    appear as an invalid packet which will normally be logged by FireHOL.

    Example:

    ~~~~

    FIREHOL_DROP_ORPHAN_TCP_RST="1"
    ~~~~

FIREHOL\_DROP\_ORPHAN\_IPV4\_ICMP\_TYPE3
:   If set to 1, FireHOL will drop all orphan ICMP destination
    unreachable packets without logging them.

    In busy environments the iptables(8) connection tracker removes
    uneeded connection tracking list entries. This makes ICMP destination
    unreachable appear as an invalid packet which will normally be logged
    by FireHOL.

    Example:

    ~~~~

    FIREHOL_DROP_ORPHAN_IPV4_ICMP_TYPE3="1"
    ~~~~

FIREHOL\_DEBUGGING
:   If set to a non-empty value, switches on debug output so that it is
    possible to see what processing FireHOL is doing.

    > **Note**
    >
    > This variable can *only* be set as an environment variable, since
    > it is processed before any configuration files are read.

    Example:

    ~~~~

    FIREHOL_DEBUGGING="Y"
    ~~~~

WAIT\_FOR\_IFACE
:   If set to the name of a network device (e.g. eth0), FireHOL will
    wait until the device is up (or until 60 seconds have elapsed)
    before continuing.

    > **Note**
    >
    > This variable can *only* be set as an environment variable, since
    > it determines when the main configuration file will be processed.

    A device does not need to be up in order to have firewall rules
    created for it, so this option should only be used if you have a
    specific need to wait (e.g. the network must be queried to determine
    the hosts or ports which will be firewalled).

    Example:

    ~~~~

    WAIT_FOR_IFACE="eth0"
    ~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-nat(5)][keyword-firehol-nat] - nat, snat, dnat, redirect helpers
* [firehol-actions(5)][] - actions for rules
* [iptables(8)](http://ipset.netfilter.org/iptables.man.html) - administration tool for IPv4 firewalls
* [ip6tables(8)](http://ipset.netfilter.org/ip6tables.man.html) - administration tool for IPv6 firewalls
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
