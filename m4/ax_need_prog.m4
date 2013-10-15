#
# SYNOPSIS
#
#   AX_NEED_PROG([VARIABLE],[program],[VALUE-IF-FOUND],[PATH])
#
# DESCRIPTION
#
#   Checks for an installed program binary, placing VALUE-IF-FOUND in the
#   precious variable VARIABLE if so. Uses AC_CHECK_PROG but adds a test for
#   success and bails out if not.
#
# LICENSE
#
#   Copyright (c) 2013 Phil Whineray <phil@sanewall.org>
#
#   Copying and distribution of this file, with or without modification, are
#   permitted in any medium without royalty provided the copyright notice
#   and this notice are preserved. This file is offered as-is, without any
#   warranty.

AC_DEFUN([AX_NEED_PROG],[
    pushdef([VARIABLE],$1)
    pushdef([EXECUTABLE],$2)
    pushdef([VALUE_IF_FOUND],$3)
    pushdef([PATH_PROG],$4)

    AC_CHECK_PROG([]VARIABLE[], []EXECUTABLE[], []VALUE_IF_FOUND[],
                  [], []PATH_PROG[])

    AS_IF([test "x$VARIABLE" = "x"],[
      AC_MSG_ERROR([cannot find required executable, bailing out])
    ])

    popdef([PATH_PROG])
    popdef([VALUE_IF_FOUND])
    popdef([EXECUTABLE])
    popdef([VARIABLE])
])
