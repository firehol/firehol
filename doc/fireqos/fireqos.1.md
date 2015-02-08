% fireqos(1) FireQOS Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

fireqos - an easy to use but powerful traffic shaping tool

# SYNOPSIS

fireqos *CONFIGFILE* [start | debug] [ -- conf-arg ... ]

fireqos { stop | clear_all_qos }

fireqos status [*name* [ dump [*class*]]]

fireqos { dump | tcpdump } *name* *class* [ *tcpdump-arg* ... ]

fireqos { drops | overlimits | requeues } *name*

# DESCRIPTION

FireQOS is a helper to assist you configure traffic shaping on Linux.

Run without any arguments, `fireqos` will present some help on usage.

When given *CONFIGFILE*, `fireqos` will use the named file instead of
`/etc/firehol/fireqos.conf` as its configuration.

The parameter *name* always refers to an interface name from the
configuration file. The parameter *class* always refers to a named class
within a named interface.

It is possible to pass arguments for use by the configuration file
separating any conf-arg values from the rest of the arguments with `--`.
The arguments are accessible in the configuration using standard
bash(1) syntax e.g. \$1, \$2, etc.

# COMMANDS

start; debug
:   Activates traffic shaping on all interfaces, as given in the
    configuration file. When invoked as `debug`, FireQOS also prints all
    of the tc(8) commands it executes.

stop
:   Removes all traffic shaping applied by FireQOS (it does not touch
    QoS on other interfaces and IFBs used by other tools).

clear\_all\_qos
:   Removes all traffic shaping on all network interfaces and removes
    all IFB devices from the system, even those applied by other tools.

status
:   Shows live utilisation for the specified interface. FireQOS will
    show you the rate of traffic on all classes, adding one line per
    second (similarly to vmstat, iostat, etc.)

    If `dump` is specified, it tcpdumps the traffic in the given class
    of the interface.

tcpdump; dump
:   FireQOS temporarily mirrors the traffic of any leaf class to an IFB
    device. Then it runs tcpdump(8) on this interface to dump the traffic
    to your console.

    You may add any tcpdump(8) parameters you like to the command line, (to
    dump the traffic to a file, match a subset of the traffic, etc.),
    for example this:

        fireqos tcpdump adsl-in voip -n

    will start a tcpdump of all traffic on interface adsl-in, in class
    voip. The parameter `-n` is a tcpdump(8) parameter.

    > **Note**
    >
    > When FireQOS is running in `tcpdump` mode, it locks itself and will
    > refuse to run in parallel with another FireQOS altering the QoS,
    > or tcpdumping other traffic. This is because FireQOS reserves
    > device ifb0 for monitoring. If two FireQOS processes were allowed
    > to `tcpdump` in parallel, your dumps would be wrong. So it locks
    > itself to prevent such a case.

drops
:   Shows packets dropped per second, per class, for the specified
    interface.

overlimits
:   Shows packets delayed per second, per class, for the specified
    interface.

requeues
:   Shows packets requeued per second, per class, for the specified
    interface.

# FILES

`/etc/firehol/fireqos.conf`

# SEE ALSO

* [fireqos.conf(5)][] - FireQOS configuration file
* [FireHOL Website](http://firehol.org/)
* [FireQOS Online PDF Manual](http://firehol.org/fireqos-manual.pdf)
* [FireQOS Online Documentation](http://firehol.org/documentation/)
* [tc(8)](http://lartc.org/manpages/tc.html) - show / manipulate traffic control settings
* [tcpdump(8)](http://www.tcpdump.org/manpages/tcpdump.1.html) - show / manipulate traffic control settings
