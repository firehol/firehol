#!/bin/bash

if ! MYTMP="`mktemp -d -t generate-XXXXXX`"
then
            echo >&2
            echo >&2
            echo >&2 "Cannot create temporary directory."
            echo >&2
            exit 1
fi

myexit() {
  rm -rf $MYTMP
  exit 0
}

trap myexit INT
trap myexit HUP
trap myexit 0

for i in $(awk '/^SERVICE / {print $2}' ../../../doc/services-db.data)
do
  j=$(echo $i | tr 'A-Z' 'a-z')
  grep -q "manually created" $j.conf || \
      sed "s|ZZZ|$i|g" 0-template-config > $j.conf
done

