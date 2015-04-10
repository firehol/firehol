% vnetbuild(1) VNetBuild Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

vnetbuild - an easy to use but powerful namespace setup tool

# SYNOPSIS

sudo vnetbuild *CONFIGFILE* { start | stop | status }

vnetbuild *CONFIGFILE* graphviz *OUTFILE*.{gv|png|pdf|ps}

# DESCRIPTION

VNetBuild is a program that helps you set up groups of interconnected
network namespaces, to simulate networks of any complexity without
resorting to using real or virtual machines.

This is ideal for testing complex multi-host configurations with a minimal
amount of resources on a single machine:

*   Each namespace can have its own network setup, including firewall
    and QOS configuration.
*   Commands can be run in the namespace and will have that specific
    view of the network, including running standard network tools and
    daemons.

Run without any arguments, `vnetbuild` will present some help on usage.

# COMMANDS

start
:   Sets up a series of network namespaces as defined in *CONFIGFILE*.
    `vnetbuild` creates interconnected network devices as specified
    in the configuration, sets up routing and runs any custom
    commands that are given within the namespace.

stop
:   Removes any devices from the namespaces defined in *CONFIGFILE*
    and kills any processes running with the namespaces, then
    removes the namespaces themselves.

status
:   For each namespace defined in *CONFIGFILE*, shows if it is active
    and if so its network devices and their configuration.

graphviz *OUTFILE*
:   Generates a graph of the network defined in *CONFIGFILE*. This
    does not need root access, nor does it require the namespaces
    to have been started.

    *OUTFILE* can be `png` `pdf` or `ps`. If the extension `gv` is
    given the output is a graphviz(7) file which you can process
    separately.

# RUNNING COMMANDS IN A NAMESPACE

Once you have created a set of network namespaces, you can easily
run any commands you want within them. If for instance you defined
three hosts (`host_a` with IP `10.0.0.1`, `host_b`
with IP `10.0.0.2` and `host_c` with IP `10.0.0.3`)
connected via a common switch `sw0`:

~~~~
 # ping host_b and host_c from host_a
 sudo ip netns exec host_a ping 10.0.0.2
 sudo ip netns exec host_a ping 10.0.0.3

 # use netcat to listen on host_a and send data from host_b
 # (use two terminals to run the commands simultaneously)
 sudo ip netns exec host_a nc -l -p 23
 sudo ip netns exec host_b nc -q 0 10.0.0.1 23 < /etc/hosts

 # capture traffic passing through the switch, then view it
 sudo ip netns exec sw0 tcpdump -i switch -w capfile
 wireshark capfile

 # Use 'firehol panic' in host_b to block all traffic
 # (you could equally load a full config etc.)
 sudo ip netns exec host_b firehol panic

 # this is now blocked
 sudo ip netns exec host_a ping 10.0.0.2

 # not blocked (host_b not involved)
 sudo ip netns exec host_a ping 10.0.0.3

 # obtain a shell for your regular user, only "in" host_c
 sudo ip netns exec host_c sudo -i -u $USER
 ip a | grep 10.0.0.3
~~~~

# SEE ALSO

* [vnetbuild.conf(5)][] - VNetBuild configuration file
* firehol(1) - FireHOL program
* fireqos(1) - FireQOS program
* [FireHOL Website](http://firehol.org/)
* [VNetBuild Online PDF Manual](http://firehol.org/vnetbuild-manual.pdf)
* [VNetBuild Online Documentation](http://firehol.org/documentation/)
