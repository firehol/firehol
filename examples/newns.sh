#!/bin/sh

#
# Create a new private user, network and mount namespace, set up a basic
# environment and run the specified command (or a shell by default).
#
# By running this command you will appear to be root in an self-contained
# environment (much like a docker container), making it possible to experiment
# with the firewall tools as a normal user.
#

uid=$(id -r -u)

# https://github.com/bazelbuild/bazel/issues/433
if [ -f /proc/sys/kernel/unprivileged_userns_clone ]
then
  userns_disabled=$(/sbin/sysctl kernel.unprivileged_userns_clone | grep " 0$")
  if [ "$userns_disabled" -a "$uid" != "0" ]
  then
    echo "Must have userns enabled"
    echo ""
    echo "To fix it, try:"
    echo "  sudo sysctl kernel.unprivileged_userns_clone=1"
    exit 1
  fi
fi

if [ "$1" = "--fake-proc" ]
then
  if [ "$IN_PRIVATE_NS" = "" ]
  then
    echo "Only use --fake-proc from within a namespace"
    exit 1
  fi
  # /proc/net/ip_tables_names is read-only for the real root in kernels
  # up to and possibly beyond 4.3, so we may not be able to access it.
  #
  # This file just contains the well known list of tables, depending
  # on which modules are loaded.
  #
  # It is relied on by firehol but also by iptables-save and iptables-restore
  #
  # We recreate the whole of proc using bind mounts, except the two files
  # which we make with our known values. We then bind our proc over the
  # original and everything just works...
  #
  # Because we are in separate user and mount namespaces, none of this
  # interferes with the running system.
  #
  # http://lists.linuxfoundation.org/pipermail/containers/2014-June/034682.html
  # https://lists.linuxcontainers.org/pipermail/lxc-users/2014-November/008099.html
  mkdir /var/run/fake-proc
  mkdir /var/run/fake-proc/net
  ls /proc | while read name
  do
    case $name in
       $$)
         mkdir /var/run/fake-proc/$name
         mount -o rbind /proc/$name /var/run/fake-proc/$name
       ;;

       [0-9]*)
         :
       ;;

       net)
         :
       ;;

       *)
         if [ -d /proc/$name ]
         then
           mkdir /var/run/fake-proc/$name
           mount -o rbind /proc/$name /var/run/fake-proc/$name
         else
           touch /var/run/fake-proc/$name
           mount -o rbind /proc/$name /var/run/fake-proc/$name
         fi
       ;;
    esac
  done

  ls /proc/net | while read name
  do
    if [ "$name" = "ip_tables_names" ]
    then
      lsmod | grep "^iptable_" | cut -f2 -d_ | \
              cut -f1 -d' ' > /var/run/fake-proc/net/$name
      chmod 444 /var/run/fake-proc/net/$name
    elif [ "$name" = "ip6_tables_names" ]
    then
      lsmod | grep "^ip6table_" | cut -f2 -d_ | \
              cut -f1 -d' ' > /var/run/fake-proc/net/$name
      chmod 444 /var/run/fake-proc/net/$name
    elif [ -d /proc/net/$name ]
    then
      mkdir /var/run/fake-proc/net/$name
      mount -o rbind /proc/net/$name /var/run/fake-proc/net/$name
    else
      touch /var/run/fake-proc/net/$name
      mount -o rbind /proc/net/$name /var/run/fake-proc/net/$name
    fi
  done

  mount -o rbind  /var/run/fake-proc /proc

  # Check it all worked
  cat /proc/net/ip_tables_names > /dev/null || exit 1
  cat /proc/net/ip6_tables_names > /dev/null || exit 1
elif [ "$IN_PRIVATE_NS" = "" ]
then
  # Unshare namespace and map root first (unshare -r), so that
  # the /proc/net 0440 files will be available when we create a
  # new network namespace (unshare -n)
  IN_PRIVATE_NS=1 exec unshare -r unshare -n -m $0 --stage2 "$@"
elif [ "${uid}" = 0 ]
then
  shift
  mount -o rbind /sys /sys
  mount -t tmpfs tmpfs /var/run
  mount -t tmpfs tmpfs /var/spool
  mkdir /var/run/netns
  if [ $# -ge 1 ]
  then
    exec "$@"
  else
    exec $SHELL
  fi
else
  echo Unshare failed
  exit 1
fi
