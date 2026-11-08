/* printf_tiny.c -- printf / vprintf for 2 KiB programs, straight to bsp_putc.
 * picolibc's smallest printf (the "minimal" variant) is 1.4 KiB of code; this one is a few
 * hundred bytes. Conversions: %d %i %u %x %X %p %c %s %%, flags '0' and '-', a field width;
 * the 'l' / 'h' modifiers are accepted and ignored (int and long are both 32 bits). No
 * precision, no long long, no floating point. Returns the number of characters written.
 * Written for 6 registers: small helpers, few values live at once.
 * Make: PRINTF=tiny (default) links this file; PRINTF=m|i|d uses picolibc's printf instead.
 */
#include <stdarg.h>
#include <stdio.h>
#include "bsp.h"

#define LEFT 1                      /* '-' flag */
#define ZERO 2                      /* '0' flag */

static int count;

static void put(char c)
{
    count++;
    bsp_putc(c);
}

/* the digits of v in front of end; base 10, 16, or 16 | 32 (upper-case hex) */
static char *utoa(char *end, unsigned v, unsigned base)
{
    const char *digits = "0123456789abcdef0123456789ABCDEF" + (base & 32);
    base &= 31;
    *end = 0;
    do
        *--end = digits[v % base];
    while (v /= base);
    return end;
}

/* s padded to width; with ZERO a leading '-' goes before the zeros */
static void field(const char *s, int width, int flags)
{
    const char *e = s;
    while (*e)
        e++;
    width -= e - s;
    if (!(flags & LEFT)) {
        if ((flags & ZERO) && *s == '-')
            put(*s++);
        for (; width > 0; width--)
            put(flags & ZERO ? '0' : ' ');
    }
    while (*s)
        put(*s++);
    for (; width > 0; width--)
        put(' ');
}

int vprintf(const char *fmt, va_list ap)
{
    char buf[12];
    count = 0;
    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            put(*fmt);
            continue;
        }
        int flags = 0, width = 0;
        while (*++fmt == '-' || *fmt == '0')
            flags |= *fmt == '-' ? LEFT : ZERO;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + *fmt++ - '0';
        while (*fmt == 'l' || *fmt == 'h')
            fmt++;

        char *s = buf;
        int x;
        switch (*fmt) {
        case 0:
            return count;
        case 's':
            s = va_arg(ap, char *);
            if (!s)
                s = "(null)";
            break;
        case 'd':
        case 'i':
            x = va_arg(ap, int);
            s = utoa(buf + sizeof buf - 1, x < 0 ? -(unsigned)x : (unsigned)x, 10);
            if (x < 0)
                *--s = '-';
            break;
        case 'u':
            s = utoa(buf + sizeof buf - 1, va_arg(ap, unsigned), 10);
            break;
        case 'x':
        case 'p':
            s = utoa(buf + sizeof buf - 1, va_arg(ap, unsigned), 16);
            break;
        case 'X':
            s = utoa(buf + sizeof buf - 1, va_arg(ap, unsigned), 16 | 32);
            break;
        case 'c':
            buf[0] = (char)va_arg(ap, int);
            buf[1] = 0;
            break;
        default:                    /* %% and unknown conversions print the character */
            buf[0] = *fmt;
            buf[1] = 0;
        }
        field(s, width, flags);
    }
    return count;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vprintf(fmt, ap);
    va_end(ap);
    return n;
}
