#!/bin/sh

# Add some iptables commands so we can verify they are retained

iptables -A INPUT -j DROP
iptables -A FORWARD -j DROP
iptables -A OUTPUT -j DROP

ip6tables -A INPUT -j DROP
ip6tables -A FORWARD -j DROP
ip6tables -A OUTPUT -j DROP
