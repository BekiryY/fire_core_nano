#!/usr/bin/env bash
# build.sh -- builds a C program of this folder into the 2 KiB RAM image (link.ld).
#
#   ./build.sh [prog]          # default cpi_test: <prog>.c -> build/<prog>.hex, build/<prog>_{0..3}.hex
#   CC=riscv32-nano-elf-gcc ./build.sh   # the 6-register GCC (-mnano) instead of -ffixed-*
#
# Output: <prog>.elf / .dis; <prog>.hex (512 words, $readmemh, the testbenches);
# <prog>_0.hex .. <prog>_3.hex (one byte per line per RAM byte lane, the INIT_FILE of
# fc32e1s_nano_fpga_ram). Every instruction is checked against the nano cores' registers
# (x0, ra, sp, a0..a2). Runs in WSL from Git Bash.
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v cygpath >/dev/null 2>&1 && command -v wsl.exe >/dev/null 2>&1; then
  exec wsl.exe -e bash -lc "CC='${CC:-}' bash \"\$(wslpath -u '$(cygpath -w "$HERE/build.sh")')\" ${1:-}"
fi
PROG="${1:-cpi_test}"
CC="${CC:-riscv64-unknown-elf-gcc}"
OBJCOPY="${OBJCOPY:-${CC%gcc}objcopy}"
OBJDUMP="${OBJDUMP:-${CC%gcc}objdump}"
OUT="$HERE/build"; mkdir -p "$OUT"

CFLAGS=(-march=rv32e -mabi=ilp32e -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles
        -fno-tree-loop-distribute-patterns -fno-ident -fno-asynchronous-unwind-tables)
if [[ "$CC" == *riscv32-nano-elf* ]]; then
  CFLAGS+=(-mnano)
else
  CFLAGS+=(-ffixed-gp -ffixed-tp -ffixed-t0 -ffixed-t1 -ffixed-t2 -ffixed-s0 -ffixed-s1
           -ffixed-a3 -ffixed-a4 -ffixed-a5)
fi

"$CC" "${CFLAGS[@]}" -Wl,--no-warn-rwx-segments -T "$HERE/link.ld" "$HERE/crt0.S" "$HERE/$PROG.c" -o "$OUT/$PROG.elf"
"$OBJDUMP" -d -M no-aliases,numeric "$OUT/$PROG.elf" > "$OUT/$PROG.dis"
"$OBJCOPY" -O binary "$OUT/$PROG.elf" "$OUT/$PROG.bin"

# registers: only x0 x1 x2 x10 x11 x12
bad=$(grep -P '^\s+[0-9a-f]+:\t[0-9a-f]+\s+\t' "$OUT/$PROG.dis" \
      | grep -oP '\bx([3-9]|1[3-9]|[2-3][0-9])\b' | sort -u | tr '\n' ' ' || true)
[ -z "$bad" ] || { echo "[!] $PROG uses registers the nano cores do not have: $bad"; exit 1; }

python3 - "$OUT/$PROG.bin" "$OUT/$PROG" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
assert len(data) <= 2048, f"image {len(data)} B > 2 KiB"
data = data.ljust(2048, b"\0")
with open(f"{sys.argv[2]}.hex", "w") as f:
    f.write("".join(f"{int.from_bytes(data[4 * w:4 * w + 4], 'little'):08x}\n" for w in range(512)))
for lane in range(4):
    with open(f"{sys.argv[2]}_{lane}.hex", "w") as f:
        f.write("".join(f"{data[4 * w + lane]:02x}\n" for w in range(512)))
PY
size=$(stat -c %s "$OUT/$PROG.bin")
echo "[i] $PROG: $size B image -> build/$PROG.hex, build/${PROG}_{0..3}.hex"
