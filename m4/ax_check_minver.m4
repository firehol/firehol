dnl =============================================================================
dnl
dnl =============================================================================
dnl
dnl SYNOPSIS
dnl
dnl   AX_CHECK_MINVER(VARIABLE, MINIMUM, COMMAND, REST, [ACTION-IF-OVER [, ACTION-IF-UNDER]])
dnl
dnl DESCRIPTION
dnl
dnl   Check that the version returned by running `COMMAND REST` is at least
dnl   version MINIMUM.
dnl
dnl   If the test is successful, $VARIABLE will be set to the version
dnl   and ACTION-IF-OVER is performed; if not, it will be set to 'no'
dnl   and ACTION-IF-UNDER is performed.
dnl
dnl   Example:
dnl
dnl    AX_CHECK_MINVER([IPRANGE_VERSION], [1.0.0], [iprange],
dnl                     [--version 2> /dev/null | head -n 1 | cut -d'_' -f1])
dnl    if test "x$IPRANGE_VERSION" = "xno"; then
dnl    ...
dnl    fi
dnl
dnl LICENSE
dnl
dnl   Copyright (c) 2015 Phil Whineray <phil@firehol.org>
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
dnl

AC_DEFUN([AX_CHECK_MINVER],[
	pushdef([VARIABLE],$1)
	pushdef([MINIMUM],$2)
	pushdef([COMMAND],$3)
	pushdef([REST],$4)
	pushdef([IFOVER],$5)
	pushdef([IFUNDER],$6)

	pushdef([RUN],COMMAND REST)
	dnl AC_MSG_NOTICE([running(]RUN[)])

	if test "${cross_compiling}" = 'yes'; then
		test -z "$VARIABLE" && AC_MSG_ERROR([must set ]VARIABLE[ when cross-compiling])
	elif test -z "$MINIMUM"; then
		AC_MSG_ERROR([no minimum for ]COMMAND[ version detection])
	else
		VARIABLE=`RUN`

		if test x"$VARIABLE" = "x"; then
			VARIABLE='no'
		fi
	fi

	AC_MSG_CHECKING([whether ]COMMAND[ version is ]MINIMUM[ or newer])

	if test x"$VARIABLE" = xno ; then
		AC_MSG_RESULT([no])
		ifelse(IFUNDER, , :, IFUNDER)
	else
		ac_minimum_compare_answer=yes
		AX_COMPARE_VERSION($VARIABLE,[lt],MINIMUM,[ac_minimum_compare_answer=no])
		if test x"$ac_minimum_compare_answer" = xno ; then
			AC_MSG_RESULT([no (]$VARIABLE[)])
			VARIABLE='no'
			ifelse(IFUNDER, , :, IFUNDER)
		else
			AC_MSG_RESULT([yes (]$VARIABLE[)])
			ifelse(IFOVER, , :, IFOVER)
		fi
		unset ac_minimum_compare_answer
	fi

	popdef([RUN])

	popdef([IFUNDER])
	popdef([IFOVER])
	popdef([REST])
	popdef([COMMAND])
	popdef([MINIMUM])
	popdef([VARIABLE])
])
