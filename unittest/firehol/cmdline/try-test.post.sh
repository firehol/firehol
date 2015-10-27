#!/bin/sh

grep -q "Restoring old firewall.*OK" "$runlog" && exit 0
echo "No restoring old firewall text"
exit 1
