#!/usr/bin/env bash
# ============================================================
#  build_bootrom.sh -- assemble the boot ROM of the CPU subsystem (v2 hard macro) and
#                     regenerate example/subsystem/fc32e1s_nano_sram2k_v2_bootrom.sv
#
#  USAGE   ./build_bootrom.sh [source.S]     (default boot_spi.S)
#  Needs riscv64-unknown-elf-gcc (native or WSL) and python3 (same side).
#  fc32e1s_nano: RV32E, no C, registers x0 ra sp a0..a2 only (check bootrom.dis).
#  The ROM is fetch-only: the code must be pure text and fit 128 bytes (bootrom.ld checks).
# ============================================================
set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/../../.." && pwd)"                # cores/fc32e1s_nano
SRC="${1:-boot_spi.S}"
OUT="$CORE/sw/build/bootrom"
mkdir -p "$OUT"

BUILD='set -e
riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e -nostdlib -nostartfiles -Os \
  -x assembler-with-cpp -T "$H/bootrom.ld" "$H/$S" -o "$O/bootrom.elf"
riscv64-unknown-elf-objdump -d "$O/bootrom.elf" > "$O/bootrom.dis"
riscv64-unknown-elf-objcopy -O binary -j .text "$O/bootrom.elf" "$O/bootrom.bin"
python3 "$H/gen_bootrom.py" "$O/bootrom.bin" "$M/fc32e1s_nano_sram2k_v2_bootrom.sv" "$S"
# registers outside the subset make the core stop (illegal)
if grep -E -w "(t[0-6]|s[0-9]|s1[01]|a[3-7]|gp|tp)" "$O/bootrom.dis" | grep -v "file format"; then
  echo "[!] register outside x0 ra sp a0..a2"; exit 1
fi'

M="$CORE/example/subsystem"
if command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
  H="$HERE" O="$OUT" M="$M" S="$SRC" bash -c "$BUILD"
elif command -v wsl.exe >/dev/null 2>&1; then
  wp() { wsl.exe -e wslpath -u "$(cygpath -w "$1")" | tr -d '\r'; }
  wsl.exe -e bash -lc "H='$(wp "$HERE")' O='$(wp "$OUT")' M='$(wp "$M")' S='$SRC'; $BUILD"
else
  echo "[!] riscv64-unknown-elf toolchain not found (and no WSL)"; exit 127
fi
