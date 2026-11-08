# See LICENSE for license details.

#*****************************************************************************
# auipc.S
#-----------------------------------------------------------------------------
#
# Test auipc instruction.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN

  TEST_CASE(2, x11, 10000, \
    .align 3; \
    lla x11, 1f + 10000; \
    jal x12, 1f; \
    1: sub x11, x11, x12; \
  )

  TEST_CASE(3, x11, -10000, \
    .align 3; \
    lla x11, 1f - 10000; \
    jal x12, 1f; \
    1: sub x11, x11, x12; \
  )

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
