dnl
dnl SYNOPSIS
dnl
dnl   AX_CHECK_PANDOC_OUTPUT()
dnl
dnl DESCRIPTION
dnl
dnl   Check for ability of pandoc to write PDF, HTML, man-page outputs
dnl
dnl   Input:
dnl
dnl     None
dnl
dnl   Output:
dnl
dnl     None
dnl
dnl   Example:
dnl
dnl    AX_CHECK_PANDOC_OUTPUT()
dnl    ...
dnl
dnl LICENSE
dnl
dnl   Copyright (c) 2014 Phil Whineray <phil@sanewall.org>
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

AU_ALIAS([AC_CHECK_PANDOC_OUTPUT], [AX_CHECK_PANDOC_OUTPUT])
AC_DEFUN([AX_CHECK_PANDOC_OUTPUT],
[
    AC_REQUIRE([AX_PROG_PANDOC])

    AC_CACHE_CHECK([for pandoc PDF output], [ac_cv_pandoc_output_pdf],
    [
        ac_cv_pandoc_output_pdf=no
        if test -n "$PANDOC"; then
            cat <<EOF >conftest.md
# Test Pandoc

Some text
EOF
            echo "Trying '$PANDOC $PANDOC_PDF_FLAGS conftest.md -o conftest.pdf'" >&AS_MESSAGE_LOG_FD
            $PANDOC $PANDOC_PDF_FLAGS conftest.md -o conftest.pdf >conftest.out 2>&1
            if test "$?" = 0; then
                if test -s conftest.pdf; then
                    ac_cv_pandoc_output_pdf=yes
                fi
            fi
            cat conftest.out >&AS_MESSAGE_LOG_FD

            rm -f conftest.md conftest.out conftest.pdf
        fi
    ])

    AC_CACHE_CHECK([for pandoc HTML output], [ac_cv_pandoc_output_html],
    [
        ac_cv_pandoc_output_html=no
        if test -n "$PANDOC"; then
            cat <<EOF >conftest.md
# Test Pandoc

Some text
EOF
            echo "Trying '$PANDOC $PANDOC_HTML_FLAGS conftest.md -o conftest.html'" >&AS_MESSAGE_LOG_FD
            $PANDOC $PANDOC_HTML_FLAGS conftest.md -o conftest.html >conftest.out 2>&1
            if test "$?" = 0; then
                if test -s conftest.html; then
                    ac_cv_pandoc_output_html=yes
                fi
            fi
            cat conftest.out >&AS_MESSAGE_LOG_FD

            rm -f conftest.md conftest.out conftest.html
        fi
    ])

    AC_CACHE_CHECK([for pandoc manpage output], [ac_cv_pandoc_output_man],
    [
        ac_cv_pandoc_output_man=no
        if test -n "$PANDOC"; then
            cat <<EOF >conftest.md
# Test Pandoc

Some text
EOF
            echo "Trying '$PANDOC $PANDOC_MAN_FLAGS conftest.md -o conftest.man'" >&AS_MESSAGE_LOG_FD
            $PANDOC $PANDOC_MAN_FLAGS conftest.md -o conftest.man >conftest.out 2>&1
            if test "$?" = 0; then
                if test -s conftest.man; then
                    ac_cv_pandoc_output_man=yes
                fi
            fi
            cat conftest.out >&AS_MESSAGE_LOG_FD

            rm -f conftest.md conftest.out conftest.man
        fi
    ])

    ac_cv_all_outputs=yes
    AS_IF([test "x$ac_cv_pandoc_output_man" = "xno"],[
      ac_cv_all_outputs=no
    ])
    AS_IF([test "x$ac_cv_pandoc_output_html" = "xno"],[
      ac_cv_all_outputs=no
    ])
    AS_IF([test "x$ac_cv_pandoc_output_pdf" = "xno"],[
      ac_cv_all_outputs=no
      AC_MSG_NOTICE(N.B. pandoc PDF output requires pdflatex)
    ])
    AS_IF([test "x$ac_cv_all_outputs" = "xno"],[
      AC_MSG_ERROR([cannot produce all pandoc outputs, bailing out])
    ])
])
