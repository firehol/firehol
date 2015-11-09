dnl Process this file with autoconf to produce a configure script.

AC_PREREQ([2.63])
AC_INIT([firehol],[m4_esyscmd([./packaging/packver])],[firehol-devs@lists.firehol.org])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([autotool])
AC_CONFIG_SRCDIR([sbin/firehol.in])
AC_CONFIG_SRCDIR([sbin/fireqos.in])
AC_CONFIG_SRCDIR([sbin/link-balancer.in])
AC_CONFIG_SRCDIR([sbin/update-ipsets.in])
AC_CONFIG_SRCDIR([sbin/vnetbuild.in])
AM_INIT_AUTOMAKE([gnu])
AM_MAINTAINER_MODE([disable])

dnl Checks for programs.
AC_PROG_MAKE_SET

AX_FIREHOL_AUTOSAVE()
AX_FIREHOL_AUTOSAVE6()

AC_ARG_ENABLE([doc],
              [AS_HELP_STRING([--disable-doc], [disable doc installation @<:@enabled@:>@])],
              ,
              [enable_doc="yes"])
AM_CONDITIONAL([ENABLE_DOC], [test "${enable_doc}" = "yes"])

AC_ARG_ENABLE([man],
              [AS_HELP_STRING([--disable-man], [disable manpage installation @<:@enabled@:>@])],
              ,
              [enable_man="yes"])
AM_CONDITIONAL([ENABLE_MAN], [test "${enable_man}" = "yes"])

AC_ARG_ENABLE([iprange],
              [AS_HELP_STRING([--disable-iprange], [disable iprange installation @<:@enabled@:>@])],
              ,
              [enable_iprange="yes"])
AM_CONDITIONAL([ENABLE_IPRANGE], [test "${enable_iprange}" = "yes"])

if test x"$USE_MAINTAINER_MODE" = xyes; then
AC_MSG_NOTICE(***************** MAINTAINER MODE *****************)
PACKAGE_BUILT_DATE=$(date '+%d %b %Y')
AX_PROG_XMLLINT([--nonet])
AX_PROG_PANDOC([ -f markdown --toc -N],
               [ -f markdown -t html --email-obfuscation=references --toc -c firehol-manual.css],
               [ -f markdown -t man -s])
dnl pandoc 1.12.2.1+ is required to process github markdown
dnl   Debian jessie and Ubuntu trusty packages are OK
AX_CHECK_PANDOC_MIN([1.12.2.1],[],[AC_MSG_ERROR(could not find required version of pandoc)])
AX_CHECK_PANDOC_OUTPUT()
AC_SUBST(PACKAGE_BUILT_DATE)
AC_SUBST(PANDOC_VERSION)
AC_CONFIG_FILES([doc/tools/pandoc-post], [chmod +x doc/tools/pandoc-post])
AC_MSG_NOTICE(***************************************************)
else
  if test ! -f doc/service-links; then
    if test x"$enable_doc" = xyes -o x"$enable_man" = xyes; then
      AC_MSG_ERROR([docs not built, use '--disable-doc --disable-man' or --enable-maintainer-mode])
    fi
  fi
fi

FIREHOL_CONFIG_DIR=$(eval echo "$sysconfdir/firehol" | sed -e 's|^NONE|/usr/local|')
AC_SUBST(FIREHOL_CONFIG_DIR)

AX_CHECK_PROG([ADNSHOST], [adnshost], [])
AX_CHECK_PROG([AGGREGATE], [aggregate], [])
AX_CHECK_PROG([AGGREGATE], [aggregate-flim], [])
AX_NEED_PROG([AGGREGATE], [cat], [])
AX_NEED_PROG([BRCTL], [brctl], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CHMOD], [chmod], [])
AX_NEED_PROG([CHOWN], [chown], [])
AX_NEED_PROG([CP], [cp], [])
AX_NEED_PROG([CURL], [curl], [])
AX_NEED_PROG([CUT], [cut], [])
AX_NEED_PROG([DATE], [date], [])
AX_NEED_PROG([DIFF], [diff], [])
AX_NEED_PROG([DIRNAME], [dirname], [])
AX_NEED_PROG([ENV], [env], [])
AX_NEED_PROG([EXPR], [expr], [])
AX_NEED_PROG([FIND], [find], [])
AX_NEED_PROG([FLOCK], [flock], [])
AX_NEED_PROG([FOLD], [fold], [])
AX_NEED_PROG([FUNZIP], [funzip], [])
AX_CHECK_PROG([GAWK], [gawk], [])
AX_CHECK_PROG([GAWK], [mawk], [])
AX_CHECK_PROG([GAWK], [nawk], [])
AX_NEED_PROG([GAWK], [awk], [])
AX_NEED_GREP()
AX_CHECK_PROG([GIT], [git], [])
AX_NEED_EGREP()
AX_NEED_PROG([HEAD], [head], [])
AX_NEED_PROG([HOST], [host], [])
AX_NEED_PROG([HOSTNAME_CMD], [hostname], [])
AX_CHECK_PROG([MODPROBE], [modprobe], [-q], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([MODPROBE], [insmod], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([RMMOD], [rmmod], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP6TABLES], [ip6tables], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP], [ip], [])
AX_NEED_PROG([IP6TABLES_RESTORE], [ip6tables-restore], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP6TABLES_SAVE], [ip6tables-save], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES], [iptables], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES_RESTORE], [iptables-restore], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES_SAVE], [iptables-save], [], [$PATH:/sbin:/usr/sbin])
AX_CHECK_PROG([JQ], [jq], [])
AX_NEED_PROG([LN], [ln], [])
AX_NEED_PROG([LOGGER], [logger], [])
AX_NEED_PROG([LS], [ls], [])
AX_NEED_PROG([LSMOD], [lsmod], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_NEED_PROG([MKTEMP], [mktemp], [])
AX_NEED_PROG([MV], [mv], [])
AX_CHECK_PROG([NEATO], [neato], [])
AX_CHECK_PROG([PAGER], [pager], [])
AX_CHECK_PROG([PAGER], [less], [])
AX_CHECK_PROG([PAGER], [more], [])
AX_NEED_PROG([PAGER], [cat], [])
AX_CHECK_PROG([PV], [pv], [])
AX_CHECK_PROG([RENICE], [renice], [])
AX_NEED_PROG([RM], [rm], [])
AX_NEED_SED()
AX_NEED_PROG([SEQ], [seq], [])
AX_CHECK_PROG([SH], [sh], [])
AX_CHECK_PROG([SH], [bash], [])
AX_NEED_PROG([SH], [ksh], [])
AX_NEED_PROG([SORT], [sort], [])
AX_NEED_PROG([SLEEP], [sleep], [])
AX_NEED_PROG([SS], [ss], [])
AX_NEED_PROG([SYSCTL], [sysctl], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([TAIL], [tail], [])
AX_NEED_PROG([TOUCH], [touch], [])
AX_NEED_PROG([TR], [tr], [])
AX_NEED_PROG([UNAME], [uname], [])
AX_NEED_PROG([UNIQ], [uniq], [])
AX_NEED_PROG([UNZIP], [unzip], [])
AX_CHECK_PROG([ZCAT], [gzcat], [])
AX_CHECK_PROG([ZCAT], [gunzip], [-c])
AX_NEED_PROG([ZCAT], [gzip], [-d -c])
AX_CHECK_PROG([NFACCT], [nfacct], [])
AX_CHECK_PROG([IPSET], [ipset], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([STTY], [stty], [])
AX_CHECK_PROG([TPUT], [tput], [])
AX_NEED_PROG([WC], [wc], [])
AX_NEED_PROG([HOSTNAMECMD], [hostname], [])
AX_NEED_PROG([TC], [tc], [], [$PATH:/sbin:/usr/sbin])
AX_CHECK_PROG([TCPDUMP], [tcpdump], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([PING], [ping], [])
AX_NEED_PROG([PING6], [ping6], [])
AX_NEED_PROG([TRACEROUTE], [traceroute], [])
AX_CHECK_PROG([SCREEN], [screen], [])
AX_CHECK_PROG([WGET], [wget], [])
AX_CHECK_PROG([WHOIS], [whois], [])

AUTOCONF_RUN=Y
AC_SUBST(AUTOCONF_RUN)

if test x"$enable_iprange" = xyes; then
dnl We are installing it ourselves
d=$(eval echo "$sbindir")
if test x$d = xNONE/sbin; then
IPRANGE=$(eval echo "$prefix/sbin/iprange" | sed -e 's|^NONE|/usr/local|')
else
IPRANGE=$(eval echo "$sbindir/iprange" | sed -e 's|^NONE|/usr/local|')
fi
AC_SUBST(IPRANGE)

AC_PROG_CC
AC_HEADER_STDC
AX_PTHREAD
AC_CHECK_HEADERS(sys/socket.h,,AC_MSG_ERROR(sys/socket.h missing))
AC_CHECK_HEADERS(netinet/in.h,,AC_MSG_ERROR(netinet/in.h missing))
AC_CHECK_HEADERS(arpa/inet.h,,AC_MSG_ERROR(arpa/inet.h missing))
AC_CHECK_HEADERS(sys/time.h,,AC_MSG_ERROR(sys/time.h missing))
AC_CHECK_FUNC(htonl,,AC_MSG_ERROR(htonl() not found))
else
dnl Try and detect it on the system anyway
AX_CHECK_PROG([IPRANGE], [iprange], [])

dnl Horrible but how else to make the compiler completely optional?
AM_CONDITIONAL([AMDEP], false)
AM_CONDITIONAL([am__fastdepCC], false)
fi

AC_CONFIG_FILES([
	Makefile
	sbin/Makefile
	m4/Makefile
	doc/Makefile
	doc/firehol/Makefile
	doc/fireqos/Makefile
	doc/vnetbuild/Makefile
	examples/Makefile
	etc/Makefile
	contrib/Makefile
	packaging/Makefile
	])

AC_CONFIG_FILES([sbin/firehol], [chmod +x sbin/firehol])
AC_CONFIG_FILES([sbin/fireqos], [chmod +x sbin/fireqos])
AC_CONFIG_FILES([sbin/link-balancer], [chmod +x sbin/link-balancer])
AC_CONFIG_FILES([sbin/update-ipsets], [chmod +x sbin/update-ipsets])
AC_CONFIG_FILES([sbin/vnetbuild], [chmod +x sbin/vnetbuild])

AC_OUTPUT
