/* bsp.c -- fc32e1s_nano_asic subsystem (cores/fc32e1s_nano_asic/example/subsystem).
 * The subsystem ends at its peripheral port (0x800 - 0xFFF); the console here drives a UART
 * with the register layout of the FireCore nano MCU (tiny_uart):
 *   0x900 DATA   w: send [7:0]; r: received byte (clears rx_valid)
 *   0x904 STAT   [0] tx_busy, [1] rx_valid
 * Another peripheral set: define bsp_putc / bsp_getc / _exit in the program (these are weak).
 */
#include "bsp.h"

#define UART_DATA     BSP_IO(0x100)
#define UART_STAT     BSP_IO(0x104)
#define UART_TX_BUSY  (1u << 0)
#define UART_RX_VALID (1u << 1)

__attribute__((weak)) void bsp_putc(char c)
{
    while (UART_STAT & UART_TX_BUSY)
        ;
    UART_DATA = (unsigned char)c;
}

__attribute__((weak)) int bsp_getc(void)
{
    while (!(UART_STAT & UART_RX_VALID))
        ;
    return UART_DATA & 0xFF;
}

__attribute__((weak)) void _exit(int code)
{
    (void)code;
    while (UART_STAT & UART_TX_BUSY)    /* let the last character leave */
        ;
    for (;;)
        __asm__ volatile("ecall");
}
