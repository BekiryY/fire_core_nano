/* crt0.S -- start-up code of the nano cores (both targets; the linker script places it).
 * The program image is already in RAM (FPGA block RAM init / ASIC boot ROM copy), so .data
 * needs no copy. .bss is cleared, main() runs, its return value goes to _exit (bsp.c).
 * No constructors, no atexit handlers: picolibc's exit() would add ~200 B of code.
 * Registers: x0, ra, sp, a0..a2 only.
 */
        .section .text.start, "ax"
        .global _start
        .type   _start, @function
_start:
        la      sp, __stack
        la      a0, __bss_start
        la      a1, __bss_end
1:      bgeu    a0, a1, 2f
        sw      zero, 0(a0)
        addi    a0, a0, 4
        j       1b
2:      call    main
        tail    _exit
        .size   _start, .-_start
