% firehol(1) FireHOL Reference | VERSION
% FireHOL Team
  Original man page by Marc Brockschmidt
% Built DATE

# NAME

firehol - an easy to use but powerful iptables stateful firewall

# SYNOPSIS

firehol

sudo -E firehol panic [ *IP* ]

firehol *command* [ -- *conf-arg*... ]

firehol *CONFIGFILE* \[start|debug|try\] [-- *conf-arg*... ]

# DESCRIPTION

Running `firehol` invokes iptables(8) to manipulate your firewall.

Run without any arguments, `firehol` will present some help on usage.

When given *CONFIGFILE*, `firehol` will use the named file instead of
`/etc/firehol/firehol.conf` as its configuration. If no *command* is
given, `firehol` assumes `try`.

It is possible to pass arguments for use by the configuration file
separating any conf-arg values from the rest of the arguments with `--`.
The arguments are accessible in the configuration using standard
bash(1) syntax e.g. \$1, \$2, etc.

## PANIC

To block all communication, invoke `firehol` with the `panic` command.

FireHOL removes all rules from the running firewall and then DROPs all
traffic on all iptables(8) tables (mangle, nat, filter) and pre-defined
chains (PREROUTING, INPUT, FORWARD, OUTPUT, POSTROUTING).

DROPing is not done by changing the default policy to DROP, but by
adding one rule per table/chain to drop all traffic. This allows systems
which do not reset all the chains to ACCEPT when starting to function
correctly.

When activating panic mode, FireHOL checks for the existence of the
SSH\_CLIENT shell environment variable, which is set by ssh(1). If it
finds this, then panic mode will allow the established SSH connection
specified in this variable to operate.

> **Note**
>
> In order for FireHOL to see the environment variable you must ensure
> that it is preserved. For sudo(8) use the `-E` and for su(1) omit the
> `-` (minus sign).

If SSH\_CLIENT is not set, the *IP* after the panic argument allows you
to give an IP address for which all established connections between the
IP address and the host in panic will be allowed to continue.

# COMMANDS

start; restart
:   Activates the firewall using `/etc/firehol/firehol.conf`.

    Use of the term `restart` is allowed for compatibility with common
    init implementations.

try
:   Activates the firewall, waiting for the user to type the word
    `commit`. If this word is not typed within 30 seconds, the previous
    firewall is restored.

stop
:   Stops a running iptables(8) firewall by clearing all of the tables and
    chains and setting the default policies to ACCEPT. This will allow
    all traffic to pass unchecked.

condrestart
:   Restarts the FireHOL firewall only if it is already active. This is
    the generally expected behaviour (but opposite to FireHOL prior to
    2.0.0-pre4).

status
:   Shows the running firewall, using `/sbin/iptables -nxvL | less`.

save
:   Start the firewall and then save it using iptables-save(8) to
    the location given by FIREHOL\_AUTOSAVE. See
    [firehol-defaults.conf(5)][] for more information.

    The required kernel modules are saved to an executable shell script
    `/var/spool/firehol/last_save_modules.sh`, which can be called
    during boot if a firewall is to be restored.

    > **Note**
    >
    > External changes may cause a firewall restored after a reboot to
    > not work as intended where starting the firewall with FireHOL will
    > work.
    >
    > This is because as part of starting a firewall, FireHOL checks
    > some changeable values. For instance the current kernel
    > configuration is checked (for client port ranges), and RPC servers
    > are queried (to allow correct functioning of the NFS service).

<a id="debug"></a>debug
:   Parses the configuration file but instead of activating it, FireHOL
    shows the generated iptables(8) statements.

<a id="explain"></a>explain
:   Enters an interactive mode where FireHOL accepts normal
    configuration commands and presents the generated iptables(8) commands
    for each of them, together with some reasoning for its purpose.

    Additionally, FireHOL automatically generates a configuration script
    based on the successful commands given.

    Some extra commands are available in `explain` mode.

    help
    :   Present some help

    show
    :   Present the generated configuration

    quit
    :   Exit interactive mode and quit

<a id="helpme-wizard"></a>helpme; wizard
:   Tries to guess the FireHOL configuration needed for the current
    machine.

    FireHOL will not stop or alter the running firewall. The
    configuration file is given in the standard output of firehol,
    thus `firehol helpme > /tmp/firehol.conf` will produce the output in
    `/tmp/firehol.conf`.

    The generated FireHOL configuration *must* be edited before use on
    your systems. You are required to take a number of decisions; the
    comments in the generated file will instruct you in the choices you
    must make.

# FILES

`/etc/firehol/firehol.conf`

# SEE ALSO

* [firehol.conf(5)][] - FireHOL configuration
* [firehol-defaults.conf(5)][] - control variables
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
