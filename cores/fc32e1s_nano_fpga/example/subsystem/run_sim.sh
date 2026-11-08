#!/usr/bin/env bash
# run_sim.sh -- builds a program (sw/build.sh) and runs it on fc32e1s_nano_fpga_top in xsim.
#
#   ./run_sim.sh [prog]        # default cpi_test; Git Bash on Windows or Linux, Vivado on PATH
#
# Work files go to build/ (not committed).
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/../.." && pwd)"
PROG="${1:-cpi_test}"
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

"$HERE/sw/build.sh" "$PROG"

WORK="$HERE/build/xsim"; mkdir -p "$WORK"; cd "$WORK"
{
  winpath "$CORE/rtl/fc32e1s_nano_fpga_pkg.sv"
  for f in "$CORE"/rtl/fc32e1s_nano_fpga_*.sv; do
    [[ "$f" == *_pkg.sv ]] || winpath "$f"
  done
  for f in ram subsystem top; do winpath "$HERE/fc32e1s_nano_fpga_$f.sv"; done
  winpath "$HERE/tb/tb_fc32e1s_nano_fpga_top.sv"
} > files.f
# The program image as image_{0..3}.hex in the work dir (the testbench's INIT_FILE "image_";
# the Windows xsim wrapper splits a -generic_top X=path argument at its "=").
for i in 0 1 2 3; do cp "$HERE/sw/build/${PROG}_$i.hex" "image_$i.hex"; done
xvlog -sv --nolog -f files.f > xvlog.log 2>&1 || { sed -n 1,40p xvlog.log; exit 1; }
xelab --nolog --timescale 1ns/1ps -s tb_snap tb_fc32e1s_nano_fpga_top > xelab.log 2>&1 || { sed -n 1,40p xelab.log; exit 1; }
xsim tb_snap --nolog --runall 2>&1 | grep -E "^  (kernel|all|run)|^(PASS|FAIL|TIMEOUT)|ERROR|Error"
