#!/bin/sh

$script $1 try
status=$?
# Expect to fail (no way for user to confirm)
if [ $status -eq 1 ]
then
  exit 0
fi
echo "Status: $status"
exit 1
