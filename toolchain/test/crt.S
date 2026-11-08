/* crt.S -- Spike start-up for the toolchain tests: main() == 0 -> tohost 1 (pass),
 * otherwise tohost (code << 1) | 1 (spike exits with that code). Registers: x0 ra sp a0..a2.
 */
        .section .text.start, "ax"
        .global _start
_start:
        la      sp, __stack
        la      a0, __bss_start
        la      a1, __bss_end
1:      bgeu    a0, a1, 2f
        sw      zero, 0(a0)
        addi    a0, a0, 4
        j       1b
2:      call    main
        .global _exit
_exit:
        slli    a0, a0, 1
        ori     a0, a0, 1
        la      a1, tohost
        sw      a0, 0(a1)
3:      j       3b

        .section .tohost, "aw", @nobits
        .align  3
        .global tohost, fromhost
tohost:   .zero 8
fromhost: .zero 8
