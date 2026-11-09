# fc32e1s_nano_fpga: RV32E core on 6 registers, FPGA build

A single-stage RV32E core that keeps only the 6 registers a C program needs (x0, ra, sp,
a0..a2), built for FPGAs: a 32-bit ALU (one cycle per ALU operation, shifts one cycle per
step), a carry-chain branch comparator and the register file in LUTRAM (4 byte-wide RAM16s).
AXI4-Lite instruction and data ports. Software: `riscv32-nano-elf-gcc -mnano`
([`../../toolchain`](../../toolchain)). ASIC build of the same core:
[`fc32e1s_nano_asic`](../fc32e1s_nano_asic).

| | |
|---|---|
| Gowin GW2A-18, core alone | 963 logic (769 LUT, 98 ALU, 16 RAM16), 58 registers (synthesis, area goal) |
| Gowin GW2A-18, board top | core + 2 KiB block RAM + peripheral: 1225 logic, 4 BSRAM, **61.6 MHz** |
| Xilinx 7-series, core alone | **529 LUT** (481 logic + 48 LUTRAM), 59 FF, est. 81.7 MHz (Vivado OOC, xc7z020, AreaOptimized_high; Default: 572 LUT, 77.5 MHz) |
| Xilinx 7-series, board top | 648 LUT (604 logic + 44 LUTRAM), 177 FF, 2 BRAM tiles, **94.6 MHz** after place and route (xc7z020clg400-1) |
| CPI | 3.37 on `cpi_bench`, zero wait states (3.50 on the board top's CPI test) |
| Verification | Spike vs RTL: 41/41 tests match, 38/38 instructions covered ([`verif/`](verif/)) |

Comparison with SERV: [`../../results`](../../results).

## Run it (from this directory)

```bash
(cd verif/env/spike_iss && ./run_core_tests.sh)     # regression: Spike vs RTL (xsim)
../../bench/cpi_test/run.sh fc32e1s_nano_fpga_sub    # CPI test on the board top
RUN=syn gw_sh appl/gw2a/core/fc32e1s_nano_fpga_core.tcl   # Gowin synthesis of the core alone
RUN=1 gw_sh appl/gw2a/subsystem/fc32e1s_nano_fpga_subsystem.tcl   # board top: synthesis + place and route
vivado -mode batch -source appl/vivado/vivado_project.tcl -tclargs top     # Vivado project of the board top (RUN=1: build it)
```

| Directory | |
|---|---|
| `rtl/` | the core (`fc32e1s_nano_fpga_core`), revisions in `rtl/HISTORY` |
| `verif/` | Spike ISS vs RTL regression |
| `example/subsystem/` | ready-to-use CPU: core + 2 KiB block RAM + AXI4-Lite peripheral port, and a board top |
| `appl/gw2a/` | Gowin projects (core alone, board top) |
| `appl/vivado/` | Vivado projects (`vivado_project.tcl`: core alone or board top; `PART=` for another device) and a batch out-of-context synthesis of the core |
