# ===========================================================================
#
# ===========================================================================
#
# SYNOPSIS
#
#   AX_FIREHOL_AUTOSAVE6()
#
# DESCRIPTION
#
#   Discover the file that IPv6 rules should be saved to so that they
#   will be loaded by the system on startup.
#
#   Output:
#
#   $FIREHOL_AUTOSAVE6 contains the path to the file, or is empty if none
#   was found or the user specified --without-autosave6.
#
# LICENSE
#
#   Copyright (c) 2013 Phil Whineray <phil@sanewall.org>
#
#   This program is free software; you can redistribute it and/or modify it
#   under the terms of the GNU General Public License as published by the
#   Free Software Foundation; either version 2 of the License, or (at your
#   option) any later version.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
#   Public License for more details.
#
#   You should have received a copy of the GNU General Public License along
#   with this program. If not, see <http://www.gnu.org/licenses/>.
#
#   As a special exception, the respective Autoconf Macro's copyright owner
#   gives unlimited permission to copy, distribute and modify the configure
#   scripts that are the output of Autoconf when processing the Macro. You
#   need not follow the terms of the GNU General Public License when using
#   or distributing such scripts, even though portions of the text of the
#   Macro appear in them. The GNU General Public License (GPL) does govern
#   all other use of the material that constitutes the Autoconf Macro.
#
#   This special exception to the GPL applies to versions of the Autoconf
#   Macro released by the Autoconf Archive. When you make and distribute a
#   modified version of the Autoconf Macro, you may extend this special
#   exception to the GPL to apply to your modified version as well.

#serial 5

AC_DEFUN([AX_FIREHOL_AUTOSAVE6],
[
# The (lack of) whitespace and overquoting here are all necessary for
# proper formatting.
AC_ARG_WITH(autosave6,
AS_HELP_STRING([--with-autosave6[[[[[=PATH]]]]]],
               [Use the PATH to save IPv6 rules to.]),
    [ ac_with_autosave6=$withval; ],
    [ ac_with_autosave6=maybe; ])

AC_MSG_CHECKING([for default FIREHOL_AUTOSAVE6])
if test "$ac_with_autosave6" = "yes" -o "$ac_with_autosave6" = "maybe"; then
    if test -d /etc/sysconfig; then
        autosave6_system=" (RedHat)"
        FIREHOL_AUTOSAVE6="/etc/sysconfig/ip6tables"
    elif test -f /etc/conf.d/ip6tables -o -f /etc/conf.d/iptables; then
        cat > conftest-sw-autosave6 <<!
#!/bin/sh
> conftest-sw-autosave6.out
IP6TABLES_CONF=
IP6TABLES_SAVE=
if test -f /etc/conf.d/ip6tables; then
echo "/etc/conf.d/ip6tables" > conftest-sw-autosave6.fil
. /etc/conf.d/ip6tables
elif test -f /etc/conf.d/iptables; then
echo "/etc/conf.d/iptables" > conftest-sw-autosave6.fil
. /etc/conf.d/iptables
fi
if test -n "\$IP6TABLES_SAVE"; then
echo "IP6TABLES_SAVE" > conftest-sw-autosave6.var
echo "\$IP6TABLES_SAVE" > conftest-sw-autosave6.out
elif test -n "\$IP6TABLES_CONF"; then
echo "IP6TABLES_CONF" > conftest-sw-autosave6.var
echo "\$IP6TABLES_CONF" > conftest-sw-autosave6.out
else
echo "missing" > conftest-sw-autosave6.var
echo "" > conftest-sw-autosave6.out
echo "/etc/conf.d/ip6tables and /etc/conf.d/iptables" > conftest-sw-autosave6.fil
fi
!
	sh conftest-sw-autosave6 > /dev/null 2>&1
        autosave6_system=" (`cat conftest-sw-autosave6.var` from `cat conftest-sw-autosave6.fil`)"
        FIREHOL_AUTOSAVE6="`cat conftest-sw-autosave6.out`"
    elif test -d /etc/iptables; then
        autosave6_system=" (Debian)"
        FIREHOL_AUTOSAVE6="/etc/iptables/rules.v6"
    else
        autosave6_system="no default available"
        FIREHOL_AUTOSAVE6=""
    fi
else
    if test "$ac_with_autosave6" = "no"; then
            autosave6_system=" (user specified empty)"
            FIREHOL_AUTOSAVE6=""
    else
            autosave6_system=" (user specified)"
            FIREHOL_AUTOSAVE6="$ac_with_autosave6";
    fi
fi
AC_MSG_RESULT([$FIREHOL_AUTOSAVE6$autosave6_system])
AC_SUBST(FIREHOL_AUTOSAVE6)
])
