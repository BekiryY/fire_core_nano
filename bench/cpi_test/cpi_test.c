// cpi_test.c -- CPI test for every core of this repository (fc32e1s_nano_fpga,
// fc32e1s_nano_asic, SERV) and the fc32e1s_nano_fpga subsystem: one binary for all of them.
//
// Six small kernels, each bracketed by two writes to the SIM register; the testbench counts
// the clock cycles and the retired instructions between them, so no core needs counters:
//   SIM = KSTART | k     kernel k starts
//   SIM = result         kernel k ends (the next SIM write after a start)
//   SIM = KDONE | fail   end of the test: 0 all results correct, else 0x80 | first failing k
// On the FPGA board the LEDs show the outcome: 0x01 pass, 0x80 | k fail.
//
// Memory map (link.ld, the testbenches, the FPGA subsystem): RAM 0x000 - 0x7FF for code, data
// and stack; I/O at 0xFFFFF800 (one instruction off x0; the nano cores see 0x800 of their
// 12-bit data address).
//
// The nano cores have 6 registers (x0, ra, sp, a0..a2): at most 3 arguments per call, and no
// multiply / divide (RV32E without M, and libgcc's routines use other registers), so the
// kernels only add, shift and compare.

typedef unsigned int u32;

#define REG(off) (*(volatile u32 *)(0xFFFFF800u + (off)))
#define LED      REG(0x0)
#define SIM      REG(0xC)

#define KSTART   0x5A000000u
#define KDONE    0xD0000000u

#define N 16

static u32 data[N] = {
  0x3a, 0x91, 0x07, 0xc4, 0x5e, 0x22, 0xf0, 0x18,
  0x6d, 0xab, 0x40, 0x09, 0x77, 0xe5, 0x13, 0x8c
};
static u32 work[N];
static unsigned char buf[64];

// ---- kernels -------------------------------------------------------------
static u32 k_sum(void) {
  u32 s = 0;
  for (int i = 0; i < N; i++) s += data[i];
  return s;
}

static u32 k_fib(void) {
  u32 a = 0, b = 1;
  for (int i = 0; i < 40; i++) { u32 t = a + b; a = b; b = t; }
  return a;
}

static u32 k_crc(void) {
  u32 c = 0xFFFFFFFFu;
  for (int i = 0; i < N; i++) {
    c ^= data[i];
    for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & -(c & 1));
  }
  return ~c;
}

static u32 k_sort(void) {
  for (int i = 0; i < N; i++) work[i] = data[i];
  for (int i = 1; i < N; i++) {
    u32 v = work[i];
    int j = i - 1;
    while (j >= 0 && work[j] > v) { work[j + 1] = work[j]; j--; }
    work[j + 1] = v;
  }
  u32 s = 0;
  for (int i = 0; i < N; i++) s = (s << 1) ^ work[i];
  return s;
}

static u32 k_bytes(void) {
  for (int i = 0; i < 64; i++) buf[i] = (unsigned char)(i ^ 0x5a);
  u32 s = 0;
  for (int i = 63; i >= 0; i--) s = (s << 3) + buf[i] + (s >> 29);
  return s;
}

static u32 mul(u32 a, u32 b) {          // shift-and-add multiply
  u32 p = 0;
  while (b) { if (b & 1) p += a; a <<= 1; b >>= 1; }
  return p;
}

static u32 k_mul(void) {
  u32 s = 0;
  for (int i = 0; i < N; i++) s += mul(data[i], data[N - 1 - i]);
  return s;
}

// ---- driver ----------------------------------------------------------------
typedef u32 (*kernel_t)(void);

static const kernel_t kernels[] = { k_sum, k_fib, k_crc, k_sort, k_bytes, k_mul };
static const u32 expect[] = {
  0x0000067a, 0x06197ecb, 0x3e59f98c, 0x000332a2, 0xacd163a3, 0x00028460
};
#define NK (sizeof(kernels) / sizeof(kernels[0]))

int main(void) {
  u32 fail = 0;
  for (u32 k = 0; k < NK; k++) {
    SIM = KSTART | k;
    u32 r = kernels[k]();
    SIM = r;
    if (r != expect[k] && !fail) fail = 0x80 | k;
  }
  LED = fail ? fail : 0x01;
  SIM = KDONE | fail;
  return 0;
}
