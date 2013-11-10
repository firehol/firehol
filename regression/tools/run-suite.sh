#!/bin/bash

if [ "$RUN_SUITE" != "OK" ]
then
  echo "Do not call this script directly"
  exit 1
fi


if [ ! -x "$1" ]
then
  echo "Executable program $1 not found"
  exit 1
fi
prog=$1
shift

if [ ! "$1" ]
then
  echo "No output directory specified"
  exit 1
fi

case "$1" in
   output/*)
      outdir="$1"
      shift
   ;;
   *)
      echo "Output directory must be output/something"
      exit 1
   ;;
esac

if ! MYTMP="`mktemp -d -t firehol-runsuite-XXXXXX`"
then
            echo >&2
            echo >&2
            echo >&2 "Cannot create temporary directory."
            echo >&2
            exit 1
fi

trap myexit SIGINT
trap myexit SIGHUP

here=`pwd`
rm -rf $outdir

clear_all() {
  cat > $MYTMP/reset <<-!
	*nat
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*mangle
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*filter
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	COMMIT
	!
  iptables-restore < $MYTMP/reset
  st1=$?

  cat > $MYTMP/reset <<-!
	*mangle
	:PREROUTING ACCEPT [0:0]
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	:POSTROUTING ACCEPT [0:0]
	COMMIT
	*filter
	:INPUT ACCEPT [0:0]
	:FORWARD ACCEPT [0:0]
	:OUTPUT ACCEPT [0:0]
	COMMIT
	!
  ip6tables-restore < $MYTMP/reset
  rm -f /var/run/firehol.lck
  rm -f $MYTMP/reset
  st2=$?

  if [ $st1 -ne 0 -o  $st2 -ne 0 ]
  then
    exit 2
  fi
}

myexit() {
  cd $here
  test -n "${SUDO_USER}" && chown -R ${SUDO_USER} output
  clear_all
  rm -rf $MYTMP
  exit 0
}

trap myexit SIGINT
trap myexit SIGHUP

cd $here
cd `dirname $prog` || myexit
progdir=`pwd`
progname=`basename $prog`
prog=$progdir/$progname

cd $here
> $MYTMP/list
if [ $# -eq 0 ]
then
  find tests -type f -name '*.conf' >> $MYTMP/list
fi

for i in "$@"
do
  if [ -f "$1" ]
  then
    echo "$i" >> $MYTMP/list
  elif [ -d "$i" ]
  then
    find "$i" -type f -name '*.conf' >> $MYTMP/list
  else
    echo "$i: Not a file or directory"
  fi
done

iptables-save > $MYTMP/save || myexit
ip6tables-save > $MYTMP/save6 || myexit

sort -u $MYTMP/list | sed -e 's;tests/;;' > $MYTMP/list.srt
mv $MYTMP/list.srt $MYTMP/list

while read testfile
do
  i=$(echo $testfile | sed -e s'/.conf$//')
  d=$(dirname $i)

  mkdir -p $outdir/tests/$d || myexit
  mkdir -p $outdir/ipv4/$d || myexit
  mkdir -p $outdir/ipv6/$d || myexit
  mkdir -p $outdir/ipv4-no-nat/$d || myexit
done < $MYTMP/list

while read testfile
do
  i=$(echo $testfile | sed -e s'/.conf$//')
  d=$(dirname $i)
  f=$(basename $i)
  cfgfile="$outdir/tests/$d/$f.conf"
  logfile="$outdir/tests/$d/$f.log"
  v4out="$outdir/ipv4/$d/$f.out"
  v6out="$outdir/ipv6/$d/$f.out"
  v4nnout="$outdir/ipv4-no-nat/$d/$f.out"
  v4aud="$outdir/ipv4/$d/$f.aud"
  v6aud="$outdir/ipv6/$d/$f.aud"
  v4nnaud="$outdir/ipv4-no-nat/$d/$f.aud"
  echo "  Running $cfgfile"
  if grep -q "^====" "$here/tests/$testfile"
  then
    audit="Y"
    sigsfile=$(echo $testfile | sed -e 's/.conf$/.sigs/')
    test -f "$here/tests/$sigsfile" && gpg --verify "$here/tests/$sigsfile" "$here/tests/$testfile"
    sed -e '/^====/,$d' "$here/tests/$testfile" > "$cfgfile"
    sed -e '1,/^==== IPv4 AUDITED O/d' \
        -e '/^==== IPv4 AUDITED END/,$d' "$here/tests/$testfile" \
       | tools/reorg-save > "$v4aud"
    tools/reorg-save -n "$v4aud" > "$v4nnaud"
    if grep -q IP6TABLES_CMD "$prog"
    then
      audit6="Y"
      sed -e '1,/^==== IPv6 AUDITED O/d' \
          -e '/^==== IPv6 AUDITED END/,$d' "$here/tests/$testfile" \
       | tools/reorg-save > "$v6aud"
    else
      audit6=""
    fi
  else
    audit=""
    audit6=""
    cp "$here/tests/$testfile" "$cfgfile"
  fi
  clear_all
  $prog "$cfgfile" start >> "$logfile" 2>&1
  iptables-save > "$v4out".tmp
  ip6tables-save > "$v6out".tmp
  sed -i -e 's/^FireHOL: //' "$logfile"
  sed -i -e '/^Processing file/s/ output\/[^/]*\// /' "$logfile"
  sed -i -e '/^SOURCE/s/ of output\/[^/]*\// of /' "$logfile"
  sed -i -e '/^COMMAND/s/ both iptables_cmd/ iptables_cmd/' "$logfile"
  sed -i -e 's;/sbin/iptables;iptables_cmd;' "$logfile"
  sed -i -e 's/-m state --state/-m conntrack --ctstate/g' "$logfile"
  tools/reorg-save "$v4out".tmp > "$v4out"
  tools/reorg-save -n "$v4out".tmp > "$v4nnout"
  tools/reorg-save "$v6out".tmp > "$v6out"
  rm -f "$v4out".tmp "$v6out".tmp
  auditfail=0
  if [ "$audit" ]; then
    if ! cmp "$v4out" "$v4aud"; then
      echo "Warning: ipv4 output differs from audited version"
      echo " v4result $v4out"
      echo "  v4audit $v4out"
      auditfail=1
    fi
  fi
  if [ "$audit6" ]; then
    if ! cmp "$v6out" "$v6aud"; then
      echo "Warning: ipv6 output differs from audited version"
      echo " v6result $v6out"
      echo "  v6audit $v6aud"
      auditfail=1
    fi
  fi
  if [ $auditfail -gt 0 ]; then
    echo "      log $logfile"
    echo ""
  fi
done < $MYTMP/list

iptables-restore < $MYTMP/save
ip6tables-restore < $MYTMP/save6
myexit
