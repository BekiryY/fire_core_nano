// ============================================================
//  crt.S -- start-up for the fc32e1s_nano_fpga C tests
//
//  Included at the end of every generated assembly/<test>.S (gen_tests.py),
//  which defines C_EXPECT (the EXPECT line of the C source) before it.
//  .init is placed first in IMEM by env/core_test.ld, so _start is the reset PC.
//  .data / .sdata are loaded by the TB from <test>.dmem.hex; .bss is not
//  cleared here because the TB DMEM and spike memory both start zeroed.
//
//  main() returns its checksum in a0:  == C_EXPECT -> TEST_PASS, else exit 1.
// ============================================================
#include "test_env.h"

        .section .init, "ax"
        .global _start
_start:
        la    sp, _stack_top
        call  main
        li    a1, C_EXPECT
        bne   a0, a1, 1f
        TEST_PASS
1:      TEST_FAIL_CODE 1
