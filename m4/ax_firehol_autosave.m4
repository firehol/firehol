# ===========================================================================
#
# ===========================================================================
#
# SYNOPSIS
#
#   AX_FIREHOL_AUTOSAVE()
#
# DESCRIPTION
#
#   Discover the file that IPv4 rules should be saved to so that they
#   will be loaded by the system on startup.
#
#   Output:
#
#   $FIREHOL_AUTOSAVE contains the path to the file, or is empty if none
#   was found or the user specified --without-autosave.
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

AC_DEFUN([AX_FIREHOL_AUTOSAVE],
[
# The (lack of) whitespace and overquoting here are all necessary for
# proper formatting.
AC_ARG_WITH(autosave,
AS_HELP_STRING([--with-autosave[[[[[=PATH]]]]]],
               [Use the PATH to save IPv4 rules to.]),
    [ ac_with_autosave=$withval; ],
    [ ac_with_autosave=maybe; ])

AC_MSG_CHECKING([for default FIREHOL_AUTOSAVE])
if test "$ac_with_autosave" = "yes" -o "$ac_with_autosave" = "maybe"; then
    if test -d /etc/sysconfig; then
        autosave_system=" (RedHat)"
        FIREHOL_AUTOSAVE="/etc/sysconfig/iptables"
    elif test -f /etc/conf.d/iptables; then
        # Get it from /etc/conf.d/iptables
        # by creating and executing a script to extract the value
        cat > conftest-sw-autosave <<!
#!/bin/sh
> conftest-sw-autosave.out
IPTABLES_CONF=
IPTABLES_SAVE=
if test -f /etc/conf.d/iptables; then . /etc/conf.d/iptables; fi
if test -n "\$IPTABLES_SAVE"; then
echo "IPTABLES_SAVE" > conftest-sw-autosave.var
echo "\$IPTABLES_SAVE" > conftest-sw-autosave.out
elif test -n "\$IPTABLES_CONF"; then
echo "IPTABLES_CONF" > conftest-sw-autosave.var
echo "\$IPTABLES_CONF" > conftest-sw-autosave.out
else
echo "missing" > conftest-sw-autosave.var
echo "" > conftest-sw-autosave.out
fi
!
	sh conftest-sw-autosave > /dev/null 2>&1
        autosave_system=" (`cat conftest-sw-autosave.var` from /etc/conf.d/iptables)"
        FIREHOL_AUTOSAVE="`cat conftest-sw-autosave.out`"
    elif test -d /etc/iptables; then
        autosave_system=" (Debian)"
        FIREHOL_AUTOSAVE="/etc/iptables/rules.v4"
    else
        autosave_system="no default available"
        FIREHOL_AUTOSAVE=""
    fi
else
    if test "$ac_with_autosave" = "no"; then
            autosave_system=" (user specified empty)"
            FIREHOL_AUTOSAVE=""
    else
            autosave_system=" (user specified)"
            FIREHOL_AUTOSAVE="$ac_with_autosave";
    fi
fi
AC_MSG_RESULT([$FIREHOL_AUTOSAVE$autosave_system])
AC_SUBST(FIREHOL_AUTOSAVE)
])
