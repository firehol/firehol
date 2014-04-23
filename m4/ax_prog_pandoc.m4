# ===========================================================================
#
# ===========================================================================
#
# SYNOPSIS
#
#   AX_PROG_PANDOC([pdf-flags],[html-flags],[man-flags])
#
# DESCRIPTION
#
#   Find a pandoc executable.
#
#   Input:
#
#   "pdf-flags" is the default $PANDOC_PDF_FLAGS, which will be overridden
#   if the user specifies --with-pandoc-pdf-flags.
#
#   "html-flags" is the default $PANDOC_HTML_FLAGS, which will be overridden
#   if the user specifies --with-pandoc-html-flags.
#
#   "man-flags" is the default $PANDOC_MAN_FLAGS, which will be overridden
#   if the user specifies --with-pandoc-man-flags.
#
#   Output:
#
#   $PANDOC contains the path to pandoc, or is empty if none was found
#   or the user specified --without-pandoc. $PANDOC_PDF_FLAGS,
#   $PANDOC_HTML_FLAGS and $PANDOC_MAN_FLAGS are the flags to produce
#   the various output formats with pandoc.
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

AU_ALIAS([AC_PROG_PANDOC], [AX_PROG_PANDOC])
AC_DEFUN([AX_PROG_PANDOC],
[
PANDOC_PDF_FLAGS="$1"
PANDOC_HTML_FLAGS="$2"
PANDOC_MAN_FLAGS="$3"
AC_SUBST(PANDOC_PDF_FLAGS)
AC_SUBST(PANDOC_HTML_FLAGS)
AC_SUBST(PANDOC_MAN_FLAGS)

# The (lack of) whitespace and overquoting here are all necessary for
# proper formatting.
AC_ARG_WITH(pandoc,
AS_HELP_STRING([--with-pandoc[[[[[=PATH]]]]]],
               [Use the pandoc binary in PATH.]),
    [ ac_with_pandoc=$withval; ],
    [ ac_with_pandoc=maybe; ])

AC_ARG_WITH(pandoc-pdf-flags,
AS_HELP_STRING([  --with-pandoc-pdf-flags=FLAGS],
               [Flags to pass to pandoc for PDF creation (default $1)]),
    [ if test "x$withval" == "xno"; then
	PANDOC_PDF_FLAGS=''
    else
	if test "x$withval" != "xyes"; then
	    PANDOC_PDF_FLAGS="$withval"
	fi
    fi
	])

AC_ARG_WITH(pandoc-html-flags,
AS_HELP_STRING([  --with-pandoc-html-flags=FLAGS],
               [Flags to pass to pandoc for HTML creation (default $2)]),
    [ if test "x$withval" == "xno"; then
	PANDOC_HTML_FLAGS=''
    else
	if test "x$withval" != "xyes"; then
	    PANDOC_HTML_FLAGS="$withval"
	fi
    fi
	])

AC_ARG_WITH(pandoc-man-flags,
AS_HELP_STRING([  --with-pandoc-man-flags=FLAGS],
               [Flags to pass to pandoc for manpage creation (default $3)]),
    [ if test "x$withval" == "xno"; then
	PANDOC_MAN_FLAGS=''
    else
	if test "x$withval" != "xyes"; then
	    PANDOC_MAN_FLAGS="$withval"
	fi
    fi
	])

# search for pandoc if it wasn't specified
if test "$ac_with_pandoc" = "yes" -o "$ac_with_pandoc" = "maybe"; then
    AC_PATH_PROGS(PANDOC,pandoc)
else
    if test "$ac_with_pandoc" != "no"; then
        if test -x "$ac_with_pandoc"; then
            PANDOC="$ac_with_pandoc";
        else
            AC_MSG_WARN([Specified pandoc of $ac_with_pandoc isn't])
            AC_MSG_WARN([executable; searching for an alternative.])
            AC_PATH_PROGS(PANDOC,pandoc)
        fi
    fi
fi
])
