// EXPECT: 0xe6d2dd7b
// Register-pressure test: CRC, sort, matrix multiply (__mulsi3), utoa (__udivsi3/__umodsi3),
// 3-argument calls, struct copies, recursion. Returns a checksum; crt.S compares it with
// the EXPECT line above (value measured on spike, identical for 16 and 6 registers).
// 3 integer arguments is the limit: a 4th would silently go to a3 (x13), which the core
// does not have (rev 2; rev 1 had a3, a4 and a 5-argument mix5()).
typedef unsigned int u32;
static u32 seed = 12345;
static u32 rnd(void) { seed = seed * 1103515245u + 12345u; return seed >> 8; }

static u32 crc32(const unsigned char *p, int n) {
  u32 c = 0xFFFFFFFFu;
  for (int i = 0; i < n; i++) {
    c ^= p[i];
    for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & -(c & 1));
  }
  return ~c;
}
static void isort(int *a, int n) {
  for (int i = 1; i < n; i++) {
    int v = a[i], j = i - 1;
    while (j >= 0 && a[j] > v) { a[j + 1] = a[j]; j--; }
    a[j + 1] = v;
  }
}
#define N 6
static void matmul(int c[N][N], const int a[N][N], const int b[N][N]) {
  for (int i = 0; i < N; i++)
    for (int j = 0; j < N; j++) {
      int s = 0;
      for (int k = 0; k < N; k++) s += a[i][k] * b[k][j];
      c[i][j] = s;
    }
}
static int utoa(u32 v, char *s) {
  char t[12]; int n = 0, m = 0;
  do { t[n++] = '0' + v % 10; v /= 10; } while (v);
  while (n) s[m++] = t[--n];
  s[m] = 0;
  return m;
}
__attribute__((noinline)) static int mix3(int a, int b, int c) {
  return (a ^ (b << 3)) + (c - a) * 3 + (b >> 5);
}
struct pkt { u32 hdr, len, data[6]; };
__attribute__((noinline)) static u32 pkt_sum(struct pkt p) {
  u32 s = p.hdr + p.len;
  for (int i = 0; i < 6; i++) s = (s << 5) ^ (s >> 27) ^ p.data[i];
  return s;
}
static int depth(int n) { return n <= 1 ? 1 : depth(n - 1) + depth(n - 2) % 7; }

static unsigned char buf[256];
static int arr[64], ma[N][N], mb[N][N], mc[N][N];
static char str[16];

int main(void) {
  u32 sum = 0;
  for (int i = 0; i < 256; i++) buf[i] = rnd();
  sum ^= crc32(buf, 256);
  for (int i = 0; i < 64; i++) arr[i] = (int)(rnd() & 0xFFFF) - 0x8000;
  isort(arr, 64);
  for (int i = 0; i < 64; i++) sum = sum * 31 + arr[i];
  for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) { ma[i][j] = rnd() & 0xFF; mb[i][j] = rnd() & 0xFF; }
  matmul(mc, ma, mb);
  for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) sum += mc[i][j] ^ (i * 7 + j);
  for (int i = 0; i < 20; i++) { sum += utoa(rnd(), str); sum ^= (u32)str[0] << (i & 15); }
  for (int i = 0; i < 40; i++) sum += mix3(i, sum, rnd());
  struct pkt p = { 1, 6, { 1, 2, 3, 4, 5, 6 } };
  for (int i = 0; i < 10; i++) { p.data[i % 6] += sum; sum ^= pkt_sum(p); }
  sum += depth(14);
  return (int)sum;
}

// Struct copies call memcpy; this one is built with the same register restriction.
void *memcpy(void *d, const void *s, unsigned n) {
  char *dd = d; const char *ss = s;
  while (n--) *dd++ = *ss++;
  return d;
}
