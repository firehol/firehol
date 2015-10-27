# SYNOPSIS
#
#   AX_NEED_EGREP
#
# DESCRIPTION
#
#   Check if an egrep implementation is available. Bail-out if not found.
#
#   This work is heavily based upon ax_need_awk.m4 script by
#   Francesco Salvestrini <salvestrini@users.sourceforge.net>, here
#      http://www.gnu.org/software/autoconf-archive/ax_need_awk.html
#
# LICENSE
#
#   Copyright (c) 2015 Phil Whineray <phil@sanewall.org>
#   Copyright (c) 2009 Francesco Salvestrini <salvestrini@users.sourceforge.net>
#
#   Copying and distribution of this file, with or without modification, are
#   permitted in any medium without royalty provided the copyright notice
#   and this notice are preserved. This file is offered as-is, without any
#   warranty.

AC_DEFUN([AX_NEED_EGREP],[
  AC_REQUIRE([AC_PROG_EGREP])

  AS_IF([test "x$EGREP" = "x"],[
    AC_MSG_ERROR([cannot find egrep, bailing out])
  ])
])
