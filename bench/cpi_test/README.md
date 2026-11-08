# CPI test

One C program, one binary, run on every core of this repository: six small kernels (sum,
Fibonacci, CRC-32, insertion sort, byte loop, shift-and-add multiply). Each kernel is
bracketed by two writes to a SIM register; the testbench counts the clock cycles and retired
instructions between them, so the cores need no performance counters. The program checks its
own results.

| File | |
|---|---|
| `cpi_test.c` | the kernels and the SIM-register protocol |
| `crt0.S`, `link.ld` | start-up and memory map: 2 KiB RAM at 0x000 (code, data, stack), I/O at 0xFFFFF800 |
| `build.sh` | compiles for the 6-register nano cores (x0, ra, sp, a0..a2) and rejects other registers; writes `build/cpi_test.hex` (words) and `build/cpi_test_{0..3}.hex` (RAM byte lanes) |
| `run.sh` | builds, then simulates each target in xsim |
| `tb/` | `cpi_monitor.sv` (shared), testbenches for the nano cores, SERV and the FPGA subsystem |

```bash
./run.sh                    # all targets; Git Bash on Windows or Linux, Vivado xsim on PATH
./run.sh serv               # one target: fc32e1s_nano_fpga, fc32e1s_nano_asic, serv, fc32e1s_nano_fpga_sub
CC=riscv32-nano-elf-gcc ./run.sh   # the 6-register GCC (-mnano) instead of stock GCC with -ffixed-*
```

The nano cores have 6 registers: at most 3 arguments per call and no multiply / divide. SERV
runs the same binary (RV32E latch register file of its sky130 layout).

## Results (stock GCC 13.2 `-O2 -ffixed-*`, 1024 B image, zero wait states)

| Target | Cycles | Instructions | CPI |
|---|---|---|---|
| fc32e1s_nano_fpga | 17 699 | 5 067 | **3.49** |
| fc32e1s_nano_fpga subsystem (block RAM) | 17 699 | 5 067 | **3.49** |
| fc32e1s_nano_asic | 35 426 | 5 067 | **6.99** |
| SERV (RV32E) | 289 979 | 5 067 | **57.23** |
