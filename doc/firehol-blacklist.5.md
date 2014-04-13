% firehol-blacklist(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-blacklist - set up a unidirectional or bidirectional blacklist

# SYNOPSIS

blacklist [ full | all ] *ip*...

blacklist { input | them | him | her | it | this | these } *ip*...

# DESCRIPTION


The `blacklist` helper command creates a blacklist for the *ip* list given
(which can be in quotes or not).

If the type `full` or one of its aliases is supplied, or no type is
given, a bidirectional stateless blacklist will be generated. The
firewall will REJECT all traffic going to the IP addresses and DROP all
traffic coming from them.

If the type `input` or one of its aliases is supplied, a unidirectional
stateful blacklist will be generated. Connections can be initiated to
such IP addresses, but the IP addresses will not be able to connect to
the firewall or hosts protected by it.

Any blacklists will affect all router and interface definitions. They
must be declared before the first router or interface.


# EXAMPLES

~~~~

blacklist full 192.0.2.1 192.0.2.2
blacklist input "192.0.2.3 192.0.2.4"
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
