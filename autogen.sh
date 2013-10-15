#! /bin/sh
## `firehol/autogen.sh'
##

TOPDIR=$(pwd)

export TOPDIR

[ -f Makefile ] && make -i maintainer-clean

rm --verbose --recursive --force autom4te.cache
find ${TOPDIR} -name 'Makefile.in' -exec rm --verbose \{\} \;

aclocal --warnings=all -I m4
automake --verbose --add-missing --gnu
autoreconf --verbose --warnings=all

rm -f configure.scan *~ *.log
find ${TOPDIR} -name '*~' -exec rm -f '{}' \;

exit 0
