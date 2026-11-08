// ============================================================
//  regs_test.S -- fc32e1s_nano_fpga register-set test
//
//  The core has 6 registers: x0, x1, x2, x10..x12, mapped onto 5 physical
//  words (fc32e1s_nano_fpga_pkg::reg_phys; rev 1 had 8 with x13, x14). This test
//  exercises every one of them in every operand position, so a wrong mapping
//  (two architectural registers sharing a word, a register reading another
//  one's word, x0 written) shows up both in the lock-step trace and in the
//  self-checks below.
//
//    1  all 5 registers hold distinct values at the same time (stored, reloaded)
//    2  every register as rd, rs1 and rs2 of ALU ops (also rd == rs1 == rs2)
//    3  every register as rs1/rs2 of a branch (taken and not taken)
//    4  every register as the JAL / JALR link register, JALR base
//    5  every register as load destination and load/store base, rd == base
//    6  writes to x0 (ALU, LUI, AUIPC, load, JAL, JALR) are discarded
//    7  back-to-back read-after-write chains through all registers
//    8  FENCE (no-op on this core)
//
//  Checks: CHK a, b, n -> if a != b exit with code n (block number).
//  x10 is TEST_CNT, but CHK loads the code itself, so blocks may clobber x10.
// ============================================================
#include "test_env.h"

        .macro CHK a, b, n
        beq   \a, \b, 9f
        li    x10, \n
        j     fail
9:
        .endm

        // CHKI a, imm, h, n : a == imm (h = scratch register, != a)
        .macro CHKI a, imm, h, n
        li    \h, \imm
        CHK   \a, \h, \n
        .endm

        .section .text
        .global _start
_start:
        TEST_INIT

// ---------------------------------------------------------------- 1
// distinct values in all registers at once, stored and reloaded
        la    x2, buf
        li    x1,  0x11111111
        li    x10, 0xa0a0a0a0
        li    x11, 0x0b0b0b0b
        li    x12, 0xc0c0c0c0
        sw    x1,  0(x2)
        sw    x2,  4(x2)
        sw    x10, 8(x2)
        sw    x11, 12(x2)
        sw    x12, 16(x2)
        // read every register back as rs1 and rs2 before anything is overwritten
        xor   x1, x1, x12          // 0xd1d1d1d1
        xor   x12, x11, x10        // 0xabababab
        CHKI  x1,  0xd1d1d1d1, x11, 1
        CHKI  x12, 0xabababab, x11, 1
        // reload, each word into a different register
        lw    x12, 0(x2)
        CHKI  x12, 0x11111111, x11, 1
        lw    x11, 4(x2)
        CHK   x11, x2, 1
        lw    x1,  8(x2)
        CHKI  x1,  0xa0a0a0a0, x12, 1
        lw    x10, 12(x2)
        CHKI  x10, 0x0b0b0b0b, x1, 1
        lw    x10, 16(x2)
        CHKI  x10, 0xc0c0c0c0, x1, 1
        lw    x2,  0(x2)           // rd == base
        CHKI  x2,  0x11111111, x1, 1

// ---------------------------------------------------------------- 2
// ALU: every register as rd / rs1 / rs2, including rd == rs1 == rs2
        li    x1, 3
        add   x1, x1, x1           // 6
        CHKI  x1, 6, x12, 2
        li    x2, 5
        add   x2, x2, x2           // 10
        CHKI  x2, 10, x12, 2
        li    x10, 7
        add   x10, x10, x10        // 14
        CHKI  x10, 14, x12, 2
        li    x11, 9
        sub   x11, x11, x11        // 0
        CHK   x11, x0, 2
        li    x12, 1
        sll   x12, x12, x12        // 2
        CHKI  x12, 2, x11, 2
        li    x12, 0x55
        xor   x12, x12, x12
        CHK   x12, x0, 2
        // each register as rs2 with a different rs1/rd
        li    x1, 100
        li    x2, 20
        li    x10, 3
        li    x11, -1
        li    x12, 0x80000000
        sub   x1, x1, x2           // 80
        CHKI  x1, 80, x2, 2
        li    x2, 31
        sra   x1, x12, x2          // -1
        CHK   x1, x11, 2
        srl   x1, x12, x2          // 1
        CHKI  x1, 1, x2, 2
        slt   x2, x11, x10         // -1 < 3 -> 1
        CHKI  x2, 1, x1, 2
        sltu  x2, x11, x10         // 0xffffffff < 3 -> 0
        CHK   x2, x0, 2
        and   x2, x11, x12         // 0x80000000
        CHK   x2, x12, 2
        li    x2, 20
        add   x12, x2, x10         // 23
        CHKI  x12, 23, x1, 2
        addi  x12, x12, -23
        CHK   x12, x0, 2
        sltiu x11, x12, 1          // seqz
        CHKI  x11, 1, x1, 2
        srai  x10, x11, 1
        CHK   x10, x0, 2
        slli  x2, x11, 31
        srli  x2, x2, 30
        CHKI  x2, 2, x1, 2
        or    x1, x10, x11         // x10 as rs1, x11 as rs2
        CHKI  x1, 1, x12, 2

// ---------------------------------------------------------------- 3
// branches: every register as rs1 and rs2
        li    x1, 1
        li    x2, 2
        li    x10, 10
        li    x11, 11
        li    x12, 12
        bne   x1, x1, 3f
        beq   x2, x1, 3f
        blt   x11, x10, 3f
        bge   x11, x12, 3f
        bltu  x12, x11, 3f
        bgeu  x2, x12, 3f
        beq   x12, x12, 1f
        j     3f
1:      blt   x10, x12, 1f
        j     3f
1:      bge   x12, x11, 1f
        j     3f
1:      bltu  x10, x12, 1f
        j     3f
1:      bgeu  x2, x1, 1f
        j     3f
1:      bne   x1, x2, 1f
3:      li    x10, 3
        j     fail
1:

// ---------------------------------------------------------------- 4
// JAL / JALR: every register as link, every register as JALR base
        jal   x1, 1f
4:      j     40f
1:      la    x12, 4b
        CHK   x1, x12, 4
        jal   x2, 1f
        j     40f
1:      jal   x10, 1f
        j     40f
1:      jal   x11, 1f
        j     40f
1:      jal   x12, 1f
        j     40f
1:      // consecutive links are 8 bytes apart (jal + j)
        sub   x1, x12, x11
        CHKI  x1, 8, x11, 4
        // JALR through each base register, link into a different register
        la    x1, 1f
        jalr  x12, 0(x1)
        j     40f
1:      la    x2, 1f
        jalr  x11, x2, 0
        j     40f
1:      la    x10, 1f+4
        jalr  x12, -4(x10)
        j     40f
1:      la    x11, 1f
        jalr  x11, 0(x11)          // rd == rs1: target uses the old value
        j     40f
1:      la    x12, 1f
        jalr  x10, 0(x12)
        j     40f
1:      la    x11, 1f
        jalr  x2, 0(x11)
        j     40f
1:      la    x12, 1f
        jalr  x1, 0(x12)
        j     40f
1:      j     41f
40:     li    x10, 4
        j     fail
41:

// ---------------------------------------------------------------- 5
// loads into every register, every register as load/store base
        la    x2, buf
        li    x1, 0x12345678
        sw    x1, 28(x2)
        la    x12, buf
        lw    x11, 28(x12)
        CHK   x11, x1, 5
        mv    x11, x12
        lw    x10, 28(x11)
        CHK   x10, x1, 5
        mv    x10, x11
        lw    x12, 28(x10)
        CHK   x12, x1, 5
        lw    x2, 28(x10)
        CHK   x2, x1, 5
        mv    x1, x10
        lh    x12, 30(x1)          // 0x1234
        CHKI  x12, 0x1234, x11, 5
        lbu   x11, 28(x1)          // 0x78
        CHKI  x11, 0x78, x12, 5
        la    x2, buf
        lw    x1, 28(x2)
        CHKI  x1, 0x12345678, x12, 5
        // rd == base
        la    x12, buf+28
        lw    x12, 0(x12)
        CHKI  x12, 0x12345678, x11, 5
        // store data from each register, base from another
        la    x11, buf
        li    x12, 0x7e
        sb    x12, 32(x11)
        sb    x11, 33(x11)         // low byte of buf
        li    x10, -1
        sh    x10, 34(x11)
        lw    x1, 32(x11)
        andi  x12, x11, 0xff
        slli  x12, x12, 8
        ori   x12, x12, 0x7e
        lui   x2, 0xffff0
        or    x12, x12, x2
        CHK   x1, x12, 5

// ---------------------------------------------------------------- 6
// writes to x0 are discarded
        li    x11, 0x5a5a5a5a
        addi  x0, x11, 1
        add   x0, x11, x11
        lui   x0, 0x12345
        auipc x0, 0x1
        la    x1, buf
        lw    x0, 0(x1)
        jal   x0, 1f
1:      la    x12, 1f
        jalr  x0, 0(x12)
1:      j     61f
60:     li    x10, 6
        j     fail
61:     bnez  x0, 60b
        add   x12, x0, x0
        bnez  x12, 60b
        or    x12, x11, x0
        CHK   x12, x11, 6

// ---------------------------------------------------------------- 7
// back-to-back RAW through all registers
        li    x1, 1
        addi  x2, x1, 1            // 2
        add   x10, x2, x1          // 3
        add   x11, x10, x2         // 5
        add   x12, x11, x10        // 8
        add   x1, x12, x11         // 13
        add   x2, x1, x12          // 21
        add   x10, x2, x1          // 34
        add   x11, x10, x2         // 55
        add   x12, x11, x10        // 89
        add   x1, x12, x11         // 144
        add   x2, x1, x12          // 233
        add   x10, x2, x1          // 377
        add   x11, x10, x2         // 610
        CHKI  x11, 610, x1, 7
        // load -> use, store -> load
        la    x2, buf
        sw    x11, 36(x2)
        lw    x1, 36(x2)
        addi  x1, x1, 1
        sw    x1, 36(x2)
        lw    x12, 36(x2)
        CHKI  x12, 611, x11, 7

// ---------------------------------------------------------------- 8
        fence
        fence rw, rw
        li    x11, 8
        CHKI  x11, 8, x12, 8

pass:   TEST_PASS
fail:   TEST_FAIL

        .section .data
        .balign 4
buf:    .space 64
