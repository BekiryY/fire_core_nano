/* crt0.S -- start-up for the fc32e1s_nano_fpga subsystem (reset PC 0x000).
 * The program image is the RAM's initial contents, so .data needs no copy; .bss is cleared
 * here (a reset without reloading the FPGA keeps the RAM as the last run left it).
 * Registers: x0, ra, sp, a0..a2 only. main()'s return ends the run with ECALL (halt).
 */
        .section .init, "ax"
        .global _start
_start:
        la    sp, _stack_top
        la    a0, _bss_start
        la    a1, _bss_end
1:      bgeu  a0, a1, 2f
        sw    zero, 0(a0)
        addi  a0, a0, 4
        j     1b
2:      call  main
        ecall
3:      j     3b
