#!/bin/sh

grep -q "Clearing all QoS on all interfaces" "$runlog" && exit 0
echo "No clearing QOS text"
exit 1
