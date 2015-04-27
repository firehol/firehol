# FireHOL Reference

## Primary commands

These are the primary packet filtering building blocks. Below each of these, sub-commands can be added.

command|man page|IPv4/6 variants|rule params|forbidden params|description
------:|:---:|:----------------:|:--------------:|:--------------:|:----------
interface|[firehol-interface(5)](firehol-interface.5.md)|Y|Y|inface outface|Define packet filtering blocks, protecting the firewall host itself
router|[firehol-router(5)](firehol-router.5.md)|Y|Y|-|Define packet filtering blocks, protecting other hosts from routed traffic

## sub-commands

The following commands can be used below **primary commands**.

command|man page|IPv4/6 variants|rule params|forbidden params|description
------:|:------:|:----------------:|:--------------:|:--------------:|:----------
server|[firehol-server(5)](firehol-server.5.md)|Y|Y|sport dport|A server is running on the `interface` or the protecting `router` hosts.
client|[firehol-client(5)](firehol-client.5.md)|Y|Y|sport dport|A client is running on the `interface` or the protecting `router` hosts.
group|[firehol-group(5)](firehol-group.5.md)|Y|Y|-|Define groups of commands that can share optional rule parameters. Groups can be nested.
policy|[firehol-policy(5)](firehol-policy.5.md)|N|N|-|Define the action to be applied on packets not matched by any `server` or `client` statements in the `interface` or `router`.
protection|[firehol-protection(5)](firehol-protection.5.md)|N|N|-|Examine incoming packets and filter out bad packets or limit request frequency per `interface` or `router`.
masquerade|[firehol-masquerade(5)](firehol-masquerade.5.md)|Y|Y|inface outface|Change the source IP of packets leaving `outface`, with the IP of the interface they are using to leave.
tcpmss|[firehol-tcpmss(5)](firehol-tcpmss.5.md)|Y|N|-|Set the MSS (Maximum Segment Size) of TCP SYN packets on the `outface` of routers.


## helpers

helper|man page|IPv4/6 variants|rule params|forbidden params|description
------:|:------:|:----------------:|:--------------:|:--------------:|:----------
action|[firehol-action(5)](firehol-action.5.md)|Y|Y|-|Define new actions that can differentiate the final action based on rules. `action` can be used to define traps.
blacklist|[firehol-blacklist(5)](firehol-blacklist.5.md)|Y|Y|-|Drop matching packets globally.
dnat|[firehol-nat(5)](firehol-nat.5.md)|Y|Y|-|Change the destination IP or port of packets received, to fixed values or fixed ranges. `dnat` can be used to implement load balancers.
dscp|[firehol-dscp(5)](firehol-dscp.5.md)|Y|Y|-|Set the DSCP field of packets.
ipset|[firehol-ipset(5)](firehol-ipset.5.md)|Y|N|-|Define ipsets. A wrapper for the system **ipset** command to add ipsets to a FireHOL firewall.
iptables ip6tables|[firehol-iptables(5)](firehol-iptables.5.md)|N|N|-|A wrapper for the system **iptables** command, to add custom iptables statements to a FireHOL firewall.
masquerade|[firehol-masquerade(5)](firehol-masquerade.5.md)|Y|Y|inface outface|Change the source IP of packets leaving one or more interfaces, with the IP of the interface they are using to leave.
redirect|[firehol-nat(5)](firehol-nat.5.md)|Y|Y|-|Redirect packets to a daemon running on the firewall host, possibly changing the destination port. `redirect` can support load balancers, if all the daemons run on localhost.
snat|[firehol-nat(5)](firehol-nat.5.md)|Y|Y|-|Change the source IP or port of packets leaving, to fixed values or fixed ranges.
tcpmss|[firehol-tcpmss(5)](firehol-tcpmss.5.md)|Y|N|-|Set the MSS (Maximum Segment Size) of TCP SYN packets routed through the firewall.
