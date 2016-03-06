% firehol-blacklist(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-blacklist - set up a unidirectional or bidirectional blacklist

<!--
contents-table:helper:blacklist:keyword-firehol-blacklist:Y:-:Drop matching packets globally.
  -->

# SYNOPSIS

{ blacklist | blacklist4 | blacklist6 } [ *type* ] [ inface *device* ] [ log *"text"* ] [ connlog *"text"* ] [ loglimit *"text"* ] [ accounting *accounting_name* ] *ip*... [ except *rule-params* [or *rule-params* [or ... ]]]


# DESCRIPTION


The `blacklist` helper command creates a blacklist for the *ip* list given
(which can be in quotes or not).

If the type `full` or `all` is supplied (or no type at all), a bidirectional
*stateless* blacklist will be generated. The firewall will REJECT all traffic
going to the IP addresses and DROP all traffic coming from them.

If the type `stateful` is supplied, a bidirectional *stateful* blacklist will
be generated. The firewall will REJECT all traffic going to the IP addresses
and DROP all traffic coming from them.

The differences between `full` and `stateful` are:

1. `stateful` is resource efficient, since only the packets that initiate connections are examined. Established connections will never be re-tested against the blacklist.

2. when using `full` and an ipset is updated to match the IP of an established connection, this established connection will immediately be blocked too.


If the type `input` or `him`, `her`, `it`, `this`, `these` is supplied,
a unidirectional *stateful* blacklist will be generated. Connections can be
established to such IP addresses, but the IP addresses will not be able to
connect to the firewall or hosts protected by it.

Using `log` (log every packet), `connlog` (log connections once),
or `loglimit` (log packets according to global throttling settings),
the `text` will be logged when matching packets are found.

Using `inface`, the blacklist will be created on the interface `device` only
(this includes forwarded traffic).

`accounting` will update the NFACCT accounting with the name given.

If the keyword `except` is found, then all the parameters following it are
rules to match packets that should excluded from the blacklist (i.e. they
are a whitelist for this blacklist). See [firehol-params(5)][] for more
details.

Blacklists must be declared before the first router or interface.

IP Lists for abuse, malware, attacks, proxies, anonymizers, etc can be
downloaded with the contrib/update-ipsets.sh script. Information about the
supported IP Lists can be found at [FireHOL IP Lists](http://iplists.firehol.org/)

# EXAMPLES

~~~~
blacklist full 192.0.2.1 192.0.2.2
blacklist input "192.0.2.3 192.0.2.4"
blacklist full inface eth0 log "BADGUY" 192.0.1.1 192.0.1.2
~~~~

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [FireHOL IP Lists](http://iplists.firehol.org/)
