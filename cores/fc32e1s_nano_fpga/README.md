# fc32e1s_nano_fpga — FireCore 32-bit RV32E single-stage, 6 registers, FPGA build

> **RTL frozen, rev 2 (2026-11-02).** Revisions: [`rtl/HISTORY`](rtl/HISTORY).

Split from `fc32e1s_nano` rev 2 on 2026-11-01 (that core was then deleted; its history is
[`rtl/HISTORY_fc32e1s_nano`](rtl/HISTORY_fc32e1s_nano)): the core with its PLATFORM
parameter fixed to FPGA and the other platform's RTL removed. Sibling:
[`fc32e1s_nano_asic`](../fc32e1s_nano_asic). Behaviour, ports, registers (x0, ra, sp, a0..a2), software flags and
the plan ([`fc32_nano_plan.md`](../../fc32_nano_plan.md)) are fc32e1s_nano's (see the history and the plan).

Datapath: 32-bit ALU (one EXEC cycle per ALU op, shifts one cycle per step), carry-chain branch
comparator, register file in LUTRAM (4 byte-wide Gowin SSRAMs).

| | |
|---|---|
| Size | GW2A-18 synthesis, core alone, area goal (2026-11-01, max fanout fixed): 963 logic (769 LUT, 98 ALU, 16 RAM16), 58 REG (the earlier 1024 came from a low max-fanout setting). Same as fc32e1s_nano rev 2 with PLATFORM = FPGA. |
| Size, Artix-7 | Vivado 2025.2 out-of-context synthesis, 10 ns (`appl/vivado/fc32e1s_nano_fpga_core.tcl`; part xc7z020clg400-1, Artix-7 fabric, no Artix-7 part installed): Default **572 LUT (524 logic + 48 LUTRAM), 59 FF, 21 CARRY4, est. 77.5 MHz**; AreaOptimized_high 529 LUT (481 + 48), est. 81.7 MHz. No block RAM, no DSP. |
| Verification | `verif/env/spike_iss/run_core_tests.sh` (Spike vs RTL, xsim) |
| Flows | `appl/gw2a/` (Gowin project of the core alone: `RUN=syn gw_sh appl/gw2a/core/fc32e1s_nano_fpga_core.tcl`) |
| Subsystem | [`example/subsystem/`](example/subsystem): core + 2 KiB block RAM + peripheral port, board top, CPI test in `bench/cpi_test` (CPI 3.49), GW2A project `appl/gw2a/subsystem/` (1225 logic, 4 BSRAM, 61.6 MHz) |

The MCU copy (`example/`, `sw/`, `verif/mcu/`) is in `fc32e1s_nano_asic`.
