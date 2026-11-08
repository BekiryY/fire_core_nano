// See LICENSE for license details.
//
// fc32e1s_nano_asic version of the riscv-tests scalar macros (RV32I integer subset only).
// The core has only x0, x1, x2, x10..x12 (rev 2; rev 1 also had x13, x14), so every macro uses
// this fixed set:
//
//   x10  TESTNUM (riscv_test.h)        x1   result (upstream testreg x14)
//   x11  source 1 / load-store base    x12  source 2 / store data
//   x2   bypass-loop counter (upstream x4), then the expected value (upstream x7): TEST_CASE
//        compares after the loop. When the tested register is x2 itself, x11 holds the
//        expected value (.ifc).
//
// Inside a bypass loop the expected value and the copy of the result go to a source register
// the iteration no longer needs (it is reloaded at the loop head).
// The bypass loops count down from 2 (addi/bnez) instead of up to a limit held in x5.
// Values, NOP counts and test numbers are those of the upstream macros, so the rv64ui test
// bodies and their result tables are unchanged. Bodies that name registers directly were
// remapped onto the same set (riscv_tests/PROVENANCE.md).

#ifndef __TEST_MACROS_SCALAR_H
#define __TEST_MACROS_SCALAR_H


#-----------------------------------------------------------------------
# Helper macros
#-----------------------------------------------------------------------

#define MASK_XLEN(x) ((x) & ((1 << (__riscv_xlen - 1) << 1) - 1))

#define TEST_CASE( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    code; \
    .ifc testreg, x2; \
    li  x11, MASK_XLEN(correctval); \
    bne testreg, x11, fail; \
    .else; \
    li  x2, MASK_XLEN(correctval); \
    bne testreg, x2, fail; \
    .endif;

# We use a macro hack to simpify code generation for various numbers
# of bubble cycles.

#define TEST_INSERT_NOPS_0
#define TEST_INSERT_NOPS_1  nop; TEST_INSERT_NOPS_0
#define TEST_INSERT_NOPS_2  nop; TEST_INSERT_NOPS_1
#define TEST_INSERT_NOPS_3  nop; TEST_INSERT_NOPS_2
#define TEST_INSERT_NOPS_4  nop; TEST_INSERT_NOPS_3
#define TEST_INSERT_NOPS_5  nop; TEST_INSERT_NOPS_4
#define TEST_INSERT_NOPS_6  nop; TEST_INSERT_NOPS_5
#define TEST_INSERT_NOPS_7  nop; TEST_INSERT_NOPS_6
#define TEST_INSERT_NOPS_8  nop; TEST_INSERT_NOPS_7
#define TEST_INSERT_NOPS_9  nop; TEST_INSERT_NOPS_8
#define TEST_INSERT_NOPS_10 nop; TEST_INSERT_NOPS_9

#define LOAD_PTR lw
#define STORE_PTR sw

# Bypass loop: run the body twice.
#define TEST_LOOP_INIT  li  x2, 2;
#define TEST_LOOP_NEXT  addi x2, x2, -1; bnez x2, 1b

#-----------------------------------------------------------------------
# Tests for instructions with immediate operand
#-----------------------------------------------------------------------

#define SEXT_IMM(x) ((x) | (-(((x) >> 11) & 1) << 11))

#define TEST_IMM_OP( testnum, inst, result, val1, imm ) \
    TEST_CASE( testnum, x1, result, \
      li  x11, MASK_XLEN(val1); \
      inst x1, x11, SEXT_IMM(imm); \
    )

#define TEST_IMM_SRC1_EQ_DEST( testnum, inst, result, val1, imm ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      inst x11, x11, SEXT_IMM(imm); \
    )

#define TEST_IMM_DEST_BYPASS( testnum, nop_cycles, inst, result, val1, imm ) \
    TEST_CASE( testnum, x12, result, \
      TEST_LOOP_INIT \
1:    li  x11, MASK_XLEN(val1); \
      inst x1, x11, SEXT_IMM(imm); \
      TEST_INSERT_NOPS_ ## nop_cycles \
      addi  x12, x1, 0; \
      TEST_LOOP_NEXT \
    )

#define TEST_IMM_SRC1_BYPASS( testnum, nop_cycles, inst, result, val1, imm ) \
    TEST_CASE( testnum, x1, result, \
      TEST_LOOP_INIT \
1:    li  x11, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## nop_cycles \
      inst x1, x11, SEXT_IMM(imm); \
      TEST_LOOP_NEXT \
    )

#define TEST_IMM_ZEROSRC1( testnum, inst, result, imm ) \
    TEST_CASE( testnum, x11, result, \
      inst x11, x0, SEXT_IMM(imm); \
    )

#define TEST_IMM_ZERODEST( testnum, inst, val1, imm ) \
    TEST_CASE( testnum, x0, 0, \
      li  x11, MASK_XLEN(val1); \
      inst x0, x11, SEXT_IMM(imm); \
    )

#-----------------------------------------------------------------------
# Tests for an instruction with register-register operands
#-----------------------------------------------------------------------

#define TEST_RR_OP( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x1, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x1, x11, x12; \
    )

#define TEST_RR_SRC1_EQ_DEST( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x11, x11, x12; \
    )

#define TEST_RR_SRC2_EQ_DEST( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x12, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x12, x11, x12; \
    )

#define TEST_RR_SRC12_EQ_DEST( testnum, inst, result, val1 ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      inst x11, x11, x11; \
    )

#define TEST_RR_DEST_BYPASS( testnum, nop_cycles, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x12, result, \
      TEST_LOOP_INIT \
1:    li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x1, x11, x12; \
      TEST_INSERT_NOPS_ ## nop_cycles \
      addi  x12, x1, 0; \
      TEST_LOOP_NEXT \
    )

#define TEST_RR_SRC12_BYPASS( testnum, src1_nops, src2_nops, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x1, result, \
      TEST_LOOP_INIT \
1:    li  x11, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## src1_nops \
      li  x12, MASK_XLEN(val2); \
      TEST_INSERT_NOPS_ ## src2_nops \
      inst x1, x11, x12; \
      TEST_LOOP_NEXT \
    )

#define TEST_RR_SRC21_BYPASS( testnum, src1_nops, src2_nops, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x1, result, \
      TEST_LOOP_INIT \
1:    li  x12, MASK_XLEN(val2); \
      TEST_INSERT_NOPS_ ## src1_nops \
      li  x11, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## src2_nops \
      inst x1, x11, x12; \
      TEST_LOOP_NEXT \
    )

#define TEST_RR_ZEROSRC1( testnum, inst, result, val ) \
    TEST_CASE( testnum, x12, result, \
      li x11, MASK_XLEN(val); \
      inst x12, x0, x11; \
    )

#define TEST_RR_ZEROSRC2( testnum, inst, result, val ) \
    TEST_CASE( testnum, x12, result, \
      li x11, MASK_XLEN(val); \
      inst x12, x11, x0; \
    )

#define TEST_RR_ZEROSRC12( testnum, inst, result ) \
    TEST_CASE( testnum, x11, result, \
      inst x11, x0, x0; \
    )

#define TEST_RR_ZERODEST( testnum, inst, val1, val2 ) \
    TEST_CASE( testnum, x0, 0, \
      li x11, MASK_XLEN(val1); \
      li x12, MASK_XLEN(val2); \
      inst x0, x11, x12; \
    )

#-----------------------------------------------------------------------
# Test memory instructions
#-----------------------------------------------------------------------

#define TEST_LD_OP( testnum, inst, result, offset, base ) \
    TEST_CASE( testnum, x1, result, \
      la  x11, base; \
      inst x1, offset(x11); \
    )

#define TEST_ST_OP( testnum, load_inst, store_inst, result, offset, base ) \
    TEST_CASE( testnum, x1, result, \
      la  x11, base; \
      li  x12, result; \
      store_inst x12, offset(x11); \
      load_inst x1, offset(x11); \
    )

#define TEST_LD_DEST_BYPASS( testnum, nop_cycles, inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  la  x11, base; \
    inst x1, offset(x11); \
    TEST_INSERT_NOPS_ ## nop_cycles \
    addi  x12, x1, 0; \
    li  x11, result; \
    bne x12, x11, fail; \
    TEST_LOOP_NEXT; \

#define TEST_LD_SRC1_BYPASS( testnum, nop_cycles, inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  la  x11, base; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x1, offset(x11); \
    li  x11, result; \
    bne x1, x11, fail; \
    TEST_LOOP_NEXT \

#define TEST_ST_SRC12_BYPASS( testnum, src1_nops, src2_nops, load_inst, store_inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  li  x12, result; \
    TEST_INSERT_NOPS_ ## src1_nops \
    la  x11, base; \
    TEST_INSERT_NOPS_ ## src2_nops \
    store_inst x12, offset(x11); \
    load_inst x1, offset(x11); \
    li  x11, result; \
    bne x1, x11, fail; \
    TEST_LOOP_NEXT \

#define TEST_ST_SRC21_BYPASS( testnum, src1_nops, src2_nops, load_inst, store_inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  la  x11, base; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x12, result; \
    TEST_INSERT_NOPS_ ## src2_nops \
    store_inst x12, offset(x11); \
    load_inst x1, offset(x11); \
    li  x11, result; \
    bne x1, x11, fail; \
    TEST_LOOP_NEXT \

#define TEST_LD_ST_BYPASS(testnum, load_inst, store_inst, result, offset, base) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    la  x11, base; \
    li  x12, result; \
    store_inst x12, offset(x11); \
    load_inst x1, offset(x11); \
    store_inst x1, offset(x11); \
    load_inst x11, offset(x11); \
    li  x2, result; \
    bne x11, x2, fail; \
    la  x11, base; \
    STORE_PTR x11, 8(x11); \
    LOAD_PTR x1, 8(x11); \
    store_inst x12, offset(x1); \
    bne x1, x11, fail; \
    load_inst x11, offset(x1); \
    bne x11, x2, fail; \

#define TEST_ST_LD_BYPASS(testnum, load_inst, store_inst, result, offset, base) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    la  x11, base; \
    li  x12, result; \
    store_inst x12, offset(x11); \
    load_inst x1, offset(x11); \
    li  x11, result; \
    bne x1, x11, fail; \

#-----------------------------------------------------------------------
# Test branch instructions
#-----------------------------------------------------------------------

#define TEST_BR2_OP_TAKEN(testnum, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x11, val1; \
    li  x12, val2; \
    inst x11, x12, 2f; \
    bne x0, TESTNUM, fail; \
1:  bne x0, TESTNUM, 3f; \
2:  inst x11, x12, 1b; \
    bne x0, TESTNUM, fail; \
3:

#define TEST_BR2_OP_NOTTAKEN( testnum, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x11, val1; \
    li  x12, val2; \
    inst x11, x12, 1f; \
    bne x0, TESTNUM, 2f; \
1:  bne x0, TESTNUM, fail; \
2:  inst x11, x12, 1b; \
3:

#define TEST_BR2_SRC12_BYPASS( testnum, src1_nops, src2_nops, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  li  x11, val1; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x12, val2; \
    TEST_INSERT_NOPS_ ## src2_nops \
    inst x11, x12, fail; \
    TEST_LOOP_NEXT \

#define TEST_BR2_SRC21_BYPASS( testnum, src1_nops, src2_nops, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  li  x12, val2; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x11, val1; \
    TEST_INSERT_NOPS_ ## src2_nops \
    inst x11, x12, fail; \
    TEST_LOOP_NEXT \

#-----------------------------------------------------------------------
# Test jump instructions
#-----------------------------------------------------------------------

#define TEST_JR_SRC1_BYPASS( testnum, nop_cycles, inst ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  la  x1, 2f; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x1; \
    bne x0, TESTNUM, fail; \
2:  TEST_LOOP_NEXT \

#define TEST_JALR_SRC1_BYPASS( testnum, nop_cycles, inst ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    TEST_LOOP_INIT \
1:  la  x1, 2f; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x12, x1, 0; \
    bne x0, TESTNUM, fail; \
2:  TEST_LOOP_NEXT \

#-----------------------------------------------------------------------
# Pass and fail code (assumes test num is in TESTNUM)
#-----------------------------------------------------------------------

#define TEST_PASSFAIL \
        bne x0, TESTNUM, pass; \
fail: \
        RVTEST_FAIL; \
pass: \
        RVTEST_PASS \


#-----------------------------------------------------------------------
# Test data section
#-----------------------------------------------------------------------

#define TEST_DATA

#endif
