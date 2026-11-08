#!/usr/bin/env bash
# ============================================================
#  run_spike.sh -- assemble the core tests, run them on Spike ISS,
#                  produce the golden (reference) traces.
#
#  USAGE
#    ./run_spike.sh                # all tests
#    ./run_spike.sh stres_test     # one test by name
#    ./run_spike.sh -h
#
#  Per-core settings (ISA, memory map, tohost, skip list, output dir) come
#  from core.cfg next to this script.
#
#  OUTPUTS (per test, under $BUILD_DIR/<group>/)
#    elf/<test>.elf
#    hex/<test>.hex                IMEM image (.text only, verilog hex)
#    hex/<test>.dmem.hex           initialised data, rebased to 0 (if any)
#    dis/<test>.dis                objdump disassembly
#    spike_logs/spike_<test>.log   golden trace CUT at the tohost store (NOTE-2)
#    spike_logs/spike_<test>.raw.log  uncut spike output (for inspection)
#
#  NOTE-1 (END OF TEST)
#    Tests end through the HTIF tohost protocol (env/test_env.h):
#      exit 0 -> PASS,  exit N -> failure in test block N (TEST_CNT counter)
#    So every test is self-checking on Spike already; checker.py then
#    compares the RTL trace against this one instruction by instruction.
#
#  NOTE-2 (WHY THE TRACE IS CUT)
#    Spike polls HTIF only every INTERLEAVE steps, so after tohost is
#    written it may log the wait loop thousands more times (measured:
#    1 / 4973 / 4974 lines depending on log mode). That tail is a tool
#    artefact, so the golden trace is cut at the tohost store line
#    (inclusive). The RTL trace is cut the same way, which makes equal
#    trace length a valid check in checker.py.
#
#  NOTE-3 (ISA STRING)
#    Spike must run the same ISA as the core, otherwise the comparison is
#    meaningless. See SPIKE_ISA in core.cfg.
#
#  NOTE-4 (MEMORY MAP)
#    IMEM 0x8000_0000 (4 KB), DMEM 0x2000_0000 (8 KB). IMEM is not at 0x0
#    because spike's debug module lives there. See core.cfg, env/core_test.ld.
#
#  NOTE-5 (REGISTER SET)
#    fc32e1s_nano_asic only has x0, x1, x2, x10..x12 (TINY_REGS in core.cfg); the
#    RTL decodes any other register as illegal, spike does not know that.
#    Every assembled ELF is scanned; a test naming another register is a
#    build error.
#
#  NOTE-6 (GENERATED GROUPS)
#    If <group>/gen_tests.py exists it is run first and writes
#    <group>/assembly/ (generated, gitignored).
# ============================================================
set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

CFG_DIR="$HERE"
# shellcheck source=core.cfg
source "$HERE/core.cfg"

CC=${CC:-riscv64-unknown-elf-gcc}
OBJDUMP=${OBJDUMP:-riscv64-unknown-elf-objdump}
OBJCOPY=${OBJCOPY:-riscv64-unknown-elf-objcopy}
SPIKE=${SPIKE:-spike}
SPIKE_TIMEOUT=${SPIKE_TIMEOUT:-30}   # seconds; see run_one()

usage() {
  sed -n '2,44p' "$0" | sed 's|^# \?||'
  exit 0
}
[ "${1:-}" = "-h" ] && usage
[ "${1:-}" = "--help" ] && usage

RED=''; GRN=''; YLW=''; RST=''
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'; fi

# ------------------------------------------------------------
# Tool check -- fail early and clearly
# ------------------------------------------------------------
missing=0
for t in "$CC" "$OBJDUMP" "$OBJCOPY" "$SPIKE"; do
  command -v "$t" >/dev/null 2>&1 || { echo "${RED}[!] not found: $t${RST}"; missing=1; }
done
if [ "$missing" = 1 ]; then
  cat <<'EOF'

Required:
  riscv64-unknown-elf-gcc  (Ubuntu: apt install gcc-riscv64-unknown-elf)
                           with the rv32i/ilp32 multilib
  spike                    https://github.com/riscv-software-src/riscv-isa-sim
Does not run natively on Windows; use WSL or Linux.
EOF
  exit 127
fi

mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"

echo "== Tools =="
"$CC" --version | head -1
"$SPIKE" --help 2>&1 | head -1
echo "   core       : $CORE_NAME"
echo "   march      : $MARCH / $MABI"
echo "   spike ISA  : $SPIKE_ISA"
echo "   memory     : $SPIKE_MEM"
echo "   tohost     : 0x$TOHOST_ADDR"
echo "   output     : $BUILD_DIR"
echo

# ------------------------------------------------------------
# Assemble + run one test
# ------------------------------------------------------------
FILTER="${1:-}"

# Prints the registers outside TINY_REGS that any instruction of the ELF names
# (operand field of objdump -M numeric; symbol/comment annotations stripped).
check_regs() {
  "$OBJDUMP" -d -M numeric,no-aliases "$1" \
    | awk -F'\t' 'NF >= 4 { s = $4; sub(/[#<].*/, "", s); print s }' \
    | grep -oE '\bx[0-9]+\b' | sort -u \
    | while read -r r; do
        case " $TINY_REGS " in *" ${r#x} "*) ;; *) printf '%s ' "$r" ;; esac
      done
}

n_total=0; n_pass=0; n_fail=0; n_build_err=0; n_skip=0

run_one() {
  local grp="$1" src="$2"
  local name; name="$(basename "$(basename "$src" .s)" .S)"
  [ -n "$FILTER" ] && [ "$name" != "$FILTER" ] && return 0

  printf '%-26s ' "$name"

  if [ -n "${SKIP[$name]+x}" ]; then
    echo "${YLW}SKIP${RST} (${SKIP[$name]})"
    n_skip=$((n_skip + 1))
    return 0
  fi

  n_total=$((n_total + 1))
  local out="$BUILD_DIR/$grp"
  mkdir -p "$out/elf" "$out/hex" "$out/dis" "$out/spike_logs"

  local elf="$out/elf/$name.elf"
  local hex="$out/hex/$name.hex"
  local dhex="$out/hex/$name.dmem.hex"
  local dis="$out/dis/$name.dis"
  local raw="$out/spike_logs/spike_$name.raw.log"
  local log="$out/spike_logs/spike_$name.log"
  local err="$out/elf/$name.build.err"

  # --- per-test -march override ---
  # A test may select its own ISA with "# MARCH: <isa>" in its first 10 lines.
  local march
  march=$(sed -n '1,10p' "$src" | sed -n 's/^[[:space:]]*#[[:space:]]*MARCH:[[:space:]]*//p' | head -1)
  [ -z "$march" ] && march="$MARCH"

  # riscv_tests pull upstream bodies and macros from their own dirs;
  # riscv_tests/env/riscv_test.h is the local frame.
  local extra_inc=""
  if [ "$grp" = "riscv_tests" ]; then
    extra_inc="-Iriscv_tests/env -Iriscv_tests/macros -Iriscv_tests/rv64ui"
  fi

  # --- assemble ---
  if ! "$CC" -march="$march" -mabi="$MABI" -nostdlib -nostartfiles -g \
             -x assembler-with-cpp -I env $extra_inc -T env/core_test.ld \
             "$src" -o "$elf" 2> "$err"; then
    echo "${RED}BUILD ERROR${RST}"
    sed 's/^/    /' "$err"
    n_build_err=$((n_build_err + 1))
    return 0
  fi
  rm -f "$err"

  "$OBJDUMP" -d "$elf" > "$dis"

  # --- register set (NOTE-5) ---
  local badregs
  badregs=$(check_regs "$elf")
  if [ -n "$badregs" ]; then
    echo "${RED}ILLEGAL REGS${RST} (${badregs}-- allowed: x{$TINY_REGS})"
    n_build_err=$((n_build_err + 1))
    return 0
  fi

  # --- IMEM hex: .text ONLY ---
  # -j .text keeps initialised data from adding a second @20000000 record
  # to the image the TB loads into IMEM.
  # Rebased to 0 so the TB IMEM array starts at index 0.
  "$OBJCOPY" -O verilog -j .text --change-addresses=-"$IMEM_BASE" "$elf" "$hex"

  # --- DMEM hex: initialised data, rebased so the TB array starts at 0 ---
  "$OBJCOPY" -O verilog -j .rodata -j .srodata -j .data -j .sdata \
             --change-addresses=-"$DMEM_BASE" "$elf" "$dhex" 2>/dev/null || : > "$dhex"
  [ -s "$dhex" ] || rm -f "$dhex"

  # --- spike ---
  # timeout is mandatory: a test that never writes tohost runs Spike forever.
  timeout --foreground "$SPIKE_TIMEOUT" \
    "$SPIKE" --isa="$SPIKE_ISA" -m"$SPIKE_MEM" \
             --log-commits --log="$raw" "$elf" > "$raw.stdout" 2> "$raw.stderr"
  local rc=$?
  local timed_out=0
  [ "$rc" = 124 ] && timed_out=1

  # --- golden trace: cut at the (last) tohost store, inclusive ---
  local cut
  cut=$(grep -n "mem 0x$TOHOST_ADDR " "$raw" | tail -1 | cut -d: -f1)
  local instr_raw instr_cut
  instr_raw=$(wc -l < "$raw")
  if [ -n "$cut" ]; then
    head -n "$cut" "$raw" > "$log"
    instr_cut="$cut"
  else
    cp "$raw" "$log"
    instr_cut="$instr_raw"
  fi

  [ -s "$raw.stdout" ] || rm -f "$raw.stdout"
  [ -s "$raw.stderr" ] || rm -f "$raw.stderr"

  local uniq_pc
  uniq_pc=$(grep -oE ' 0x[0-9a-f]{8} \(' "$log" | sort -u | wc -l)

  local verdict
  if [ "$timed_out" = 1 ]; then
    verdict="${RED}TIMEOUT ${SPIKE_TIMEOUT}s (tohost never written?)${RST}"
    n_fail=$((n_fail + 1))
  elif [ -z "$cut" ]; then
    verdict="${YLW}no tohost store (did not end via HTIF)${RST}"
    n_fail=$((n_fail + 1))
  elif [ "$rc" = 0 ]; then
    verdict="${GRN}PASS${RST}"
    n_pass=$((n_pass + 1))
  else
    verdict="${RED}FAIL (block TEST_CNT=$rc)${RST}"
    n_fail=$((n_fail + 1))
  fi

  printf 'exit=%-3s trace=%-6s (raw %-6s) uniq_pc=%-4s %b\n' \
         "$rc" "$instr_cut" "$instr_raw" "$uniq_pc" "$verdict"
}

for grp in "${TEST_GROUPS[@]}"; do
  if [ -f "$grp/gen_tests.py" ]; then
    python3 "$grp/gen_tests.py" || { echo "${RED}[!] $grp/gen_tests.py failed${RST}"; exit 1; }
  fi
done

for grp in "${TEST_GROUPS[@]}"; do
  [ -d "$grp/assembly" ] || continue
  echo "-- $grp"
  for src in "$grp"/assembly/*.[sS]; do
    [ -e "$src" ] || continue
    run_one "$grp" "$src"
  done
  echo
done

echo "======================================================"
printf 'total %d   pass %d   fail %d   build_error %d   skipped %d\n' \
       "$n_total" "$n_pass" "$n_fail" "$n_build_err" "$n_skip"
echo "======================================================"

if [ "$n_total" = 0 ]; then
  echo "${RED}[!] no test ran (filter: '${FILTER}')${RST}"
  exit 2
fi
[ "$n_fail" = 0 ] && [ "$n_build_err" = 0 ] || exit 1
exit 0
