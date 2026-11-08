/* bsp.c -- fc32e1s_nano_fpga example subsystem (cores/fc32e1s_nano_fpga/example/subsystem).
 *   0x800 LED      [7:0] the board LEDs
 *   0x80C SIM      simulation output: the console testbench (sim/) prints [7:0] as a character
 * _exit shows the result on the LEDs (0x01 = exit code 0, 0x80 | code otherwise) and stops the
 * core with ECALL (the core's halt output).
 */
#include "bsp.h"

#define LED BSP_IO(0x000)
#define SIM BSP_IO(0x00C)

__attribute__((weak)) void bsp_putc(char c)
{
    SIM = (unsigned char)c;
}

__attribute__((weak)) int bsp_getc(void)
{
    return -1;
}

__attribute__((weak)) void _exit(int code)
{
    LED = code == 0 ? 0x01 : 0x80 | (code & 0x7F);
    for (;;)
        __asm__ volatile("ecall");
}
