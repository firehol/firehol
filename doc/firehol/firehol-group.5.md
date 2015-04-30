% firehol-group(5) FireHOL Reference | VERSION
% FireHOL Team
% Built DATE

# NAME

firehol-group - group commands with common options

<!--
contents-table:subcommand:group:keyword-firehol-group:Y:-:Define groups of commands that share optional rule parameters. Groups can be nested.
  -->

# SYNOPSIS

group with *rule-params*

group end

# DESCRIPTION

The `group` command allows you to group together multiple `client` and
`server` commands.

Grouping commands with common options (see
[firehol-params(5)][]) allows the option values
to be checked only once in the generated firewall rather than once per
service, making it more efficient.

Nested groups may be used.

# EXAMPLES

This:

~~~~

interface any world
  client all accept
  server http accept

  # Provide these services to trusted hosts only
  server "ssh telnet" accept src "192.0.2.1 192.0.2.2"
~~~~

can be replaced to produce a more efficient firewall by this:

~~~~

interface any world
  client all accept
  server http accept

  # Provide these services to trusted hosts only
  group with src "192.0.2.1 192.0.2.2"
    server telnet accept
    server ssh accept
  group end
~~~~


# SEE ALSO

* [firehol(1)][] - FireHOL program
* [firehol.conf(5)][] - FireHOL configuration
* [firehol-interface(5)][keyword-firehol-interface] - interface definition
* [firehol-router(5)][keyword-firehol-router] - router definition
* [firehol-params(5)][] - optional rule parameters
* [FireHOL Website](http://firehol.org/)
* [FireHOL Online PDF Manual](http://firehol.org/firehol-manual.pdf)
* [FireHOL Online Documentation](http://firehol.org/documentation/)
