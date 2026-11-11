#!/usr/bin/env bash
# run_power.sh -- CPU power and energy of the sky130 layouts, measured with the CPI test's real
# switching activity instead of a default activity factor.
#
#   NANO_FINAL=<run>/final SERV_FINAL=<run>/final ./run_power.sh          # both cores
#   ./run_power.sh nano                                                   # one of them
#
# Per core (nano = fc32e1s_nano_asic_hard, serv = serv_rf_top_latch, RV32E):
#   1. the CPI test image (../cpi_test/build.sh: nano -mnano, serv RV32E)
#   2. the layout's final netlist (zero-delay gate level, PDK cell models with FUNCTIONAL) runs it
#      in xsim at the signed-off clock (tb/tb_gl_<core>.sv), memory model outside the netlist
#   3. saif.tcl records every cell pin's toggles from reset release to the program's end (SAIF)
#   4. fix_saif.py, then OpenSTA: tt 025C 1v80 liberty, the layout's nom SPEF and SDC,
#      read_saif, report_power (vectorless too, for comparison)
# Output: build/<core>/ (power_vectorless.rpt, power_saif.rpt, summary.txt).
#
# Inputs (Linux paths): NANO_FINAL / SERV_FINAL = the LibreLane run's final/ folder (nl/, spef/,
# sdc/), PDK_ROOT (default ~/.ciel, sky130A), STA (default sta, the OpenSTA binary).
# Git Bash on Windows (xsim on PATH, the Linux steps in WSL; set MSYS_NO_PATHCONV=1 so Git Bash
# leaves the Linux paths alone) or Linux (xsim and sta on PATH).
set -u -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPI="$HERE/../cpi_test"

if command -v cygpath >/dev/null 2>&1 && command -v wsl.exe >/dev/null 2>&1; then
  lin() { wsl.exe -e bash -lc "$1"; }                        # Linux side in WSL
  LHERE=$(wsl.exe -e wslpath -u "$(cygpath -w "$HERE")" | tr -d '\r')
  winpath() { cygpath -m "$1"; }
else
  lin() { bash -lc "$1"; }
  LHERE="$HERE"
  winpath() { echo "$1"; }
fi

TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(nano serv)

rc=0
for t in "${TARGETS[@]}"; do
  case "$t" in
    nano) top=fc32e1s_nano_asic_hard; abi=nano;  period=27.7778; final="${NANO_FINAL:-}" ;;
    serv) top=serv_rf_top_latch;      abi=rv32e; period=13.2;    final="${SERV_FINAL:-}" ;;
    *) echo "[!] unknown target $t (nano, serv)"; rc=1; continue ;;
  esac
  [ -n "$final" ] || { echo "[!] $t: set ${t^^}_FINAL to the LibreLane run's final/ folder"; rc=1; continue; }
  W="$HERE/build/$t"; LW="$LHERE/build/$t"
  echo "== $t ($top, $period ns)"

  # 1-2. image, netlist, parasitics, constraints, cell models
  "$CPI/build.sh" "$abi" cpi_test > /dev/null || { rc=1; continue; }
  mkdir -p "$W"
  cp "$CPI/build/$abi/cpi_test.hex" "$W/image.hex"
  lin "set -e; P=\$(readlink -f ${PDK_ROOT:-\$HOME/.ciel}/sky130A)/libs.ref/sky130_fd_sc_hd
       cp '$final'/nl/$top.nl.v '$final'/spef/nom/$top.nom.spef '$LW'/
       cp '$final'/sdc/$top.sdc '$LW'/$top.sdc
       sed 's/\`default_nettype none/\`default_nettype wire/' \$P/verilog/primitives.v > '$LW'/primitives.v
       sed 's/\`default_nettype none/\`default_nettype wire/' \$P/verilog/sky130_fd_sc_hd.v > '$LW'/sky130_fd_sc_hd.v
       cp \$P/lib/sky130_fd_sc_hd__tt_025C_1v80.lib '$LW'/" || { echo "[!] $t: staging failed"; rc=1; continue; }

  # 2-3. gate-level simulation with the SAIF window
  cat > "$W/saif.tcl" <<EOF
run [expr {3.5 * $period + 0.01}] ns
open_saif act.saif
log_saif [get_objects -r /tb_gl/u_dut/*]
run -all
close_saif
quit
EOF
  ( cd "$W" &&
    { xvlog --nolog -d FUNCTIONAL -d UNIT_DELAY= primitives.v sky130_fd_sc_hd.v $top.nl.v \
        > xvlog_cells.log 2>&1 || { grep -m10 ERROR xvlog_cells.log; exit 1; }; } &&
    { xvlog --nolog -sv -i "$(winpath "$HERE/tb")" "$(winpath "$CPI/tb/cpi_monitor.sv")" \
        "$(winpath "$HERE/tb/tb_gl_$t.sv")" > xvlog_tb.log 2>&1 || { grep -m10 ERROR xvlog_tb.log; exit 1; }; } &&
    { xelab --nolog --debug typical --timescale 1ns/1ps -s snap tb_gl > xelab.log 2>&1 ||
        { grep -m10 ERROR xelab.log; exit 1; }; } &&
    xsim snap --nolog -tclbatch saif.tcl > xsim.log 2>&1
    grep -E " all |^WINDOW|^(PASS|FAIL)|TIMEOUT|ERROR" xsim.log
    grep -q "^PASS" xsim.log ) || { rc=1; continue; }

  # 4. power
  cat > "$W/power.tcl" <<EOF
read_liberty sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog $top.nl.v
link_design $top
read_sdc $top.sdc
read_spef $top.nom.spef
report_power -digits 4 > power_vectorless.rpt
read_saif -scope tb_gl/u_dut act_fix.saif
report_activity_annotation > annotation.rpt
report_power -digits 4 > power_saif.rpt
EOF
  lin "cd '$LW' && python3 '$LHERE/fix_saif.py' act.saif act_fix.saif &&
       ${STA:-sta} -no_splash -exit power.tcl > sta.log 2>&1" || { echo "[!] $t: OpenSTA failed (sta.log)"; rc=1; continue; }

  read -r cyc ins tns _ < <(sed -n 's/^WINDOW cycles \([0-9]*\) instr \([0-9]*\) time_ns \([0-9.]*\).*/\1 \2 \3/p' "$W/xsim.log")
  pv=$(awk '/^Total/ {print $5}' "$W/power_vectorless.rpt")
  ps=$(awk '/^Total/ {print $5}' "$W/power_saif.rpt")
  ann=$(awk '/^unannotated/ {print $2}' "$W/annotation.rpt")
  awk -v t="$t" -v c="$cyc" -v i="$ins" -v ns="$tns" -v pv="$pv" -v ps="$ps" -v u="$ann" 'BEGIN {
    e = ps * ns * 1e-9
    printf "%s: window %d cycles, %d instructions, %.1f us; unannotated pins %s\n", t, c, i, ns / 1e3, u
    printf "%s: power %.3f mW (vectorless %.3f mW); energy %.3f uJ, %.1f pJ/cycle, %.1f pJ/instruction\n",
           t, ps * 1e3, pv * 1e3, e * 1e6, e / c * 1e12, e / i * 1e12 }' | tee "$W/summary.txt"
done
exit $rc
