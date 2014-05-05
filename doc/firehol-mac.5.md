% firehol-mac(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-mac - ensure source IP and source MAC address match

# SYNOPSIS

mac *IP* *macaddr*

# DESCRIPTION


Any `mac` commands will affect all traffic destined for the firewall
host, or to be forwarded by the host. They must be declared before the
first router or interface.

> **Note**
>
> There is also a `mac` parameter which allows matching MAC addresses
> within individual rules (see [firehol-params(5)][]).

The `mac` helper command DROPs traffic from the *IP* address that was not
sent using the *macaddr* specified.

When packets are dropped, a log is produced with the label "MAC
MISSMATCH" (sic.). `mac` obeys the default log limits (see
[LOGGING][] in [firehol-params(5)][]).

> **Note**
>
> This command restricts an IP to a particular MAC address. The same MAC
> address is permitted send traffic with a different IP.


# EXAMPLES

~~~~
mac 192.0.2.1    00:01:01:00:00:e6
mac 198.51.100.1 00:01:01:02:aa:e8
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-params(5)][] - optional rule parameters
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online HTML Manual](http://firehol.org/manual)
