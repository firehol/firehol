% firehol-ipset(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-ipset - configure ipsets

<!--
contents-table:helper:ipset:keyword-firehol-ipset:4/6:*all forbidden*:Define ipsets. A wrapper for the system ipset command to add ipsets to a FireHOL firewall.
  -->

# SYNOPSIS 

ipset *command* *name* *options*

# DESCRIPTION

FireHOL has an `ipset` helper. It is a wrapper around the real `ipset` command
and is handled internally within FireHOL in such a way so that the ipset
collections defined in the configuration will be activated before activating
the firewall.

FireHOL is also smart enough to restore the ipsets after a reboot, before it
restores the firewall, so that everything will work as seamlessly as possible.

The `ipset` helper has the same syntax with the real `ipset` command. So in
FireHOL you just add the `ipset` statements you need, and FireHOL will do the
rest.

Keep in mind that each `ipset` collection is either IPv4 or IPv6.
In FireHOL prefix `ipset` with either `ipv4` or `ipv6` and FireHOL will choose
the right IP version (there is also `ipset4` and `ipset6`).

Also, do not add `-!` to ipset statements given in `firehol.conf`. FireHOL will
batch import all ipsets and this option is not needed.

# FireHOL ipset extensions

The features below are extensions of `ipset` that can only be used from within
`firehol.conf`. They will not work on a terminal.

The FireHOL helper allows mass import of ipset collections from files. This is
done with `ipset addfile` command.

The `ipset addfile` command will get a filename, remove all comments (anything
after a `#` on the same line), trim any empty lines and spaces, and add all
the remaining lines to `ipset`, as if each line of the file was run with
`ipset add COLLECTION_NAME IP_FROM_FILE [other options]`.

The syntax of the `ipset addfile` command is:

~~~
 ipset addfile *name* [ip|net] *filename* [*other ipset add options*]
~~~

`name` is the collection to add the IPs.

`ip` is optional and will select all the lines of the file that do not contain
a `/`.

`net` is optional and will select all the lines of the file that contain a
`/`.

`filename` is the filename to read. You can give absolute filenames and
relative filenames (to `/etc/firehol`).

`other ipset add options` is whatever else `ipset add` supports, that you are
willing to give for each line.

The `ipset add` command implemented in FireHOL also allows you to give
multiple IPs separated by comma or enclosed in quotes and separated by space.


# EXAMPLES

~~~
 ipv4 ipset create badguys hash:ip
 ipv4 ipset add badguys 1.2.3.4
 ipv4 ipset addfile badguys file-with-the-bad-guys-ips.txt
 ...
 ipv4 blacklist full ipset:badguys

 # example with multiple IPs
 ipv4 ipset create badguys hash:ip
 ipv4 ipset add badguys 1.2.3.4,5.6.7.8,9.10.11.12 # << comma separated
 ipv4 ipset add badguys "11.22.33.44 55.66.77.88"  # << space separated in quotes
~~~


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [firehol-masquerade(5)][keyword-firehol-masquerade] - masquerade helper
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
* [NAT HOWTO](http://www.netfilter.org/documentation/HOWTO/NAT-HOWTO-6.html)
* [netfilter flow diagram][netfilter flow diagram]

[netfilter flow diagram]: http://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg
