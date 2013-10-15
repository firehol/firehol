# ===========================================================================
#
# ===========================================================================
#
# SYNOPSIS
#
#   AX_PROG_DBLATEX([default-flags])
#
# DESCRIPTION
#
#   Find an dblatex executable.
#
#   Input:
#
#   "default-flags" is the default $DBLATEX_FLAGS, which will be overridden
#   if the user specifies --with-dblatex-flags.
#
#   Output:
#
#   $DBLATEX contains the path to dblatex, or is empty if none was found
#   or the user specified --without-dblatex. $DBLATEX_FLAGS contains the
#   flags to use with dblatex.
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

AU_ALIAS([AC_PROG_DBLATEX], [AX_PROG_DBLATEX])
AC_DEFUN([AX_PROG_DBLATEX],
[
DBLATEX_FLAGS="$1"
AC_SUBST(DBLATEX_FLAGS)

# The (lack of) whitespace and overquoting here are all necessary for
# proper formatting.
AC_ARG_WITH(dblatex,
AS_HELP_STRING([--with-dblatex[[[[[=PATH]]]]]],
               [Use the dblatex binary in PATH.]),
    [ ac_with_dblatex=$withval; ],
    [ ac_with_dblatex=maybe; ])

AC_ARG_WITH(dblatex-flags,
AS_HELP_STRING([  --with-dblatex-flags=FLAGS],
               [Flags to pass to dblatex (default $1)]),
    [ if test "x$withval" == "xno"; then
	DBLATEX_FLAGS=''
    else
	if test "x$withval" != "xyes"; then
	    DBLATEX_FLAGS="$withval"
	fi
    fi
	])

# search for dblatex if it wasn't specified
if test "$ac_with_dblatex" = "yes" -o "$ac_with_dblatex" = "maybe"; then
    AC_PATH_PROGS(DBLATEX,dblatex)
else
    if test "$ac_with_dblatex" != "no"; then
        if test -x "$ac_with_dblatex"; then
            DBLATEX="$ac_with_dblatex";
        else
            AC_MSG_WARN([Specified dblatex of $ac_with_dblatex isn't])
            AC_MSG_WARN([executable; searching for an alternative.])
            AC_PATH_PROGS(DBLATEX,dblatex)
        fi
    fi
fi
])
