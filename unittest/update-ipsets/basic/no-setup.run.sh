#!/bin/sh

$kcov $script
status=$?
if [ $status -eq 0 ]
then
  exit 0
fi
echo "Status: $status"
exit 1
