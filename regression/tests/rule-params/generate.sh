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

i=0
IFS='|'
sed -e '/^#/d' -e 's/		*/|/g' 1-common | \
while read v4 v6
do
  i=$(expr $i + 1)
  j=$i
  if [ $i -lt 10 ]; then j=0$i; fi
  if [ $i -lt 100 ]; then j=0$j; fi

  w1=$(echo "$v4" | cut -f1 -d' ')
  if [ "$(echo $v4 | grep '\<not\>')" ]
  then
    w="$w1-not"
  else
    w="$w1"
  fi

  sed -e "s/ZZ4/$v4/g" -e "s/ZZ6/$v6/g" 0-template-config > rules-$j-$w.conf
done

IFS='|'
sed -e '/^#/d' -e 's/		*/|/g' 2-router | \
while read v4 v6
do
  i=$(expr $i + 1)
  j=$i
  if [ $i -lt 10 ]; then j=0$i; fi
  if [ $i -lt 100 ]; then j=0$j; fi

  w1=$(echo "$v4" | cut -f1 -d' ')
  if [ "$(echo $v4 | grep '\<not\>')" ]
  then
    w="$w1-not"
  else
    w="$w1"
  fi

  sed -e '/INTERFACE/,/END INTERFACE/d' -e "s/ZZ4/$v4/g" -e "s/ZZ6/$v6/g" 0-template-config > rules-$j-$w.conf
done

IFS='|'
sed -e '/^#/d' -e 's/		*/|/g' 3-interface | \
while read v4 v6
do
  i=$(expr $i + 1)
  j=$i
  if [ $i -lt 10 ]; then j=0$i; fi
  if [ $i -lt 100 ]; then j=0$j; fi

  w1=$(echo "$v4" | cut -f1 -d' ')
  if [ "$(echo $v4 | grep '\<not\>')" ]
  then
    w="$w1-not"
  else
    w="$w1"
  fi

  sed -e '/ROUTER/,/END ROUTER/d' -e "s/ZZ4/$v4/g" -e "s/ZZ6/$v6/g" 0-template-config > rules-$j-$w.conf
done
