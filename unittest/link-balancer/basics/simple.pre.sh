#!/bin/sh

# Bring up the veth0 and veth1 devices created for us and give them
# an IP address each

ip addr add 10.0.0.1/24 dev veth0
ip addr add 10.0.1.1/24 dev veth1

ip link set veth0 up
ip link set veth1 up
