#!/bin/sh

# Update autoconf scripts after a configure.ac change

if [ ! -f .gitignore -o ! -f sbin/firehol.in ]
then
  echo "Run as ./packaging/autogen.sh from a firehol git repository"
  exit 1
fi

autoreconf -ivf
