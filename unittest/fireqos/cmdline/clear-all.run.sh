#!/bin/sh

$script clear_all_qos
status=$?
if [ $status -eq 0 ]
then
  exit 0
fi
echo "Status: $status"
exit 1
