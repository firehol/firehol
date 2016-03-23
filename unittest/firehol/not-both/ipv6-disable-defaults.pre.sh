#!/bin/sh

# Disable IPV6
cat - >> $MYTMP/firehol/firehol-defaults.conf <<-END-DEFAULTS
ENABLE_IPV6=0
END-DEFAULTS
