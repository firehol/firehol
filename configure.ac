dnl Process this file with autoconf to produce a configure script.

AC_PREREQ([2.63])

dnl Package version
define([VERSION_MAJOR], [3])
define([VERSION_MINOR], [0])
define([VERSION_FIX], [3])
define([VERSION_SUFFIX], [_master])

dnl Required program versions
define([MIN_IPRANGE_VERSION], [1.0.2])
define([MIN_BASH_VERSION], [4.0])
define([MIN_PANDOC_VERSION], [1.12.2.1])

define([VERSION_NUMBER], VERSION_MAJOR[.]VERSION_MINOR[.]VERSION_FIX)
AC_INIT([firehol],VERSION_NUMBER[]VERSION_SUFFIX,[firehol-devs@lists.firehol.org])

AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([autotool])
AC_CONFIG_SRCDIR([sbin/firehol])
AM_INIT_AUTOMAKE([tar-ustar])
AM_MAINTAINER_MODE([disable])

dnl Checks for programs.
AC_PROG_MAKE_SET

dnl Check for functioning symbolic links
AC_PROG_LN_S

AM_CONDITIONAL([GIT_TREE], [test -f README.md])

AX_FIREHOL_AUTOSAVE()
AX_FIREHOL_AUTOSAVE6()

AC_ARG_ENABLE([filename-versions],
              [AS_HELP_STRING([--disable-filename-versions], [no versions on executable filenames @<:@enabled@:>@])],
              ,
              [enable_filename_versions="yes"])
AM_CONDITIONAL([FILENAME_VERSIONS],[test "${enable_filename_versions}" = "yes"])

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

AC_ARG_ENABLE([firehol],
              [AS_HELP_STRING([--disable-firehol], [disable firehol installation @<:@enabled@:>@])],
              ,
              [enable_firehol="yes"])
AM_CONDITIONAL([ENABLE_FIREHOL], [test "${enable_firehol}" = "yes"])

AC_ARG_ENABLE([firehol-wizard],
              [AS_HELP_STRING([--disable-firehol-wizard], [disable firehol-wizard @<:@enabled@:>@])],
              ,
              [enable_firehol_wizard="yes"])
AM_CONDITIONAL([ENABLE_FIREHOL_WIZARD], [test "${enable_firehol_wizard}" = "yes"])

AC_ARG_ENABLE([fireqos],
              [AS_HELP_STRING([--disable-fireqos], [disable fireqos installation @<:@enabled@:>@])],
              ,
              [enable_fireqos="yes"])
AM_CONDITIONAL([ENABLE_FIREQOS], [test "${enable_fireqos}" = "yes"])

AC_ARG_ENABLE([link-balancer],
              [AS_HELP_STRING([--disable-link-balancer], [disable link-balancer installation @<:@enabled@:>@])],
              ,
              [enable_link_balancer="yes"])
AM_CONDITIONAL([ENABLE_LINK_BALANCER], [test "${enable_link_balancer}" = "yes"])

AC_ARG_ENABLE([update-ipsets],
              [AS_HELP_STRING([--disable-update-ipsets], [disable update-ipsets installation @<:@enabled@:>@])],
              ,
              [enable_update_ipsets="yes"])
AM_CONDITIONAL([ENABLE_UPDATE_IPSETS], [test "${enable_update_ipsets}" = "yes"])

AC_ARG_ENABLE([vnetbuild],
              [AS_HELP_STRING([--disable-vnetbuild], [disable vnetbuild installation @<:@enabled@:>@])],
              ,
              [enable_vnetbuild="yes"])
AM_CONDITIONAL([ENABLE_VNETBUILD], [test "${enable_vnetbuild}" = "yes"])

AC_ARG_ENABLE([ipv4],
              [AS_HELP_STRING([--disable-ipv4], [disable ipv4 @<:@enabled@:>@])],
              ,
              [enable_ipv4="yes"])
AM_CONDITIONAL([ENABLE_IPV4], [test "${enable_ipv4}" = "yes"])

AC_ARG_ENABLE([ipv6],
              [AS_HELP_STRING([--disable-ipv6], [disable ipv6 @<:@enabled@:>@])],
              ,
              [enable_ipv6="yes"])
AM_CONDITIONAL([ENABLE_IPV6], [test "${enable_ipv6}" = "yes"])

AC_ARG_VAR([IPRANGE_VERSION], [version of iprange when cross-compiling])
AC_ARG_VAR([BASH_VERSION], [version of bash when cross-compiling])

if test x"$enable_ipv4" = xyes; then
IPV4_ENABLED=1
else
IPV4_ENABLED=0
fi
AC_SUBST(IPV4_ENABLED)

if test x"$enable_ipv6" = xyes; then
IPV6_ENABLED=1
else
IPV6_ENABLED=0
fi
AC_SUBST(IPV6_ENABLED)

if test x"$USE_MAINTAINER_MODE" = xyes; then
AC_MSG_NOTICE(***************** MAINTAINER MODE *****************)
PACKAGE_BUILT_DATE=$(date '+%d %b %Y')
AX_PROG_XMLLINT([--nonet])

AX_PROG_PANDOC([ -f markdown --toc -N],
               [ -f markdown -t html --email-obfuscation=references --toc -c firehol-manual.css],
               [ -f markdown -t man -s])
AX_CHECK_MINVER([PANDOC_VERSION], MIN_PANDOC_VERSION, [$PANDOC],
                [-v | head -n 1 | cut -d' ' -f2],
                [], [AC_MSG_ERROR(could not find required version of pandoc)])
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

PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin

AX_NEED_PROG([BASH_SHELL_PATH], [bash], [])
AX_CHECK_MINVER([BASH_VERSION_PATH], MIN_BASH_VERSION, [$BASH_SHELL_PATH],
                [--version | sed -n -e '1{s/.* \(.*\..*\)\..*/\1/p;}'],
                [], [AC_MSG_ERROR(could not find required version of bash)])
AX_NEED_SED()

if test x"$enable_ipv6" = xyes; then
AX_CHECK_PING_IPV6()
fi

dnl --- OUTPUT OF './packaging/firehol/gen-config-detect sbin/*.in' BEGIN   ---
if test x"$MAKEDIST_BUILD_ONLY" != xyes; then
AX_NEED_EGREP()
AX_NEED_GREP()
AX_NEED_SED()
AX_NEED_PROG([READLINK], [readlink], [])
AX_NEED_PROG([DIRNAME], [dirname], [])
AX_NEED_PROG([BASENAME], [basename], [])
if test x"$enable_firehol" = xyes; then
AC_MSG_NOTICE([Detecting commands for firehol])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CHMOD], [chmod], [])
AX_NEED_PROG([CHOWN], [chown], [])
AX_NEED_PROG([CP], [cp], [])
AX_NEED_PROG([CUT], [cut], [])
if test x"$enable_firehol_wizard" = xyes; then
AX_NEED_PROG([DATE], [date], [])
fi
AX_NEED_PROG([EXPR], [expr], [])
AX_NEED_PROG([FIND], [find], [])
AX_NEED_PROG([FLOCK], [flock], [])
AX_NEED_PROG([FOLD], [fold], [])
AX_NEED_PROG([HEAD], [head], [])
if test x"$enable_firehol_wizard" = xyes; then
AX_NEED_PROG([HOSTNAMECMD], [hostname], [])
fi
if test x"$enable_firehol_wizard" = xyes; then
AX_NEED_PROG([IP], [ip], [])
fi
if test x"$enable_ipv6" = xyes; then
AX_CHECK_PROG([IP6TABLES], [ip6tables], [])
fi
if test x"$enable_ipv6" = xyes; then
AX_CHECK_PROG([IP6TABLES_RESTORE], [ip6tables-restore], [])
fi
if test x"$enable_ipv6" = xyes; then
AX_CHECK_PROG([IP6TABLES_SAVE], [ip6tables-save], [])
fi
AX_CHECK_PROG([IPRANGE], [iprange], [])
AX_CHECK_PROG([IPSET], [ipset], [])
if test x"$enable_ipv4" = xyes; then
AX_CHECK_PROG([IPTABLES], [iptables], [])
fi
if test x"$enable_ipv4" = xyes; then
AX_CHECK_PROG([IPTABLES_RESTORE], [iptables-restore], [])
fi
if test x"$enable_ipv4" = xyes; then
AX_CHECK_PROG([IPTABLES_SAVE], [iptables-save], [])
fi
AX_NEED_PROG([LOGGER], [logger], [])
AX_NEED_PROG([LS], [ls], [])
AX_NEED_PROG([LSMOD], [lsmod], [])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_NEED_PROG([MKTEMP], [mktemp], [])
AX_CHECK_PROG([MODPROBE], [modprobe], [-q])
AX_CHECK_PROG([MODPROBE], [insmod], [])
AX_CHECK_PROG([MORE], [pager], [])
AX_CHECK_PROG([MORE], [less], [])
AX_CHECK_PROG([MORE], [more], [])
AX_NEED_PROG([MORE], [cat], [])
AX_NEED_PROG([MV], [mv], [])
AX_CHECK_PROG([NFACCT], [nfacct], [])
AX_CHECK_PROG([RENICE], [renice], [])
if test x"$RENICE" = x; then
AC_SUBST([RENICE], [:])
fi
AX_NEED_PROG([RM], [rm], [])
AX_NEED_PROG([SLEEP], [sleep], [])
AX_NEED_PROG([SORT], [sort], [])
if test x"$enable_firehol_wizard" = xyes; then
AX_NEED_PROG([SS], [ss], [])
fi
AX_CHECK_PROG([STTY], [stty], [])
if test x"$STTY" = x; then
AC_SUBST([STTY], [:])
fi
AX_NEED_PROG([SYSCTL], [sysctl], [])
AX_NEED_PROG([TAIL], [tail], [])
AX_NEED_PROG([TOUCH], [touch], [])
AX_CHECK_PROG([TPUT], [tput], [])
AX_NEED_PROG([TR], [tr], [])
AX_NEED_PROG([UNAME], [uname], [])
AX_NEED_PROG([UNIQ], [uniq], [])
AX_NEED_PROG([WC], [wc], [])
AX_CHECK_PROG([ZCAT], [zcat], [])
AX_CHECK_PROG([ZCAT], [gzcat], [])
AX_NEED_PROG([ZCAT], [gzip], [-dc])
fi
if test x"$enable_fireqos" = xyes; then
AC_MSG_NOTICE([Detecting commands for fireqos])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CUT], [cut], [])
AX_NEED_PROG([DATE], [date], [])
AX_NEED_PROG([FLOCK], [flock], [])
AX_CHECK_PROG([GAWK], [gawk], [])
AX_NEED_PROG([GAWK], [awk], [])
AX_NEED_PROG([IP], [ip], [])
AX_NEED_PROG([LOGGER], [logger], [])
AX_NEED_PROG([LS], [ls], [])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_CHECK_PROG([MODPROBE], [modprobe], [-q])
AX_NEED_PROG([MODPROBE], [insmod], [])
AX_NEED_PROG([MV], [mv], [])
AX_NEED_PROG([RM], [rm], [])
AX_NEED_PROG([RMMOD], [rmmod], [])
AX_NEED_PROG([SEQ], [seq], [])
AX_NEED_PROG([SLEEP], [sleep], [])
AX_NEED_PROG([TAIL], [tail], [])
AX_NEED_PROG([TC], [tc], [])
AX_CHECK_PROG([TCPDUMP], [tcpdump], [])
AX_NEED_PROG([TOUCH], [touch], [])
AX_CHECK_PROG([TPUT], [tput], [])
AX_NEED_PROG([TR], [tr], [])
fi
if test x"$enable_link_balancer" = xyes; then
AC_MSG_NOTICE([Detecting commands for link-balancer])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CHMOD], [chmod], [])
AX_NEED_PROG([CHOWN], [chown], [])
AX_NEED_PROG([CUT], [cut], [])
AX_NEED_PROG([DIFF], [diff], [])
AX_NEED_PROG([ENV], [env], [])
AX_NEED_PROG([FLOCK], [flock], [])
AX_CHECK_PROG([HEAD], [head], [])
AX_NEED_PROG([IP], [ip], [])
AX_NEED_PROG([IPRANGE], [iprange], [])
AX_CHECK_PROG([JQ], [jq], [])
AX_NEED_PROG([LN], [ln], [])
AX_NEED_PROG([LOGGER], [logger], [])
AX_NEED_PROG([LS], [ls], [])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_NEED_PROG([MKTEMP], [mktemp], [])
if test x"$enable_ipv4" = xyes; then
AX_NEED_PROG([PING], [ping], [])
fi
if test x"$enable_ipv6" = xyes; then
AX_NEED_PROG([PING6], [ping6], [])
fi
AX_NEED_PROG([RM], [rm], [])
AX_CHECK_PROG([SCREEN], [screen], [])
AX_NEED_PROG([SLEEP], [sleep], [])
AX_NEED_PROG([SORT], [sort], [])
AX_NEED_PROG([TOUCH], [touch], [])
AX_CHECK_PROG([TPUT], [tput], [])
AX_NEED_PROG([TR], [tr], [])
AX_NEED_PROG([TRACEROUTE], [traceroute], [])
AX_CHECK_PROG([WGET], [wget], [])
AX_CHECK_PROG([WHOIS], [whois], [])
fi
if test x"$enable_update_ipsets" = xyes; then
AC_MSG_NOTICE([Detecting commands for update-ipsets])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CHMOD], [chmod], [])
AX_NEED_PROG([CHOWN], [chown], [])
AX_NEED_PROG([CP], [cp], [])
AX_NEED_PROG([CURL], [curl], [])
AX_NEED_PROG([CUT], [cut], [])
AX_NEED_PROG([DATE], [date], [])
AX_NEED_PROG([DIFF], [diff], [])
AX_NEED_PROG([FIND], [find], [])
AX_NEED_PROG([FLOCK], [flock], [])
AX_NEED_PROG([FOLD], [fold], [])
AX_CHECK_PROG([FUNZIP], [funzip], [])
AX_CHECK_PROG([JQ], [jq], [])
AX_CHECK_PROG([GAWK], [gawk], [])
AX_NEED_PROG([GAWK], [awk], [])
AX_CHECK_PROG([GIT], [git], [])
AX_NEED_PROG([IPRANGE], [iprange], [])
AX_NEED_PROG([IPSET], [ipset], [])
AX_NEED_PROG([LN], [ln], [])
AX_NEED_PROG([LOGGER], [logger], [])
AX_NEED_PROG([LS], [ls], [])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_NEED_PROG([MKTEMP], [mktemp], [])
AX_NEED_PROG([MV], [mv], [])
AX_CHECK_PROG([RENICE], [renice], [])
if test x"$RENICE" = x; then
AC_SUBST([RENICE], [:])
fi
AX_NEED_PROG([RM], [rm], [])
AX_NEED_PROG([SORT], [sort], [])
AX_NEED_PROG([TAIL], [tail], [])
AX_NEED_PROG([TAR], [tar], [])
AX_NEED_PROG([TOUCH], [touch], [])
AX_CHECK_PROG([TPUT], [tput], [])
AX_NEED_PROG([TR], [tr], [])
AX_CHECK_PROG([UNZIP], [unzip], [])
AX_NEED_PROG([WC], [wc], [])
AX_CHECK_PROG([ZCAT], [zcat], [])
AX_CHECK_PROG([ZCAT], [gzcat], [])
AX_NEED_PROG([ZCAT], [gzip], [-dc])
fi
if test x"$enable_vnetbuild" = xyes; then
AC_MSG_NOTICE([Detecting commands for vnetbuild])
AX_NEED_PROG([BRIDGE], [bridge], [])
AX_NEED_PROG([CAT], [cat], [])
AX_NEED_PROG([CUT], [cut], [])
AX_NEED_PROG([FIND], [find], [])
AX_NEED_PROG([IP], [ip], [])
AX_NEED_PROG([MKDIR], [mkdir], [])
AX_NEED_PROG([MKTEMP], [mktemp], [])
AX_CHECK_PROG([NEATO], [neato], [])
AX_NEED_PROG([RM], [rm], [])
AX_CHECK_PROG([SH], [sh], [])
AX_CHECK_PROG([SH], [bash], [])
AX_NEED_PROG([SH], [ksh], [])
AX_NEED_PROG([SLEEP], [sleep], [])
AX_NEED_PROG([TR], [tr], [])
fi
else
AC_MSG_NOTICE(MAKEDIST_BUILD_ONLY is yes - skipping command checks)
fi
dnl --- OUTPUT OF './packaging/gen-config-detect.pl sbin/*.in' END   ---

if test x"$IPRANGE" != x; then
AX_CHECK_MINVER([IPRANGE_VERSION], MIN_IPRANGE_VERSION, [$IPRANGE],
                [--version | head -n 1 | cut -d'_' -f1],
                [], [AC_MSG_ERROR(could not find required version of iprange - check http://firehol.org/download/iprange/)])
fi

AC_SUBST([firehollibexecdir], ["\$(libexecdir)/firehol/\$(PACKAGE_VERSION)"])

AC_CONFIG_FILES([
	Makefile
	sbin/Makefile
	sbin/install.config.in
	m4/Makefile
	doc/Makefile
	doc/firehol/Makefile
	doc/fireqos/Makefile
	doc/vnetbuild/Makefile
	examples/Makefile
	etc/Makefile
	html/Makefile
	html/ipsets/Makefile
	contrib/Makefile
	])

AC_OUTPUT
