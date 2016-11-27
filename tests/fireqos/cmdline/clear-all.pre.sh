#!/bin/sh

# Add a tc command so we can verify they are removed
/sbin/tc qdisc del dev veth0-ifb root
/sbin/tc qdisc add dev veth0-ifb root handle 1: stab linklayer adsl overhead 40 mtu 1492 htb default 5000 r2q 9

