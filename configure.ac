dnl Process this file with autoconf to produce a configure script.

AC_PREREQ([2.63])
AC_INIT([firehol],[m4_esyscmd([./packaging/packver])],[firehol-devs@lists.firehol.org])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_AUX_DIR([autotool])
AC_CONFIG_SRCDIR([sbin/firehol.in])
AC_CONFIG_SRCDIR([sbin/fireqos.in])
AC_CONFIG_SRCDIR([sbin/link-balancer.in])
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
fi

FIREHOL_CONFIG_DIR=$(eval echo "$sysconfdir/firehol" | sed -e 's|^NONE|/usr/local|')
AC_SUBST(FIREHOL_CONFIG_DIR)

AX_NEED_AWK()
AX_NEED_PROG([CAT_CMD], [cat], [cat])
AX_NEED_PROG([CHMOD_CMD], [chmod], [chmod])
AX_NEED_PROG([CHOWN_CMD], [chown], [chown])
AX_NEED_PROG([CUT_CMD], [cut], [cut])
AX_NEED_PROG([DATE_CMD], [date], [date])
AX_NEED_PROG([EGREP_CMD], [egrep], [egrep])
AX_NEED_PROG([EXPR_CMD], [expr], [expr])
AX_NEED_PROG([FIND_CMD], [find], [find])
AX_NEED_PROG([FOLD_CMD], [fold], [fold])
AX_NEED_GREP()
AX_NEED_PROG([HEAD_CMD], [head], [head])
AX_NEED_PROG([HOSTNAME_CMD], [hostname], [hostname])
AC_CHECK_PROG([INSMOD_CMD], [modprobe], [modprobe -q], [], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([INSMOD_CMD], [insmod], [insmod], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP6TABLES_CMD], [ip6tables], [ip6tables], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP_CMD], [ip], [ip])
AX_NEED_PROG([IP6TABLES_RESTORE_CMD], [ip6tables-restore], [iptables-restore], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IP6TABLES_SAVE_CMD], [ip6tables-save], [ip6tables-save], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES_CMD], [iptables], [iptables], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES_RESTORE_CMD], [iptables-restore], [iptables-restore], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([IPTABLES_SAVE_CMD], [iptables-save], [iptables-save], [$PATH:/sbin:/usr/sbin])
AC_CHECK_PROG([FLOCK_CMD], [flock], [flock], [:])
AX_NEED_PROG([LOGGER_CMD], [logger], [logger])
AX_NEED_PROG([LSMOD_CMD], [lsmod], [lsmod], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([MKDIR_CMD], [mkdir], [mkdir])
AX_NEED_PROG([MKTEMP_CMD], [mktemp], [mktemp])
AX_NEED_PROG([MV_CMD], [mv], [mv])
AC_CHECK_PROG([PAGER_CMD], [pager], [pager])
AC_CHECK_PROG([PAGER_CMD], [less], [less])
AC_CHECK_PROG([PAGER_CMD], [more], [more])
AX_NEED_PROG([PAGER_CMD], [cat], [cat])
AC_CHECK_PROG([RENICE_CMD], [renice], [renice], [:])
AX_NEED_PROG([RM_CMD], [rm], [rm])
AX_NEED_SED()
AX_NEED_PROG([SORT_CMD], [sort], [sort])
AX_NEED_PROG([SS_CMD], [ss], [ss])
AX_NEED_PROG([SYSCTL_CMD], [sysctl], [sysctl], [$PATH:/sbin:/usr/sbin])
AX_NEED_PROG([TOUCH_CMD], [touch], [touch])
AX_NEED_PROG([TR_CMD], [tr], [tr])
AX_NEED_PROG([UNAME_CMD], [uname], [uname])
AX_NEED_PROG([UNIQ_CMD], [uniq], [uniq])
AC_CHECK_PROG([ZCAT_CMD], [zcat], [zcat])
AC_CHECK_PROG([ZCAT_CMD], [gzcat], [gzcat])
AC_CHECK_PROG([ZCAT_CMD], [gunzip], [gunzip -c])
AX_NEED_PROG([ZCAT_CMD], [gzip], [gzip -d -c])

AM_CONDITIONAL([ENABLE_DOC], [test "${enable_doc}" = "yes"])

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
	packaging/Makefile
	])

AC_CONFIG_FILES([sbin/firehol], [chmod +x sbin/firehol])
AC_CONFIG_FILES([sbin/fireqos], [chmod +x sbin/fireqos])
AC_CONFIG_FILES([sbin/link-balancer], [chmod +x sbin/link-balancer])
AC_CONFIG_FILES([sbin/vnetbuild], [chmod +x sbin/vnetbuild])

AC_OUTPUT
