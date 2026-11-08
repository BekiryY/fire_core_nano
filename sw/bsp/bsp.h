/* bsp.h -- board support for the nano cores: console and program exit.
 * Each target (bsp/fpga, bsp/asic) implements these in its bsp.c; all are weak there, so a
 * program can supply its own (for example a different UART).
 */
#ifndef BSP_H
#define BSP_H

/* Peripherals sit at 0x800 - 0xFFF of the 12-bit data address space; software reaches them
 * as 0xFFFFF800 + offset (one sw/lw off x0, no lui). */
#define BSP_IO(off) (*(volatile unsigned *)(0xFFFFF800u + (off)))

void bsp_putc(char c);      /* write one character to the console */
int  bsp_getc(void);        /* read one character; -1 (EOF) when the target has no input */
void _exit(int code) __attribute__((noreturn));

#endif
