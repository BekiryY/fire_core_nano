// libc.c -- picolibc built with -mnano: the routines with nano assembly versions (memcpy,
// memmove, memset, strcmp, setjmp / longjmp) and a few C ones that stress the 3-register
// ABI (snprintf with 5+ arguments, qsort's callback, strtol, 64-bit printf-free math).
// main returns 0 when every check passes, otherwise the number of the first failing check.
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static jmp_buf jb;
static volatile int depth;

__attribute__((noinline)) static void dive(int n)
{
    depth = n;
    if (n == 5)
        longjmp(jb, 42);
    dive(n + 1);
}

static int cmp(const void *a, const void *b)
{
    return *(const int *)a - *(const int *)b;
}

#define CHECK(n, cond) do { if (!(cond)) return n; } while (0)

int main(void)
{
    char a[64], b[64];
    for (int i = 0; i < 64; i++)
        a[i] = (char)(i * 7 + 1);

    memcpy(b, a, sizeof a);
    CHECK(1, memcmp(a, b, sizeof a) == 0);
    memmove(b + 3, b, 40);                      // overlapping, backward
    CHECK(2, b[3] == a[0] && b[42] == a[39] && b[2] == a[2]);
    memmove(b, b + 5, 30);                      // overlapping, forward
    CHECK(3, b[0] == a[2] && b[29] == a[31]);
    memset(b, 0x5A, 17);
    CHECK(4, b[0] == 0x5A && b[16] == 0x5A && b[17] != 0x5A);
    CHECK(5, memset(b, 0, 0) == b);

    CHECK(6, strcmp("abc", "abc") == 0);
    CHECK(7, strcmp("abc", "abd") < 0);
    CHECK(8, strcmp("abd", "abc") > 0);
    CHECK(9, strcmp("ab", "abc") < 0);
    CHECK(10, strcmp("\xff", "a") > 0);         // unsigned char compare

    int r = setjmp(jb);
    if (r == 0)
        dive(0);
    CHECK(11, r == 42 && depth == 5);

    snprintf(a, sizeof a, "%d|%5u|%-4x|%s|%c|%08lx", -123, 45u, 0xbeu, "ok", 'z', 0xC0FFEEul);
    CHECK(12, strcmp(a, "-123|   45|be  |ok|z|00c0ffee") == 0);

    int v[] = { 9, -3, 7, 0, 12, 5, -8, 1 };
    qsort(v, 8, sizeof v[0], cmp);
    for (int i = 1; i < 8; i++)
        CHECK(13, v[i - 1] <= v[i]);

    char *end;
    CHECK(14, strtol("  -0x1F zz", &end, 0) == -31 && *end == ' ');
    CHECK(15, strlen(strcpy(b, "nano")) == 4 && strchr(b, 'n') == b && strrchr(b, 'n') == b + 2);

    unsigned long long x = 0x123456789ull * 1000003u;
    CHECK(16, x / 1000003u == 0x123456789ull && x % 7 == (0x123456789ull * 1000003u) % 7);
    return 0;
}
