#!/bin/sh

# Disable IPV4
cat - > /etc/firehol/firehol-defaults.conf <<-END-DEFAULTS
ENABLE_IPV4=0
END-DEFAULTS
