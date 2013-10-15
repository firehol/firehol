# SYNOPSIS
#
#   AX_NEED_SED
#
# DESCRIPTION
#
#   Check if a sed implementation is available. Bail-out if not found.
#
#   This work is heavily based upon ax_need_awk.m4 script by
#   Francesco Salvestrini <salvestrini@users.sourceforge.net>, here
#      http://www.gnu.org/software/autoconf-archive/ax_need_awk.html
#
# LICENSE
#
#   Copyright (c) 2013 Phil Whineray <phil@sanewall.org>
#   Copyright (c) 2009 Francesco Salvestrini <salvestrini@users.sourceforge.net>
#
#   Copying and distribution of this file, with or without modification, are
#   permitted in any medium without royalty provided the copyright notice
#   and this notice are preserved. This file is offered as-is, without any
#   warranty.

AC_DEFUN([AX_NEED_SED],[
  AC_REQUIRE([AC_PROG_SED])

  AS_IF([test "x$SED" = "x"],[
    AC_MSG_ERROR([cannot find sed, bailing out])
  ])
])
