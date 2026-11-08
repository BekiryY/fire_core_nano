/* crt0.S -- start-up of the CPI test (reset PC 0x000), the same for every core.
 * The program image is in RAM from the start (testbench / FPGA block RAM init), so .data needs
 * no copy; .bss is cleared (an FPGA reset without reconfiguration keeps the old RAM).
 * Registers: x0, ra, sp, a0..a2 only. After main the core spins: the testbench stops at the
 * KDONE write (no ECALL: SERV without CSRs has no defined ECALL behaviour).
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
3:      j     3b
