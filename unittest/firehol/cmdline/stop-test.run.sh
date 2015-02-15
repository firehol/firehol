#!/bin/sh

$script stop
status=$?
if [ $status -eq 1 ]
then
  exit 0
fi
echo "Status: $status"
exit 1
