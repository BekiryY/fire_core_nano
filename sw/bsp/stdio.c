/* stdio.c -- picolibc stdin/stdout/stderr on the BSP console (bsp_putc / bsp_getc, bsp.c).
 * Unbuffered: every character goes straight to the console, nothing to flush at exit.
 */
#include <stdio.h>
#include "bsp.h"

static int console_put(char c, FILE *f)
{
    (void)f;
    bsp_putc(c);
    return (unsigned char)c;
}

static int console_get(FILE *f)
{
    (void)f;
    return bsp_getc();
}

static FILE console = FDEV_SETUP_STREAM(console_put, console_get, NULL, _FDEV_SETUP_RW);

FILE *const stdin  = &console;
FILE *const stdout = &console;
FILE *const stderr = &console;
