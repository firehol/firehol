#!/bin/sh

grep -q "Clearing firewall" "$runlog" && exit 0
echo "No clearing firewall text"
exit 1
