#
# SYNOPSIS
#
#   AX_CHECK_PROG([VARIABLE],[program],[OPTIONS-IF-FOUND],[PATH])
#
# DESCRIPTION
#
#   Checks for an installed program binary, placing the PATH and
#   OPTIONS-IF-FOUND in the precious variable VARIABLE if so.
#   Uses AC_PATH_PROG to do the work.
#
# LICENSE
#
#   Copyright (c) 2015 Phil Whineray <phil@sanewall.org>
#
#   Copying and distribution of this file, with or without modification, are
#   permitted in any medium without royalty provided the copyright notice
#   and this notice are preserved. This file is offered as-is, without any
#   warranty.

AC_DEFUN([AX_CHECK_PROG],[
    pushdef([VARIABLE],$1)
    pushdef([EXECUTABLE],$2)
    pushdef([OPTIONS_IF_FOUND],$3)
    pushdef([PATH_PROG],$4)

    AS_IF([test "x$VARIABLE" = "x"],[
        AC_PATH_PROG([]VARIABLE[], []EXECUTABLE[], [], []PATH_PROG[])

        AS_IF([test "x$VARIABLE" != "x"],[
          AS_IF([test x"OPTIONS_IF_FOUND" = "x"],[],
                [VARIABLE="$VARIABLE OPTIONS_IF_FOUND"])
          ])
    ])

    popdef([PATH_PROG])
    popdef([OPTIONS_IF_FOUND])
    popdef([EXECUTABLE])
    popdef([VARIABLE])
])
