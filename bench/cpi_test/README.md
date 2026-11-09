# CPI test

One C program, built for each core's register set and run on every core of this repository: six small kernels (sum,
Fibonacci, CRC-32, insertion sort, byte loop, shift-and-add multiply). Each kernel is
bracketed by two writes to a SIM register; the testbench counts the clock cycles and retired
instructions between them, so the cores need no performance counters. The program checks its
own results.

| File | |
|---|---|
| `cpi_test.c` | the kernels and the SIM-register protocol |
| `crt0.S`, `link.ld` | start-up and memory map: 2 KiB RAM at 0x000 (code, data, stack), I/O at 0xFFFFF800 |
| `build.sh` | `build.sh nano`: `riscv32-nano-elf-gcc -mnano` for the 6-register nano cores (x0, ra, sp, a0..a2), rejects other registers; `build.sh rv32e`: stock GCC, plain RV32E (16 registers) for SERV. Writes `build/<abi>/cpi_test.hex` (words) and `build/<abi>/cpi_test_{0..3}.hex` (RAM byte lanes) |
| `run.sh` | builds both images, then simulates each target in xsim |
| `tb/` | `cpi_monitor.sv` (shared), testbenches for the nano cores, SERV and the two FPGA board tops (nano, SERV) |

```bash
./run.sh                    # all targets; Git Bash on Windows or Linux, Vivado xsim on PATH
./run.sh serv               # one target: fc32e1s_nano_fpga, fc32e1s_nano_asic, serv, serv_nano, fc32e1s_nano_fpga_sub, serv_fpga
```

Each core runs the code its own compiler makes: the nano cores the `-mnano` image (toolchain in
[`../../toolchain`](../../toolchain), installed in `~/opt/riscv32-nano`, or set `NANO_CC`), SERV the
stock RV32E image (`riscv64-unknown-elf-gcc`, or set `CC`). `serv_nano` runs the nano image on
SERV, so its CPI compares with the nano cores' on the same instructions.

## Results (GCC 13.2 `-O2`, zero wait states)

| Target | Image | Code | Cycles | Instructions | CPI | Clock | Complete time | Effective MIPS |
|---|---|---|---|---|---|---|---|---|
| fc32e1s_nano_fpga | `-mnano` | 1044 B | 18 304 | 5 228 | **3.50** | 61.6 MHz (GW2A) | 297.1 us | **11.86** |
| fc32e1s_nano_fpga subsystem (block RAM) | `-mnano` | 1044 B | 18 304 | 5 228 | **3.50** | 61.6 MHz (GW2A) | 297.1 us | **11.86** |
| fc32e1s_nano_asic | `-mnano` | 1044 B | 36 392 | 5 228 | **6.96** | 36 MHz (sky130) | 1010.9 us | **3.49** |
| SERV (RV32E) | RV32E | 808 B | 183 729 | 3 525 | **52.12** | 85 MHz (sky130) | 2161.5 us | **1.63** |
| SERV (RV32E), nano image | `-mnano` | 1044 B | 299 923 | 5 228 | **57.37** | 85 MHz (sky130) | 3528.5 us | 1.00 |
| SERV FPGA board top (block RAM) | RV32E | 808 B | 183 729 | 3 525 | **52.12** | 139.8 MHz (GW2A) | 1314.0 us | **2.68** |

Complete time = cycles / clock, at each core's signed-off sky130 clock or GW2A place-and-route
Fmax (the board tops, the same for the core alone). Effective MIPS = the program's work in RV32E instructions (SERV's native
count, 3 525) / complete time, so extra instructions count against a core.

With 6 registers the code is 29 % larger and runs 48 % more instructions than SERV's 16-register
build; the nano cores still need 10.0x (FPGA) and 5.0x (ASIC) fewer cycles than SERV on its own
code. On sky130 the nano ASIC finishes 2.1x sooner (36 MHz) than SERV (85 MHz); on GW2A the nano
board top finishes 4.4x sooner (61.6 MHz) than the SERV board top (139.8 MHz).
