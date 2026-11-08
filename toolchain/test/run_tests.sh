#!/usr/bin/env bash
# ============================================================
#  run_tests.sh -- acceptance test of an installed riscv32-nano-elf toolchain
#
#  abi.c (calls with 4-8 arguments, 64-bit arguments, varargs, structs, function pointers,
#  tail calls, a > 2 KiB frame, 64-bit division) and libc.c (picolibc's nano assembly,
#  setjmp / longjmp, snprintf, qsort, strtol) at -O0, -O2 and -Os:
#    1. every instruction uses only x0, ra, sp, a0..a2 (the nano cores' registers)
#    2. the program passes on Spike (spike --isa=rv32e), when spike is on PATH
#  Env: PREFIX (default $HOME/opt/riscv32-nano), OUT (default /tmp/riscv32-nano-test)
# ============================================================
set -u -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$HOME/opt/riscv32-nano}
OUT=${OUT:-/tmp/riscv32-nano-test}
T=$PREFIX/bin/riscv32-nano-elf
mkdir -p "$OUT"
command -v spike > /dev/null && SPIKE=1 || { SPIKE=0; echo "(spike not on PATH: register check only)"; }

fail=0
for src in "$HERE/abi.c" "$HERE/libc.c"; do
  name=$(basename "$src" .c)
  for opt in O0 O2 Os; do
    elf=$OUT/${name}_$opt.elf
    printf '%-10s ' "${name}_$opt"
    if ! "$T-gcc" -march=rv32e -mabi=ilp32e -mnano -"$opt" -Wall -nostdlib -T "$HERE/link.ld" \
         "$HERE/crt.S" "$src" -Wl,--start-group -lc -lgcc -Wl,--end-group -o "$elf" \
         2> "$OUT/${name}_$opt.err"; then
      echo "BUILD ERROR"; sed 's/^/    /' "$OUT/${name}_$opt.err"; fail=1; continue
    fi
    bad=$("$T-objdump" -d -M numeric,no-aliases "$elf" \
          | awk -F'\t' 'NF >= 4 { s = $4; sub(/[#<].*/, "", s); print s }' \
          | grep -oE '\bx[0-9]+\b' | sort -u | grep -vxE 'x(0|1|2|10|11|12)' | tr '\n' ' ')
    if [ -n "$bad" ]; then echo "ILLEGAL REGISTERS $bad"; fail=1; continue; fi
    text=$("$T-size" -A "$elf" | awk '$1 == ".text" { print $2 }')
    if [ $SPIKE = 0 ]; then echo "regs ok  (.text $text B)"; continue; fi
    if timeout 60 spike --isa=rv32e -m0x80000000:0x10000 "$elf" > "$OUT/${name}_$opt.log" 2>&1; then
      echo "PASS     (.text $text B)"
    else
      echo "FAIL     (exit $?, .text $text B)"; fail=1
    fi
  done
done
[ $fail = 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
