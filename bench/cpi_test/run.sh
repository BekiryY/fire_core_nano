#!/usr/bin/env bash
# run.sh -- builds the CPI test (build.sh) and runs it in xsim on each target.
#
#   ./run.sh                          # all targets
#   ./run.sh serv fc32e1s_nano_asic   # some of them
#
# Targets:
#   fc32e1s_nano_fpga       the FPGA core alone          (tb/tb_cpi_nano.sv)
#   fc32e1s_nano_asic       the ASIC core alone          (tb/tb_cpi_nano.sv)
#   serv                    SERV, RV32E latch register file (tb/tb_cpi_serv.sv)
#   fc32e1s_nano_fpga_sub   the FPGA subsystem board top (tb/tb_cpi_fpga_subsystem.sv)
# Git Bash on Windows or Linux, Vivado xsim on PATH. Work files: build/xsim_<target>/.
set -u -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(fc32e1s_nano_fpga fc32e1s_nano_asic serv fc32e1s_nano_fpga_sub)

"$HERE/build.sh" cpi_test || exit 1

core_files() {                      # <core>: package first, then the other rtl/<core>_*.sv
  local d="$REPO/cores/$1/rtl"
  winpath "$d/$1_pkg.sv"
  for f in "$d"/"$1"_*.sv; do [[ "$f" == *_pkg.sv ]] || winpath "$f"; done
}

rc=0
for t in "${TARGETS[@]}"; do
  W="$HERE/build/xsim_$t"; mkdir -p "$W"
  cp "$HERE/build/cpi_test.hex" "$W/image.hex"
  for i in 0 1 2 3; do cp "$HERE/build/cpi_test_$i.hex" "$W/image_$i.hex"; done
  {
    case "$t" in
      fc32e1s_nano_fpga|fc32e1s_nano_asic)
        core_files fc32e1s_nano_fpga; core_files fc32e1s_nano_asic
        top=tb_cpi_${t#fc32e1s_}; tbf=tb_cpi_nano.sv ;;
      serv)
        for f in alu bufreg bufreg2 csr ctrl decode immdec mem_if rf_if rf_ram_if state aligner \
                 compdec top; do winpath "$REPO/cores/serv/rtl/serv_$f.v"; done
        winpath "$REPO/common/rtl/regfile/rf32x32_2r1w_latch.sv"
        winpath "$REPO/cores/serv/appl/sky130_latch_rf/rtl/serv_rf_top_latch.sv"
        top=tb_cpi_serv; tbf=tb_cpi_serv.sv ;;
      fc32e1s_nano_fpga_sub)
        core_files fc32e1s_nano_fpga
        for f in ram subsystem top; do
          winpath "$REPO/cores/fc32e1s_nano_fpga/example/subsystem/fc32e1s_nano_fpga_$f.sv"
        done
        top=tb_cpi_fpga_subsystem; tbf=tb_cpi_fpga_subsystem.sv ;;
      *) echo "[!] unknown target $t"; rc=1; continue ;;
    esac
    winpath "$HERE/tb/cpi_monitor.sv"
    winpath "$HERE/tb/$tbf"
  } > "$W/files.f"
  echo "== $t"
  ( cd "$W" &&
    { xvlog -sv --nolog -f files.f > xvlog.log 2>&1 || { sed -n 1,30p xvlog.log; exit 1; }; } &&
    { xelab --nolog --timescale 1ns/1ps -s snap "$top" > xelab.log 2>&1 || { grep -m20 ERROR xelab.log; exit 1; }; } &&
    xsim snap --nolog --runall > xsim.log 2>&1
    grep -E " kernel | all |^(PASS|FAIL)|TIMEOUT|ERROR" xsim.log
    grep -q "^PASS" xsim.log ) || rc=1
done
exit $rc
