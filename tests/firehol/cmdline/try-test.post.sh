#!/bin/sh

if ! grep -q "Restoring old firewall" "$runlog"
then
  echo "No restoring old firewall text"
  exit 1
fi

if ! grep -q "Restoring old firewall succeeded" "$runlog"
then
  echo "Restoring old firewall failed"
  exit 1
fi

exit 0
