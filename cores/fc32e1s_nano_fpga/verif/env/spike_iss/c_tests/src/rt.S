// ============================================================
//  rt.S -- libgcc replacements for the fc32e1s_nano_fpga C tests
//
//  The prebuilt rv32e libgcc helpers use t0 (x5) and friends, which this core
//  does not have. These versions use only a0..a2, ra, sp (rev 2: no a3, a4).
//  The two loops need a fourth register: they save ra on the stack and use it
//  as the bit-test temporary / the iteration counter.
//    __mulsi3                 shift-and-add, 32 iterations max
//    __udivsi3 / __umodsi3    restoring division, 32 iterations
//    __divsi3  / __modsi3     signed wrappers (C semantics: truncate toward 0,
//                             remainder has the sign of the dividend)
//  Division by zero is not handled (not used by the tests).
// ============================================================
        .text
        .globl __mulsi3, __udivsi3, __umodsi3, __divsi3, __modsi3

__mulsi3:                       // a0 = a0 * a1
        addi  sp, sp, -4
        sw    ra, 0(sp)
        mv    a2, a0
        li    a0, 0
1:      andi  ra, a1, 1
        beqz  ra, 2f
        add   a0, a0, a2
2:      slli  a2, a2, 1
        srli  a1, a1, 1
        bnez  a1, 1b
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

__udivsi3:                      // a0 = a0 / a1, remainder left in a2
        addi  sp, sp, -4
        sw    ra, 0(sp)
        li    a2, 0
        li    ra, 32
1:      slli  a2, a2, 1         // remainder:dividend <<= 1
        bgez  a0, 2f
        ori   a2, a2, 1
2:      slli  a0, a0, 1
        bltu  a2, a1, 3f
        sub   a2, a2, a1
        ori   a0, a0, 1
3:      addi  ra, ra, -1
        bnez  ra, 1b
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

__umodsi3:                      // a0 = a0 % a1
        addi  sp, sp, -4
        sw    ra, 0(sp)
        call  __udivsi3
        mv    a0, a2
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret

__divsi3:                       // a0 = a0 / a1 (signed)
        addi  sp, sp, -8
        sw    ra, 4(sp)
        xor   a2, a0, a1        // sign of the quotient
        sw    a2, 0(sp)
        bgez  a0, 1f
        neg   a0, a0
1:      bgez  a1, 2f
        neg   a1, a1
2:      call  __udivsi3
        lw    a2, 0(sp)
        bgez  a2, 3f
        neg   a0, a0
3:      lw    ra, 4(sp)
        addi  sp, sp, 8
        ret

__modsi3:                       // a0 = a0 % a1 (signed, sign of the dividend)
        addi  sp, sp, -8
        sw    ra, 4(sp)
        sw    a0, 0(sp)
        bgez  a0, 1f
        neg   a0, a0
1:      bgez  a1, 2f
        neg   a1, a1
2:      call  __udivsi3
        mv    a0, a2
        lw    a2, 0(sp)
        bgez  a2, 3f
        neg   a0, a0
3:      lw    ra, 4(sp)
        addi  sp, sp, 8
        ret
