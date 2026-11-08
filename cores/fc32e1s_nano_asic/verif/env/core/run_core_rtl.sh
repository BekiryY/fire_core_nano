#!/usr/bin/env bash
# ============================================================
#  run_core_rtl.sh -- run the core tests on the core's RTL (xsim), write traces.
#  Core name comes from core.cfg (CORE_NAME); the script expects
#    <core>/rtl/<CORE_NAME>_pkg.sv + <CORE_NAME>_*.sv
#    ./<CORE_NAME>_tracer.sv  ./tb_<CORE_NAME>_spike.sv  (next to this script)
#
#  USAGE
#    ./run_core_rtl.sh                # all tests
#    ./run_core_rtl.sh stres_test     # one test
#    ./run_core_rtl.sh -h
#
#  INPUT   $BUILD_DIR/<group>/hex/<test>.hex (+ .dmem.hex)   from run_spike.sh
#  OUTPUT  $BUILD_DIR/<group>/rtl_logs/rtl_<test>.log       cut at tohost store
#          $BUILD_DIR/<group>/rtl_logs/rtl_<test>.raw.log   uncut
#  (BUILD_DIR comes from ../spike_iss/core.cfg)
#
#  REQUIRES  Vivado xsim on PATH. Runs in Git Bash on Windows or on Linux.
#
#  OPTIONS (environment)
#    SIM_SEED=<n>     xsim --sv_seed; selects the random wait-state pattern (default 1)
#    AXI_WAITS=none   zero-wait-state slaves (compiles with -d AXI_NO_WAIT)
#    AXI_MEM=rtl      synthesisable common/rtl axil_imem/axil_dmem instead of the
#                     random-wait models (compiles with -d USE_RTL_MEM)
#
#  The test image is copied to fixed names (imem.hex / dmem.hex) in the work
#  dir because the Windows xsim wrapper splits "--testplusarg X=path" at '='.
# ============================================================
set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$HERE/../spike_iss" && pwd)"
CORE_DIR="$(cd "$HERE/../../.." && pwd)"
REPO_DIR="$(cd "$CORE_DIR/../.." && pwd)"

CFG_DIR="$SPIKE_DIR"
# shellcheck source=../spike_iss/core.cfg
source "$SPIKE_DIR/core.cfg"
mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

# Windows-native paths for Vivado when running under Git Bash
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

usage() { sed -n '2,26p' "$0" | sed 's|^# \?||'; exit 0; }
[ "${1:-}" = "-h" ] && usage
[ "${1:-}" = "--help" ] && usage

RED=''; GRN=''; YLW=''; RST=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'; fi

missing=0
for t in xvlog xelab xsim; do
  command -v "$t" >/dev/null 2>&1 || { echo "${RED}[!] not found: $t${RST}"; missing=1; }
done
[ "$missing" = 1 ] && { echo "Vivado xsim required (source Vivado settings64)."; exit 127; }

FILTER="${1:-}"
SIM_SEED="${SIM_SEED:-1}"
AXI_WAITS="${AXI_WAITS:-rand}"
TB_DEFINES=""
[ "$AXI_WAITS" = none ] && TB_DEFINES="-d AXI_NO_WAIT"
[ "${AXI_MEM:-model}" = rtl ] && TB_DEFINES="$TB_DEFINES -d USE_RTL_MEM"
WORK="$BUILD_DIR/xsim_work"
TB_TOP="tb_${CORE_NAME}_spike"
SNAP="${TB_TOP}_snap"
TRACE="trace_${CORE_NAME}.log"
mkdir -p "$WORK"
cd "$WORK" || exit 1

# STALE-TRACE GUARD (1/2): remove the stamp BEFORE compiling. If compile or
# elaboration fails, no stamp exists and run_core_tests.sh treats every
# trace as stale instead of comparing leftovers from an earlier run.
STAMP="$BUILD_DIR/.rtl_run_stamp"
rm -f "$STAMP"

# ------------------------------------------------------------
# Compile once -- the design does not change between tests
# ------------------------------------------------------------
echo "== Compile ($MARCH${XVLOG_DEFINES:+, $XVLOG_DEFINES}${TB_DEFINES:+, $TB_DEFINES}) seed=$SIM_SEED =="
RTL="$CORE_DIR/rtl"
{
  winpath "$RTL/${CORE_NAME}_pkg.sv"             # package first
  for f in "$RTL"/"${CORE_NAME}"_*.sv; do
    [ "$(basename "$f")" = "${CORE_NAME}_pkg.sv" ] || winpath "$f"
  done
  # shared testbench models (core.cfg TB_COMMON_FILES, relative to <repo>/common/tb)
  for f in "${TB_COMMON_FILES[@]}"; do winpath "$REPO_DIR/common/tb/$f"; done
  # synthesisable shared RTL used by the TB (core.cfg COMMON_RTL_FILES, <repo>/common/rtl)
  for f in "${COMMON_RTL_FILES[@]}"; do winpath "$REPO_DIR/common/rtl/$f"; done
  # core-level wrappers outside rtl/ (core.cfg CORE_EXTRA_FILES, relative to the core dir)
  for f in "${CORE_EXTRA_FILES[@]}"; do winpath "$CORE_DIR/$f"; done
  winpath "$HERE/${CORE_NAME}_tracer.sv"
  winpath "$HERE/$TB_TOP.sv"
} > files.f

# XVLOG_DEFINES (core.cfg) selects the variant, e.g. "-d RV32E".
# shellcheck disable=SC2086
if ! xvlog -sv --nolog $XVLOG_DEFINES $TB_DEFINES -f files.f > xvlog.log 2>&1; then
  echo "${RED}[!] compile failed${RST}"; sed -n '1,40p' xvlog.log; exit 1
fi
if ! xelab --nolog --timescale 1ns/1ps -s "$SNAP" "$TB_TOP" > xelab.log 2>&1; then
  echo "${RED}[!] elaboration failed${RST}"; sed -n '1,60p' xelab.log; exit 1
fi
if grep -q "WARNING" xvlog.log xelab.log; then
  echo "${YLW}[!] compile warnings:${RST}"; grep -h "WARNING" xvlog.log xelab.log | sort -u | sed 's/^/    /'
fi
echo "   ok"
echo

# STALE-TRACE GUARD (2/2): compile succeeded -- stamp now.
: > "$STAMP"

n_total=0; n_pass=0; n_fail=0; n_skip=0

run_one() {
  local grp="$1" name="$2"
  local out="$BUILD_DIR/$grp"
  local hex="$out/hex/$name.hex"

  [ -n "$FILTER" ] && [ "$name" != "$FILTER" ] && return 0
  printf '%-26s ' "$name"

  if [ -n "${SKIP[$name]+x}" ]; then
    echo "${YLW}SKIP${RST} (${SKIP[$name]})"; n_skip=$((n_skip + 1)); return 0
  fi
  if [ ! -f "$hex" ]; then
    echo "${YLW}no hex -- run run_spike.sh first${RST}"; return 0
  fi

  # The image must be a single record at 0 (run_spike.sh rebases .text).
  local recs first_rec
  recs=$(grep -c "^@" "$hex")
  first_rec=$(grep -m1 "^@" "$hex")
  if [ "$recs" != 1 ] || [ "$first_rec" != "@00000000" ]; then
    echo "${RED}hex is not a single @00000000 record ($recs records, first '$first_rec')${RST}"
    n_total=$((n_total + 1)); n_fail=$((n_fail + 1)); return 0
  fi

  n_total=$((n_total + 1))
  mkdir -p "$out/rtl_logs"
  local raw="$out/rtl_logs/rtl_$name.raw.log"
  local log="$out/rtl_logs/rtl_$name.log"

  # Remove the previous trace and make sure it is really gone: on Windows a
  # finished xsim can hold the file handle briefly, and a leftover trace
  # would be attributed to this test.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    rm -f "$TRACE" 2>/dev/null; [ -f "$TRACE" ] || break; sleep 0.2
  done
  if [ -f "$TRACE" ]; then
    echo "${RED}previous trace could not be deleted${RST}"; n_fail=$((n_fail + 1)); return 0
  fi

  cp "$hex" imem.hex
  rm -f dmem.hex
  [ -f "$out/hex/$name.dmem.hex" ] && cp "$out/hex/$name.dmem.hex" dmem.hex

  local sim_out sim_rc
  sim_out=$(xsim "$SNAP" --nolog --sv_seed "$SIM_SEED" --runall 2>&1); sim_rc=$?

  if [ ! -f "$TRACE" ]; then
    echo "${RED}no trace produced (sim rc=$sim_rc)${RST}"
    echo "$sim_out" | sed -n '1,20p' | sed 's/^/    /'
    n_fail=$((n_fail + 1)); return 0
  fi
  cp "$TRACE" "$raw"

  # Cut at the last tohost store, inclusive -- same cut as the spike side.
  local cut instr_raw instr_cut
  cut=$(grep -n "PA:$TOHOST_ADDR" "$raw" | tail -1 | cut -d: -f1)
  instr_raw=$(($(wc -l < "$raw") - 1))    # minus header line
  if [ -n "$cut" ]; then
    head -n "$cut" "$raw" > "$log"; instr_cut=$((cut - 1))
  else
    cp "$raw" "$log"; instr_cut="$instr_raw"
  fi

  local tb_line verdict
  tb_line=$(echo "$sim_out" | grep -m1 "\[TB\] SONUC:")
  if echo "$tb_line" | grep -q "GECTI"; then
    verdict="${GRN}PASS${RST}"; n_pass=$((n_pass + 1))
  elif [ -z "$tb_line" ]; then
    verdict="${RED}no [TB] SONUC line (sim rc=$sim_rc)${RST}"; n_fail=$((n_fail + 1))
  else
    verdict="${RED}${tb_line#*SONUC: }${RST}"; n_fail=$((n_fail + 1))
  fi
  local cpi
  cpi=$(echo "$sim_out" | grep -m1 -oE 'CPI=[0-9.]+' || true)
  printf 'trace=%-6s (raw %-6s) %-9s %b\n' "$instr_cut" "$instr_raw" "$cpi" "$verdict"
}

for grp in "${TEST_GROUPS[@]}"; do
  [ -d "$SPIKE_DIR/$grp/assembly" ] || continue
  echo "-- $grp"
  for src in "$SPIKE_DIR/$grp"/assembly/*.[sS]; do
    [ -e "$src" ] || continue
    run_one "$grp" "$(basename "$(basename "$src" .s)" .S)"
  done
  echo
done

echo "======================================================"
printf 'total %d   pass %d   fail %d   skipped %d\n' "$n_total" "$n_pass" "$n_fail" "$n_skip"
echo "======================================================"

[ "$n_total" = 0 ] && { echo "${RED}[!] no test ran (filter: '${FILTER}')${RST}"; exit 2; }
[ "$n_fail" = 0 ] || exit 1
exit 0
