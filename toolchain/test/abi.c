// -mnano ABI test (riscv32-nano-elf-gcc): calls the 6-register core could not make before
// -mnano -- 4 to 8 integer arguments, 64-bit arguments, variadic functions, structs passed
// and returned by value, function pointers, tail calls, a stack frame over 2 KB, 64-bit
// multiply / divide (libgcc). main returns 0 when the checksum is the host (cc) result.
// HOST build: cc -O2 -DHOST abi.c && ./a.out
typedef unsigned int u32;
typedef unsigned long long u64;
typedef __builtin_va_list va_list;
#define va_start(v, l) __builtin_va_start(v, l)
#define va_arg(v, t)   __builtin_va_arg(v, t)
#define va_end(v)      __builtin_va_end(v)

#define NOINLINE __attribute__((noinline))
static volatile u32 sink;                 // keeps arguments live across calls

NOINLINE static u32 arg4(u32 a, u32 b, u32 c, u32 d) { return a * 3 + b * 5 + c * 7 + d * 11; }
NOINLINE static u32 arg8(u32 a, u32 b, u32 c, u32 d, u32 e, u32 f, u32 g, u32 h) {
  return (a ^ (b << 1)) + (c ^ (d << 2)) + (e ^ (f << 3)) + (g ^ (h << 4));
}
NOINLINE static u64 arg64(u32 a, u64 b, u64 c) { return b * a + (c >> 3); }
NOINLINE static u32 mixed(u64 a, u32 b, u64 c, u32 d) { return (u32)(a >> 7) + b + (u32)(c % 1000003u) + d; }

NOINLINE static u32 vsum(int n, ...) {
  va_list ap;
  u32 s = 0;
  va_start(ap, n);
  for (int i = 0; i < n; i++) s = s * 31 + va_arg(ap, u32);
  va_end(ap);
  return s;
}
NOINLINE static u64 vsum64(int n, ...) {
  va_list ap;
  u64 s = 0;
  va_start(ap, n);
  for (int i = 0; i < n; i++) s += va_arg(ap, u64) << i;
  va_end(ap);
  return s;
}

struct pt { u32 x, y, z, w; };
NOINLINE static struct pt padd(struct pt a, struct pt b, u32 k) {
  struct pt r = { a.x + b.x * k, a.y + b.y * k, a.z + b.z * k, a.w + b.w * k };
  return r;
}
struct small { u32 lo, hi; };
NOINLINE static struct small swap(struct small s, u32 a, u32 b) {
  struct small r = { s.hi + a, s.lo + b };
  return r;
}

typedef u32 (*fn4)(u32, u32, u32, u32);
static fn4 volatile fptr = arg4;          // a real indirect call at every -O level
NOINLINE static u32 via_ptr(u32 a, u32 b, u32 c) { return fptr(a, b, c, a + b); }

NOINLINE static u32 tail_target(u32 a, u32 b, u32 c, u32 d, u32 e) { return a + b * c - d + e; }
NOINLINE static u32 tail_caller(u32 a, u32 b, u32 c) { return tail_target(c, b, a, 1, 2); }

NOINLINE static u32 big_frame(u32 seed) {   // > 2 KB of locals: sp adjusted in addi steps
  volatile u32 buf[700];
  for (int i = 0; i < 700; i++) buf[i] = seed + (u32)i * 2654435761u;
  u32 s = 0;
  for (int i = 0; i < 700; i += 7) s ^= buf[i] + (s << 1);
  return s;
}

NOINLINE static u32 recurse(u32 n, u32 a, u32 b, u32 c, u32 d) {
  return n == 0 ? a ^ b ^ c ^ d : recurse(n - 1, b, c, d, a + n) + 1;
}

static u32 run(void) {
  u32 h = 0;
  h = h * 33 + arg4(1, 2, 3, 4);
  h = h * 33 + arg8(1, 2, 3, 4, 5, 6, 7, 8);
  h = h * 33 + arg8(h, h >> 1, h >> 2, h >> 3, h >> 4, h >> 5, h >> 6, h >> 7);
  u64 r = arg64(7, 0x123456789abcdefull, 0xfedcba9876543210ull);
  h = h * 33 + (u32)r + (u32)(r >> 32);
  h = h * 33 + mixed(0x1122334455667788ull, 9, 0x8877665544332211ull, 10);
  h = h * 33 + vsum(6, 1u, 2u, 3u, 4u, 5u, 6u);
  h = h * 33 + vsum(0);
  u64 v = vsum64(3, 0x100000001ull, 0x200000002ull, 0x300000003ull);
  h = h * 33 + (u32)v + (u32)(v >> 32);
  struct pt a = { 1, 2, 3, 4 }, b = { 10, 20, 30, 40 };
  struct pt c = padd(a, b, 3);
  h = h * 33 + c.x + c.y * 2 + c.z * 3 + c.w * 4;
  struct small s = { 0xdead, 0xbeef };
  s = swap(s, 1, 2);
  h = h * 33 + s.lo * 7 + s.hi;
  h = h * 33 + via_ptr(5, 6, 5 ^ 6);
  h = h * 33 + tail_caller(3, 4, 5);
  h = h * 33 + big_frame(h);
  h = h * 33 + recurse(10, 1, 2, 3, 4);
  u64 m = (u64)h * 0x9e3779b97f4a7c15ull;
  h = h * 33 + (u32)(m / 1000000007u) + (u32)(m % 65521u);
  long long sd = (long long)(m ^ 0x8000000000000000ull) >> 3;
  long long sv = -(long long)(h | 1u) * 12345;
  h = h * 33 + (u32)(sd / sv) + (u32)(sd % sv) + (u32)(sd / 77) + (u32)(-sd % 77);
  sink = h;
  return h;
}

#ifdef HOST
#include <stdio.h>
int main(void) { printf("0x%08x\n", run()); return 0; }
#else
int main(void) { return run() != 0x294149aeu; }
#endif
