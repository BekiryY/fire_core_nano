# fc32e1s_nano_asic — FireCore 32-bit RV32E single-stage, 6 registers, ASIC build

> **RTL frozen, rev 3 (2026-11-03): one register-file read port.** Revisions: [`rtl/HISTORY`](rtl/HISTORY).

Split from `fc32e1s_nano` rev 2 on 2026-11-01 (that core was then deleted; its history is
[`rtl/HISTORY_fc32e1s_nano`](rtl/HISTORY_fc32e1s_nano)): the core with its PLATFORM
parameter fixed to ASIC and the other platform's RTL removed. Sibling:
[`fc32e1s_nano_fpga`](../fc32e1s_nano_fpga). Behaviour, ports, registers (x0, ra, sp, a0..a2), software flags and
the plan ([`fc32_nano_plan.md`](../../fc32_nano_plan.md)) are fc32e1s_nano's (see the history and the plan).

Datapath: byte-serial ALU (4 EXEC cycles per ALU op, branches compare in it), register file in
latches behind one clock gate per byte lane. Simulate with xsim: Verilator mis-simulates
the latch register file.

| | |
|---|---|
| Size | sky130_fd_sc_hd tt, Yosys, hierarchy kept, latches counted as dlxtp_1 (rev 3, 2026-11-03): 13 614 um2 (rev 2: 15 044). Rev 3 has one register-file read port: register-register ALU ops and branches take 2 cycles per byte, cpi_bench CPI 7.40 (rev 2: 6.21; xsim, zero waits). |
| Verification | `verif/env/spike_iss/run_core_tests.sh` (Spike vs RTL, xsim) |
| Flows | `appl/sky130_core/` (LibreLane flow of the core alone; define `FC32E1S_NANO_ASIC_SKY130_ICG` for the library clock gate) |

The MCU copy (`example/`, `sw/`, `verif/mcu/`) is in `fc32e1s_nano_asic`.
