# Spike ISS vs RTL

The core's regression: each test runs on [Spike](https://github.com/riscv-software-src/riscv-isa-sim)
(`--isa=rv32e`) and on the RTL (xsim), and the two instruction traces are compared step by step:
PC, instruction word, register write, memory address and store data. Results and the memory map
are in [`../../README.md`](../../README.md).

```bash
./run_core_tests.sh               # all tests: Spike -> RTL -> checker -> coverage
./run_core_tests.sh add           # one test
SIM_SEED=7 ./run_core_tests.sh    # another random AXI wait-state pattern
AXI_WAITS=none ./run_core_tests.sh
```

Needs `riscv64-unknown-elf-gcc` and `spike` (Linux or WSL; from Git Bash on Windows the Spike
stage runs in WSL automatically) and Vivado's `xvlog` / `xelab` / `xsim` on PATH. Outputs go
to `../../build/`.

| Path | |
|---|---|
| `core.cfg` | every core-specific setting: ISA, memory map, tohost, test groups, skip list |
| `run_core_tests.sh` | full regression, one exit code (0 = every trace matched) |
| `run_spike.sh` | builds the tests and writes Spike's golden traces |
| `checker.py`, `coverage.py` | trace comparison; instruction coverage over the passing tests |
| `riscv_tests/` | the official riscv-tests (`rv64ui` sources, built for RV32E), with their `LICENSE` |
| `tiny_tests/` | hand-written test of the 6-register set (x0, ra, sp, a0..a2) |
| `random_tests/`, `c_tests/` | generated random-instruction and C tests (`gen_tests.py`) |
| `env/` | linker script and test environment (`tohost`, `TEST_CNT`) |

Tests that need M, C, Zicsr, traps or registers outside the 6 are skipped, each with its reason
in `core.cfg`. run_spike.sh also fails any test whose code uses a register the core does not
have.
