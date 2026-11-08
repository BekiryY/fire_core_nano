# See LICENSE for license details.

#*****************************************************************************
# jalr.S
#-----------------------------------------------------------------------------
#
# Test jalr instruction.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # Test 2: Basic test
  #-------------------------------------------------------------

test_2:
  li  TESTNUM, 2
  li  x11, 0
  la  x12, target_2

  jalr x11, x12, 0
linkaddr_2:
  j fail

target_2:
  la  x12, linkaddr_2
  bne x11, x12, fail

  #-------------------------------------------------------------
  # Test 3: Basic test2, rs = rd
  #-------------------------------------------------------------

test_3:
  li  TESTNUM, 3
  la  x11, target_3

  jalr x11, x11, 0
linkaddr_3:
  j fail

target_3:
  la  x12, linkaddr_3
  bne x11, x12, fail

  #-------------------------------------------------------------
  # Bypassing tests
  #-------------------------------------------------------------

  TEST_JALR_SRC1_BYPASS( 4, 0, jalr );
  TEST_JALR_SRC1_BYPASS( 5, 1, jalr );
  TEST_JALR_SRC1_BYPASS( 6, 2, jalr );

  #-------------------------------------------------------------
  # Test delay slot instructions not executed nor bypassed
  #-------------------------------------------------------------

  .option push
  .align 2
  .option norvc
  TEST_CASE( 7, x11, 4, \
    li  x11, 1; \
    la  x12, 1f; \
    jr  x12, -4; \
    addi x11, x11, 1; \
    addi x11, x11, 1; \
    addi x11, x11, 1; \
    addi x11, x11, 1; \
1:  addi x11, x11, 1; \
    addi x11, x11, 1; \
  )
  .option pop

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
