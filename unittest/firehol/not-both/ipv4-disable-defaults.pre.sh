#!/bin/sh

# Disable IPV4
cat - >> $MYTMP/firehol/firehol-defaults.conf <<-END-DEFAULTS
ENABLE_IPV4=0
END-DEFAULTS
