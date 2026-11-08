# Results: FireCore nano vs SERV

The FireCore nano cores compared with [SERV](https://github.com/olofk/serv) (bit-serial RISC-V,
Olof Kindgren), the usual reference for "smallest RISC-V core". All numbers are for the
cores alone (no memories, no peripherals). Date: 2026-11-08.

## Summary

On sky130, `fc32e1s_nano_asic` runs the benchmark program **2.4x faster** than SERV (RV32E) on a
**2.4x smaller die**, using **5.8x less energy** (estimated): **3.66 effective MIPS** against
SERV's 1.53. SERV runs at a 2.4x higher clock, but needs 5.6x more cycles for the same C
program. At equal setup margin the speed-up is 2.1x (see the clock caveat below). Each core runs
the code of its own compiler: the nano `-mnano` (6 registers, 10 % more
code, 33 % more instructions), SERV stock RV32E (16 registers).

## sky130 layouts

SkyWater sky130A, `sky130_fd_sc_hd`, LibreLane Classic flow, signed off in all 9 corners
(ss / tt / ff x min / nom / max RC). Configs and metrics are in [`sky130/`](sky130/).

| | fc32e1s_nano_asic | SERV, RV32E |
|---|---|---|
| ISA, registers | RV32E, 6 (x0 ra sp a0..a2) | RV32E, 16 (x0..x15) |
| Datapath | byte-serial ALU | bit-serial |
| Register file | latches, one clock gate per byte lane | latches (`dlxtp_1`), one clock gate per word |
| Die | 153.5 x 155.3 um = **23 843 um2** | 238 x 238 um = **56 644 um2** |
| Standard cells | **18 505 um2** | **30 895 um2** |
| of which sequential | 5 095 um2 | 13 992 um2 |
| Cell density (fill excluded) | 82.7 % | 66.6 % |
| Clock (signed off) | **36 MHz** (ss Fmax 37.0 MHz, max RC) | **85 MHz** (ss setup slack +1.59 ns) |
| Hold, worst | +0.106 ns | +0.0015 ns |
| DRC (Magic, KLayout) / LVS / antenna | clean | clean |
| Max slew (1.1 ns limit) | 1 net at 1.13 ns (ss) | clean |
| Wire length | 67.7 mm | 68.8 mm |
| Power, estimated | 2.33 mW at 36 MHz | 5.71 mW at 85 MHz |

| fc32e1s_nano_asic | SERV, RV32E |
|---|---|
| ![fc32e1s_nano_asic layout](sky130/fc32e1s_nano_asic/fc32e1s_nano_asic_hard.png) | ![SERV layout](sky130/serv_rv32e/serv_rf_top_latch.png) |
| 153.5 x 155.3 um | 238 x 238 um (images are not to the same scale) |

## Performance

`cpi_bench`: one C program (crc, fib, qsort, bsearch, list, interp, parse kernels), GCC 13.2.0
`-O2`, zero memory wait states. Each core runs its own compiler's code: the nano cores
`riscv32-nano-elf-gcc -mnano` ([`../toolchain`](../toolchain), 6 registers), SERV stock
`riscv64-unknown-elf-gcc` (`-march=rv32e` / `rv32i`). Raw outputs: [`cpi_bench/`](cpi_bench/).

| Core | Compiler | Code (.text) | Instructions | Cycles | CPI |
|---|---|---|---|---|---|
| fc32e1s_nano_fpga | `-mnano` | 5 460 B | 1 465 222 | **4 931 283** | 3.37 |
| fc32e1s_nano_asic | `-mnano` | 5 460 B | 1 465 222 | **10 839 619** | 7.40 |
| SERV, RV32E (latch register file, no CSRs) | RV32E | 4 972 B | 1 101 473 | 61 037 635 | 55.42 |
| SERV, RV32I (stock) | RV32I | 4 628 B | 1 079 823 | 60 603 529 | 56.12 |

With 6 registers the program is 9.8 % larger and runs 33 % more instructions than SERV's RV32E
build; the cycle counts and times include that.

**Complete time and effective MIPS.** Complete time = cycles / clock. Effective MIPS = the
program's work in RV32E instructions (SERV RV32E's count, 1 101 473) / complete time, so the nano
cores' extra instructions count against them; native MIPS = the core's own instructions / time
= clock / CPI.

| | Clock | Complete time | Effective MIPS | Native MIPS |
|---|---|---|---|---|
| fc32e1s_nano_asic, sky130 | 36 MHz (signed off) | **301.1 ms** | **3.66** | 4.87 |
| SERV RV32E, sky130 | 85 MHz (signed off) | **718.1 ms** | **1.53** | 1.53 |
| fc32e1s_nano_fpga, GW2A-18 | 61.6 MHz (subsystem, place and route) | **80.1 ms** | **13.76** | 18.30 |

Same program on sky130, at each core's signed-off clock:

| | fc32e1s_nano_asic | SERV, RV32E | nano advantage |
|---|---|---|---|
| Complete time | 10.84 M cycles / 36 MHz = **301 ms** | 61.04 M cycles / 85 MHz = **718 ms** | 2.39x faster |
| Effective MIPS | **3.66** | **1.53** | 2.39x |
| Code (.text) | 5 460 B | 4 972 B | 1.10x larger |
| Die area | 23 843 um2 | 56 644 um2 | 2.38x smaller |
| Speed per die area | | | 5.7x |
| Energy, estimated | 2.33 mW x 301 ms = **0.70 mJ** | 5.71 mW x 718 ms = **4.10 mJ** | 5.8x less |

The small CPI test of [`../bench/cpi_test`](../bench/cpi_test) (1 KiB image, same compilers)
agrees: nano ASIC 1.01 ms at 36 MHz (3.49 effective MIPS), SERV 2.16 ms at 85 MHz (1.63), 2.1x.

## FPGA

Synthesis only (no place and route for SERV: the bare core has more pins than the device).

| | fc32e1s_nano_fpga | SERV, RV32I (stock `serv_rf_top`, with CSRs) |
|---|---|---|
| Gowin GW2A-18 | 963 logic (769 LUT, 98 ALU, 16 RAM16), 58 REG | 288 LUT, 182 FF, 1 BSRAM (register file) |
| Xilinx Artix-7 (Vivado, xc7z020) | 572 LUT (48 LUTRAM), 59 FF, est. 77.5 MHz | not run |
| Cycles, `cpi_bench` | 4.93 M | 60.60 M (12.3x more) |

On an FPGA SERV is smaller in LUTs (its register file goes into a block RAM); the nano is 12x
faster per clock.

## Method and caveats

- **Different register counts.** The nano keeps 6 registers, SERV (RV32E) 16. The nano program
  (`-mnano`) is 33 % more instructions and 10 % more code; the cycle counts, times and effective
  MIPS above include that.
- **Different densities.** SERV was laid out at 60-67 % cell density, the nano at 82.7 %. At the
  nano's density SERV's die would be about 46 400 um2, still 1.9x the nano's.
- **Clocks.** Each core is signed off at its own clock, with different setup margins at the slow
  corner (ss 100C 1.60 V, max RC): SERV 85 MHz against an Fmax of about 98 MHz (13.5 %), the
  nano 36 MHz against 37.0 MHz (2.7 %; 39.5 MHz at min RC). Compared at their Fmax, or both
  at 13.5 % margin (nano 32 MHz), the nano finishes `cpi_bench` **2.1x** sooner (293 vs 621 ms)
  instead of 2.4x.
- **Power** is LibreLane's estimate with default switching activity, not a measured or
  simulation-annotated figure. Use it to compare the two cores, not as an absolute.
- **SERV configuration.** Upstream SERV with `WITH_CSR = 0` (no CSRs, traps or timer interrupt;
  the nano has none either: ECALL / EBREAK halt it), `W = 1`, and its register-file RAM replaced
  by a latch register file so both cores are standard cells only (no SRAM macro). The RV32E build
  uses registers x0..x15 only. The latch register file does not change SERV's timing in cycles:
  the RV32I build runs `cpi_bench` in exactly the stock SERV cycle count.
- **Buses.** The nano has AXI4-Lite instruction and data ports, SERV Wishbone; both layouts are
  the core with its bus pins, no interconnect.
