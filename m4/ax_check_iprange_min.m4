dnl =============================================================================
dnl
dnl =============================================================================
dnl
dnl SYNOPSIS
dnl
dnl   AX_CHECK_IPRANGE_MIN([MINIMUM-VERSION, [ACTION-IF-FOUND [, ACTION-IF-NOT-FOUND]]])
dnl
dnl DESCRIPTION
dnl
dnl   Check that the version of iprange is at least version MINIMUM-VERSION.
dnl   If the test is successful, $IPRANGE_VERSION will be set to the iprange
dnl   version and ACTION-IF-FOUND is performed; if not, it will be set to 'no'
dnl   and ACTION-IF-NOT-FOUND is performed.
dnl
dnl   Example:
dnl
dnl    AX_CHECK_IPRANGE_MIN([1.0.0])
dnl    if test "x$IPRANGE_VERSION" = "xno"; then
dnl    ...
dnl
dnl   NOTE: This macros is based upon the original AX_CHECK_DOCBOOK_XSLT_MIN macro
dnl   from Dustin J. Mitchell <dustin@zmanda.com>
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

AU_ALIAS([AC_CHECK_IPRANGE_MIN], [AX_CHECK_IPRANGE_MIN])
AC_DEFUN([AX_CHECK_IPRANGE_MIN],
[
	AC_CACHE_CHECK([for iprange version], [ac_cv_iprange_version],
		[
			ac_cv_iprange_version=no

			if test -n "$IPRANGE"; then
				ac_cv_iprange_version=$($IPRANGE --version 2> /dev/null | head -n 1 | cut -d'_' -f1)

				if test "x$ac_cv_iprange_version" = "x"; then
					ac_cv_iprange_version='no'
				fi

			fi
		])

		min_iprange_version=ifelse([$1], ,1.0.0,$1)

		IPRANGE_VERSION="$ac_cv_iprange_version"
		AC_MSG_CHECKING([whether iprange version is $min_iprange_version or newer])

		if test x"$ac_cv_iprange_version" = xno ; then
			AC_MSG_RESULT([no])
			IPRANGE_VERSION='no'
			ifelse([$3], , :, [$3])
		else
			ac_cv_iprange_compare_answer=yes
			AX_COMPARE_VERSION([$IPRANGE_VERSION],[lt],[$min_iprange_version],[ac_cv_iprange_compare_answer=no])
				if test x"$ac_cv_iprange_compare_answer" = xno ; then
					AC_MSG_RESULT([no ($IPRANGE_VERSION)])
					IPRANGE_VERSION='no'
					ifelse([$3], , :, [$3])
				else
					AC_MSG_RESULT([yes ($IPRANGE_VERSION)])
					ifelse([$2], , :, [$2])
				fi
			unset ac_cv_iprange_compare_answer
		fi
])
dnl
dnl
