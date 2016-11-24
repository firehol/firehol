dnl SYNOPSIS
dnl
dnl   AX_CHECK_MODPROBE_QUIET()
dnl
dnl DESCRIPTION
dnl
dnl   Check for a modprobe+whether it appears to handle the -q option
dnl
dnl LICENSE
dnl
dnl   Copyright (c) 2016 Phil Whineray <phil@firehol.org>
dnl
dnl   This program is free software; you can redistribute it and/or modify it
dnl   under the terms of the GNU General Public License as published by the
dnl   Free Software Foundation; either version 2 of the License, or (at your
dnl   option) any later version.
dnl
dnl   This program is distributed in the hope that it will be useful, but
dnl   WITHOUT ANY WARRANTY; without even the implied warranty of
dnl   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
dnl   Public License for more details.
dnl
dnl   You should have received a copy of the GNU General Public License along
dnl   with this program. If not, see <http://www.gnu.org/licenses/>.
dnl
dnl   As a special exception, the respective Autoconf Macro's copyright owner
dnl   gives unlimited permission to copy, distribute and modify the configure
dnl   scripts that are the output of Autoconf when processing the Macro. You
dnl   need not follow the terms of the GNU General Public License when using
dnl   or distributing such scripts, even though portions of the text of the
dnl   Macro appear in them. The GNU General Public License (GPL) does govern
dnl   all other use of the material that constitutes the Autoconf Macro.
dnl
dnl   This special exception to the GPL applies to versions of the Autoconf
dnl   Macro released by the Autoconf Archive. When you make and distribute a
dnl   modified version of the Autoconf Macro, you may extend this special
dnl   exception to the GPL to apply to your modified version as well.

AC_DEFUN([AX_CHECK_MODPROBE_QUIET],
[
    AC_PATH_PROG([MODPROBE], [modprobe], [], [])

    AC_CACHE_CHECK([whether ]MODPROBE[ has working -q option], [ac_cv_modprobe_q_opt],
    [
        ac_cv_modprobe_q_opt=no
        if test -n "$MODPROBE"; then
            echo "Trying '$MODPROBE -q -n made-up-name'" >&AS_MESSAGE_LOG_FD
            $MODPROBE -q -n made-up-name-nonexistend > conftest.out 2>&1
            if ! test -s conftest.out; then
                ac_cv_modprobe_q_opt=yes
            fi
            cat conftest.out >&AS_MESSAGE_LOG_FD
            rm -f conftest.out
        fi
    ])

    AS_IF([test "x$ac_cv_modprobe_q_opt" = "xyes"],[
      MODPROBE="$MODPROBE -q"
    ])
])
