#!/usr/bin/env bash
# build.sh -- builds a C program of this folder into the 2 KiB RAM image (link.ld).
#
#   ./build.sh nano  [prog]   # the nano cores: riscv32-nano-elf-gcc -mnano (6 registers)
#   ./build.sh rv32e [prog]   # SERV: stock GCC, plain RV32E (16 registers)
#
# prog defaults to cpi_test. Output in build/<abi>/: <prog>.elf / .dis; <prog>.hex (512 words,
# $readmemh, the testbenches); <prog>_0.hex .. <prog>_3.hex (one byte per line per RAM byte
# lane, the INIT_FILE of fc32e1s_nano_fpga_ram). A nano build is checked against the nano
# cores' registers (x0, ra, sp, a0..a2). Runs in WSL from Git Bash. Compilers: NANO_CC
# (default ~/opt/riscv32-nano/bin/riscv32-nano-elf-gcc), CC (default riscv64-unknown-elf-gcc).
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v cygpath >/dev/null 2>&1 && command -v wsl.exe >/dev/null 2>&1; then
  exec wsl.exe -e bash -lc "CC='${CC:-}' NANO_CC='${NANO_CC:-}' bash \"\$(wslpath -u '$(cygpath -w "$HERE/build.sh")')\" ${1:-} ${2:-}"
fi
ABI="${1:?usage: build.sh nano|rv32e [prog]}"
PROG="${2:-cpi_test}"
CFLAGS=(-march=rv32e -mabi=ilp32e -O2 -ffreestanding -fno-builtin -nostdlib -nostartfiles
        -fno-tree-loop-distribute-patterns -fno-ident -fno-asynchronous-unwind-tables)
case "$ABI" in
  nano)  CC="${NANO_CC:-$HOME/opt/riscv32-nano/bin/riscv32-nano-elf-gcc}"; CFLAGS+=(-mnano) ;;
  rv32e) CC="${CC:-riscv64-unknown-elf-gcc}" ;;
  *) echo "[!] unknown ABI $ABI (nano, rv32e)"; exit 1 ;;
esac
OBJCOPY="${CC%gcc}objcopy"
OBJDUMP="${CC%gcc}objdump"
OUT="$HERE/build/$ABI"; mkdir -p "$OUT"

"$CC" "${CFLAGS[@]}" -Wl,--no-warn-rwx-segments -T "$HERE/link.ld" "$HERE/crt0.S" "$HERE/$PROG.c" -o "$OUT/$PROG.elf"
"$OBJDUMP" -d -M no-aliases,numeric "$OUT/$PROG.elf" > "$OUT/$PROG.dis"
"$OBJCOPY" -O binary "$OUT/$PROG.elf" "$OUT/$PROG.bin"

if [ "$ABI" = nano ]; then           # registers: only x0 x1 x2 x10 x11 x12
  bad=$(grep -P '^\s+[0-9a-f]+:\t[0-9a-f]+\s+\t' "$OUT/$PROG.dis" \
        | grep -oP '\bx([3-9]|1[3-9]|[2-3][0-9])\b' | sort -u | tr '\n' ' ' || true)
  [ -z "$bad" ] || { echo "[!] $PROG uses registers the nano cores do not have: $bad"; exit 1; }
fi

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
echo "[i] $PROG ($ABI): $size B image -> build/$ABI/$PROG.hex, build/$ABI/${PROG}_{0..3}.hex"
