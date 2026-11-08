#!/usr/bin/env bash
# ============================================================
#  run_core_tests.sh -- FULL core regression: Spike ISS <-> RTL
#
#  Runs three stages in order and returns ONE exit code:
#    1) run_spike.sh               golden traces       (WSL/Linux)
#    2) ../core/run_core_rtl.sh    RTL traces (xsim)   (Windows Git Bash or Linux)
#    3) checker.py                 per-test trace comparison
#    4) coverage.py                instruction coverage (only if all matched)
#
#  USAGE
#    ./run_core_tests.sh                # all tests
#    ./run_core_tests.sh stres_test     # one test
#    SIM_SEED=7 ./run_core_tests.sh     # other random AXI wait-state pattern
#    AXI_WAITS=none ./run_core_tests.sh # zero-wait-state slaves
#    AXI_MEM=rtl ./run_core_tests.sh    # common/rtl axil_imem + axil_dmem
#
#  EXIT CODE
#    0    every test passed and every trace matched
#    1    at least one test or comparison failed
#    127  required tool missing
#
#  On Windows (Git Bash) the spike stage runs through WSL automatically;
#  on Linux everything runs natively.
# ============================================================
set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="$HERE"
# shellcheck source=core.cfg
source "$HERE/core.cfg"
mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

RED=''; GRN=''; YLW=''; BLD=''; RST=''
if [ -t 1 ]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; BLD=$'\033[1m'; RST=$'\033[0m'
fi

usage() { sed -n '2,22p' "$0" | sed 's|^# \?||'; exit 0; }
[ "${1:-}" = "-h" ] && usage
[ "${1:-}" = "--help" ] && usage

FILTER="${1:-}"
have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------
# Where does each stage run
# ------------------------------------------------------------
USE_WSL=0
if ! have spike || ! have riscv64-unknown-elf-gcc; then
  if have wsl.exe && wsl.exe -e bash -lc 'command -v spike >/dev/null' >/dev/null 2>&1; then
    USE_WSL=1
    WSL_HERE="$(wsl.exe -e wslpath -u "$(cygpath -w "$HERE")" 2>/dev/null | tr -d '\r')"
    [ -n "$WSL_HERE" ] || { echo "${RED}[!] cannot resolve WSL path (cygpath/wslpath)${RST}"; exit 127; }
  else
    echo "${RED}[!] spike / riscv64-unknown-elf-gcc not found, not in WSL either${RST}"; exit 127
  fi
fi

have xvlog && have xsim || {
  echo "${RED}[!] Vivado xsim not found (needed for the RTL stage)${RST}"; exit 127; }

# Native python: python3 first, then python (Windows often only has the latter;
# the WindowsApps python3 stub exists but does not run).
PY=""
for p in python3 python; do
  if have "$p" && "$p" -c "" >/dev/null 2>&1; then PY="$p"; break; fi
done
[ -n "$PY" ] || { echo "${RED}[!] python not found (checker.py needs it)${RST}"; exit 127; }

# ------------------------------------------------------------
# 1) golden traces
# ------------------------------------------------------------
echo "${BLD}=== 1/4  Spike ISS golden traces ===${RST}"
if [ "$USE_WSL" = 1 ]; then
  wsl.exe -e bash -lc "cd '$WSL_HERE' && ./run_spike.sh $FILTER"
else
  (cd "$HERE" && ./run_spike.sh "$FILTER")
fi || { echo "${RED}[!] spike stage failed -- not comparing${RST}"; exit 1; }
echo

# ------------------------------------------------------------
# 2) RTL traces
# ------------------------------------------------------------
echo "${BLD}=== 2/4  RTL traces ===${RST}"
# A failing TEST here does not stop the comparison (we still want to see where
# the traces diverge). A failing COMPILE leaves no fresh traces; the stamp
# check below catches that.
(cd "$HERE/../core" && ./run_core_rtl.sh $FILTER)
rtl_rc=$?
echo

# ------------------------------------------------------------
# 3) compare
# ------------------------------------------------------------
echo "${BLD}=== 3/4  Trace comparison ===${RST}"
STAMP="$BUILD_DIR/.rtl_run_stamp"
n_total=0; n_ok=0; n_bad=0; n_skip=0
declare -a FAILED=()

for grp in "${TEST_GROUPS[@]}"; do
  [ -d "$HERE/$grp/assembly" ] || continue
  for src in "$HERE/$grp"/assembly/*.[sS]; do
    [ -e "$src" ] || continue
    name="$(basename "$(basename "$src" .s)" .S)"
    [ -n "$FILTER" ] && [ "$name" != "$FILTER" ] && continue
    if [ -n "${SKIP[$name]+x}" ]; then n_skip=$((n_skip + 1)); continue; fi

    s_log="$BUILD_DIR/$grp/spike_logs/spike_$name.log"
    r_log="$BUILD_DIR/$grp/rtl_logs/rtl_$name.log"
    n_total=$((n_total + 1))
    printf '%-26s ' "$name"

    if [ ! -f "$s_log" ] || [ ! -f "$r_log" ]; then
      echo "${RED}TRACE MISSING${RST}"; n_bad=$((n_bad + 1)); FAILED+=("$name"); continue
    fi
    # STALE-TRACE GUARD: only compare traces produced by THIS run.
    if [ ! -f "$STAMP" ] || [ ! "$r_log" -nt "$STAMP" ]; then
      echo "${RED}STALE TRACE${RST} (not produced by this run -- did the RTL stage fail?)"
      n_bad=$((n_bad + 1)); FAILED+=("$name"); continue
    fi

    out="$("$PY" "$HERE/checker.py" "$(cygpath -m "$s_log" 2>/dev/null || echo "$s_log")" \
                                     "$(cygpath -m "$r_log" 2>/dev/null || echo "$r_log")" 2>&1)"
    if [ $? -eq 0 ]; then
      echo "${GRN}MATCH${RST} ($(echo "$out" | grep -oE '^rtl.*[0-9]+ komut' | grep -oE '[0-9]+ komut' | sed 's/komut/instr/'))"
      n_ok=$((n_ok + 1))
    else
      echo "${RED}MISMATCH${RST}"; echo "$out" | sed 's/^/    /'
      n_bad=$((n_bad + 1)); FAILED+=("$name")
    fi
  done
done

echo
echo "======================================================"
printf 'total %d   match %d   mismatch %d   skipped %d\n' "$n_total" "$n_ok" "$n_bad" "$n_skip"
[ "${#FAILED[@]}" -gt 0 ] && printf 'failed: %s\n' "${FAILED[*]}"
echo "======================================================"
echo

overall=0
[ "$n_total" = 0 ] && { echo "${RED}[!] no test ran (filter: '$FILTER')${RST}"; exit 2; }
[ "$n_bad" = 0 ] || overall=1
[ "$rtl_rc" = 0 ] || overall=1

# ------------------------------------------------------------
# 4) instruction coverage -- meaningful only once traces are verified
# ------------------------------------------------------------
if [ "$overall" = 0 ] && [ -z "$FILTER" ]; then
  echo "${BLD}=== 4/4  Instruction coverage ===${RST}"
  "$PY" "$HERE/coverage.py" --isa "$COVERAGE_ISA" \
        --root "$(cygpath -m "$BUILD_DIR" 2>/dev/null || echo "$BUILD_DIR")" \
        --md "$(cygpath -m "$BUILD_DIR/KAPSAM.md" 2>/dev/null || echo "$BUILD_DIR/KAPSAM.md")" \
    | tail -n 25 || echo "${YLW}[!] coverage report failed${RST}"
  echo
fi

if [ "$overall" = 0 ]; then
  echo "${GRN}${BLD}CORE REGRESSION PASSED${RST}"
else
  echo "${RED}${BLD}CORE REGRESSION FAILED${RST}"
fi
exit $overall
