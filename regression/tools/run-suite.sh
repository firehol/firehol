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

here=`pwd`
rm -rf $outdir

myexit() {
  cd $here
  test -n "${SUDO_USER}" && chown -R ${SUDO_USER} output
  test -f $MYTMP/save && iptables-restore < $MYTMP/save
  test -f $MYTMP/save6 && ip6tables-restore < $MYTMP/save6
  rm -rf $MYTMP
  rm -f /var/run/firehol.lck
  exit
}

trap myexit INT
trap myexit HUP
trap myexit 0

iptables-save > $MYTMP/save || exit
ip6tables-save > $MYTMP/save6 || exit

clear_all() {
  test -d $MYTMP || exit 3
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
  ip6tables-restore < $MYTMP/reset
  rm -f /var/run/firehol.lck
  rm -f $MYTMP/reset
  st2=$?

  if [ $st1 -ne 0 -o  $st2 -ne 0 ]
  then
    exit 2
  fi
}

cd $here
cd `dirname $prog` || exit
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

sort -u $MYTMP/list | sed -e 's;tests/;;' > $MYTMP/list.srt
mv $MYTMP/list.srt $MYTMP/list

while read testfile
do
  i=$(echo $testfile | sed -e s'/.conf$//')
  d=$(dirname $i)

  mkdir -p $outdir/tests/$d || exit
  mkdir -p $outdir/ipv4/$d || exit
  mkdir -p $outdir/ipv6/$d || exit
  mkdir -p $outdir/ipv4-no-nat/$d || exit
done < $MYTMP/list

audit_opts=""
if ! grep -q "^marksreset" "$prog"; then
  audit_opts="$audit_opts --noadvancedmark"
fi

while read testfile
do
  i=$(echo $testfile | sed -e s'/.conf$//')
  d=$(dirname $i)
  f=$(basename $i)
  origfile="tests/$d/$f.conf"
  cfgfile="$outdir/$origfile"
  logfile="$outdir/tests/$d/$f.log"
  v4out="$outdir/ipv4/$d/$f.out"
  v6out="$outdir/ipv6/$d/$f.out"
  v4nnout="$outdir/ipv4-no-nat/$d/$f.out"
  v4aud="$outdir/ipv4/$d/$f.aud"
  v6aud="$outdir/ipv6/$d/$f.aud"
  v4nnaud="$outdir/ipv4-no-nat/$d/$f.aud"

  echo "  Running $origfile"
  cp "$here/tests/$testfile" "$cfgfile"

  audit4=""
  if grep -q "audit_results_ipv4" "$here/tests/$testfile"
  then
    audit4="Y"
    sigsfile=$(echo $testfile | sed -e 's/.conf$/.sigs/')
    test -f "$here/tests/$sigsfile" && gpg --verify "$here/tests/$sigsfile" "$here/tests/$testfile"
    sed -ne '/audit_results_ipv4()/,/^}/p' "$here/tests/$testfile" \
         | sed -e '1d' -e '$d' \
         | tools/reorg-save $audit_opts > "$v4aud"
    tools/reorg-save $audit_opts --skipnat "$v4aud" > "$v4nnaud"
  fi

  audit6=""
  if grep -q "audit_results_ipv6" "$here/tests/$testfile"
  then
    if grep -q IP6TABLES_CMD "$prog"; then
      audit6="Y"
      sed -ne '/audit_results_ipv6()/,/^}/p' "$here/tests/$testfile" \
           | sed -e '1d' -e '$d' \
           | tools/reorg-save $audit_opts > "$v6aud"
    fi
  fi

  if grep -q "check_results_script" "$here/tests/$testfile"; then
    sed -ne '/check_results_script()/,/^}/p' "$here/tests/$testfile" > $MYTMP/auditscript
  else
    rm -f $MYTMP/auditscript
  fi

  clear_all
  $prog "$cfgfile" start >> "$logfile" 2>&1
  fhstatus=$?
  iptables-save > "$v4out".tmp
  ip6tables-save > "$v6out".tmp
  sed -i -e 's/^FireHOL: //' "$logfile"
  sed -i -e '/^Processing file/s/ output\/[^/]*\// /' "$logfile"
  sed -i -e '/^SOURCE/s/ of output\/[^/]*\// of /' "$logfile"
  sed -i -e '/^COMMAND/s/ both iptables_cmd/ iptables_cmd/' "$logfile"
  sed -i -e 's;/sbin/iptables;iptables_cmd;' "$logfile"
  sed -i -e 's/-m state --state/-m conntrack --ctstate/g' "$logfile"
  tools/reorg-save $audit_opts "$v4out".tmp > "$v4out"
  tools/reorg-save $audit_opts --skipnat "$v4out".tmp > "$v4nnout"
  tools/reorg-save $audit_opts "$v6out".tmp > "$v6out"
  rm -f "$v4out".tmp "$v6out".tmp
  auditrun=0
  auditfail=0
  if [ "$audit4" ]; then
    auditrun=$[auditrun+1]
    if ! cmp "$v4out" "$v4aud"; then
      echo "Warning: ipv4 output differs from audited version"
      echo " v4result $v4out"
      echo "  v4audit $v4aud"
      auditfail=$[auditfail+1]
    fi
  fi
  if [ "$audit6" ]; then
    auditrun=$[auditrun+1]
    if ! cmp "$v6out" "$v6aud"; then
      echo "Warning: ipv6 output differs from audited version"
      echo " v6result $v6out"
      echo "  v6audit $v6aud"
      auditfail=$[auditfail+1]
    fi
  fi
  if [ -f $MYTMP/auditscript ]; then
    auditrun=$[auditrun+1]
    echo "check_results_script $MYTMP $fhstatus $logfile $v4out $v6out" >> $MYTMP/auditscript
    bash $MYTMP/auditscript
    if [ $? -ne 0 ]; then
      auditfail=$[auditfail+1]
    fi
  else
    if [ $fhstatus -ne 0 ]; then
      echo "      bad status $fhstatus (or need check_results_script())"
      auditfail=$[auditfail+1]
    fi
  fi
  if [ $auditfail -gt 0 ]; then
    echo "      log $logfile"
    echo ""
  elif [ $auditrun -gt 0 ]; then
    echo "    audit passed $auditrun/$auditrun"
  fi
done < $MYTMP/list
echo "  Outdir: $outdir"
