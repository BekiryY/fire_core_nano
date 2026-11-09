# fc32e1s_nano_asic verification

Every committed instruction is compared against Spike (`--isa=rv32e`): PC, instruction word,
register write, memory address and store data. The core runs behind AXI4-Lite slaves with a
protocol checker on each master (any AXI rule violation fails the test) and a deadlock
watchdog (no commit for 1000 cycles).

```bash
cd env/spike_iss && ./run_core_tests.sh       # random wait states (default); Spike via WSL
SIM_SEED=7 ./run_core_tests.sh                # another wait-state pattern
AXI_WAITS=none ./run_core_tests.sh            # zero-wait slave models
AXI_MEM=rtl ./run_core_tests.sh               # synthesisable common/rtl axil_imem + axil_dmem
```

| Run | Spike match | Skipped | Coverage | CPI |
|---|---|---|---|---|
| random waits, seed 1 | 41/41 | 19 | 38/38 | 5.8-8.0 |
| zero-wait models | 41/41 | 19 | 38/38 | 3.01-3.71 |
| RTL `axil_imem`/`axil_dmem` | 41/41 | 19 | 38/38 | 3.01-3.71 |

Skips (with reasons) are in `env/spike_iss/core.cfg`: 14 need M, C, Zicsr or traps, 5 use
x16..x31. Tests that run here use `TEST_CNT` (x15 on RV32E) from `env/test_env.h`.

The x16..x31-are-illegal rule cannot be checked against Spike (the assembler refuses those
registers and Spike would trap). Checked directly in the TB: `addi x16,x0,1`, `addi x1,x16,0`
and `add x1,x0,x16` each stop the core with `illegal` at that instruction (re-checked on the AXI4-Lite version), while a preceding
`lui x1,0xfffff` (immediate bits in the same positions) stays legal.



```
verif/
  env/spike_iss/                  Spike flow
    core.cfg                      ALL per-core settings: ISA, memory map, tohost, skip list, BUILD_DIR
    run_core_tests.sh             full regression: spike -> RTL -> checker -> coverage
    run_spike.sh                  golden traces only (WSL/Linux)
    checker.py, coverage.py       trace compare / instruction coverage
    env/, riscv_tests/, *_tests/  test sources
  env/core/
    run_core_rtl.sh               RTL traces only (xsim)
    tb_fc32e1s_nano_asic_spike.sv            core + 2 AXI4-Lite memories + protocol checkers + tohost monitor
    fc32e1s_nano_asic_tracer.sv              per-instruction trace, cv32e40p_tracer-compatible format
```

All generated files (ELF, hex, disassembly, traces, coverage report) go to `cores/fc32e1s_nano_asic/verif/build/spike_<march>/`.

## Memory map (simulation)

| Range | Use |
|---|---|
| `0x8000_0000` - `0x8000_0FFF` | IMEM 4 KB |
| `0x2000_0000` - `0x2000_1FFF` | DMEM 8 KB |
| `0x2000_1FC0` | tohost |

IMEM is **not** at `0x0`: Spike maps its debug module
at `0x0-0xFFF`, and the installed Spike build (1.1.1-dev) refuses to load an ELF there
(`Memory address 0x0 is invalid`).

The testbenches instantiate the core with `IMEM_AW=32, DMEM_AW=32`. The core defaults
(24/28) exist only for the Gowin build, where the ports become pins.

## The checker has been shown to catch bugs

Two faults were injected into the RTL and the regression failed both times, at the right instruction:

| Injected fault | Result |
|---|---|
| `SRA` implemented as logical shift | `sra` MISMATCH: `x14` spike `c0000000`, RTL `40000000` |
| `BGEU` using a signed compare | `bgeu` MISMATCH: PC diverges at step 37 |

## Not covered

- Random instruction streams (riscv-dv or similar) -- all tests are directed.
- `ecall` / `ebreak`: fc32e1s_nano_asic halts, Spike traps, so the traces cannot be compared.
- Misaligned accesses (unsupported, no trap) and `fence.i`.
