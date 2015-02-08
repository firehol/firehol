% firehol-version(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-version - set version number of configuration file

# SYNOPSIS

version 6

# DESCRIPTION

The `version` helper command states the configuration file version.

If the value passed is newer than the running version of FireHOL
supports, FireHOL will not run.

You do not have to specify a version number for a configuration file,
but by doing so you will prevent FireHOL trying to process a file which
it cannot handle.

The value that FireHOL expects is increased every time that the
configuration file format changes.

> **Note**
>
> If you pass version 5 to FireHOL, it will disable IPv6 support and
> warn you that you must update your configuration.

# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
