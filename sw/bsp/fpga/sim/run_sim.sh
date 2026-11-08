#!/usr/bin/env bash
# run_sim.sh [prog] -- runs build/fpga/<prog> (make TARGET=fpga PROG=<prog>, default hello) on the
# fc32e1s_nano_fpga example subsystem in xsim and prints its console output.
# Git Bash on Windows or Linux, Vivado on PATH. Work files go to build/fpga/xsim/.
set -eu -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SW="$(cd "$HERE/../../.." && pwd)"
REPO="$(cd "$SW/.." && pwd)"
CORE="$REPO/cores/fc32e1s_nano_fpga"
EX="$CORE/example/subsystem"
PROG="${1:-hello}"
IMG="$SW/build/fpga/$PROG"
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

[ -f "${IMG}_0.hex" ] || { echo "run_sim.sh: ${IMG}_0.hex missing: make TARGET=fpga PROG=$PROG first"; exit 1; }
WORK="$SW/build/fpga/xsim"; mkdir -p "$WORK"; cd "$WORK"
{
  winpath "$CORE/rtl/fc32e1s_nano_fpga_pkg.sv"
  for f in "$CORE"/rtl/fc32e1s_nano_fpga_*.sv; do
    [[ "$f" == *_pkg.sv ]] || winpath "$f"
  done
  for f in ram subsystem top; do winpath "$EX/fc32e1s_nano_fpga_$f.sv"; done
  winpath "$HERE/tb_console.sv"
} > files.f
for i in 0 1 2 3; do cp "${IMG}_$i.hex" "image_$i.hex"; done
xvlog -sv --nolog -f files.f > xvlog.log 2>&1 || { sed -n 1,40p xvlog.log; exit 1; }
xelab --nolog --timescale 1ns/1ps -s tb_snap tb_console > xelab.log 2>&1 || { sed -n 1,40p xelab.log; exit 1; }
xsim tb_snap --nolog --runall 2>&1   | grep -vE 'Copyright|^\s*\*\*|^(Vivado Simulator|INFO:|source |# |Time resolution|run -all|exit)|\$finish'   | sed '/^\s*$/d'
