# ===========================================================================
#
# ===========================================================================
#
# SYNOPSIS
#
#   AX_PROG_XMLLINT([default-flags])
#
# DESCRIPTION
#
#   Find an xmllint executable.
#
#   Input:
#
#   "default-flags" is the default $XMLLINT_FLAGS, which will be overridden
#   if the user specifies --with-xmllint-flags.
#
#   Output:
#
#   $XMLLINT contains the path to xmllint, or is empty if none was found
#   or the user specified --without-xmllint. $XMLLINT_FLAGS contains the
#   flags to use with xmllint.
#
#   NOTE: This macros is based upon the original AX_PROG_XSLTPROC macro from
#   Dustin J. Mitchell <dustin@zmanda.com>
#
# LICENSE
#
#   Copyright (c) 2013 Jerome Benoit <calculus@rezozer.net>
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

AU_ALIAS([AC_PROG_XMLLINT], [AX_PROG_XMLLINT])
AC_DEFUN([AX_PROG_XMLLINT],
[
XMLLINT_FLAGS="$1"
AC_SUBST(XMLLINT_FLAGS)

# The (lack of) whitespace and overquoting here are all necessary for
# proper formatting.
AC_ARG_WITH(xmllint,
AS_HELP_STRING([--with-xmllint[[[[[=PATH]]]]]],
               [Use the xmllint binary in PATH.]),
    [ ac_with_xmllint=$withval; ],
    [ ac_with_xmllint=maybe; ])

AC_ARG_WITH(xmllint-flags,
AS_HELP_STRING([  --with-xmllint-flags=FLAGS],
               [Flags to pass to xmllint (default $1)]),
    [ if test "x$withval" == "xno"; then
	XMLLINT_FLAGS=''
    else
	if test "x$withval" != "xyes"; then
	    XMLLINT_FLAGS="$withval"
	fi
    fi
	])

# search for xmllint if it wasn't specified
if test "$ac_with_xmllint" = "yes" -o "$ac_with_xmllint" = "maybe"; then
    AC_PATH_PROGS(XMLLINT,xmllint)
else
    if test "$ac_with_xmllint" != "no"; then
        if test -x "$ac_with_xmllint"; then
            XMLLINT="$ac_with_xmllint";
        else
            AC_MSG_WARN([Specified xmllint of $ac_with_xmllint isn't])
            AC_MSG_WARN([executable; searching for an alternative.])
            AC_PATH_PROGS(XMLLINT,xmllint)
        fi
    fi
fi
])
