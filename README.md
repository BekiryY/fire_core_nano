# FireCore nano

The smallest cores of the FireCore RISC-V family: **fc32e1s_nano**, a single-stage RV32E core
that keeps only the 6 registers a C program needs (x0, ra, sp, a0..a2). It comes in two builds of
the same core, one for FPGAs and one for ASICs, and is compared against
[SERV](https://github.com/olofk/serv), the well-known bit-serial RISC-V core.

Only the non-compressed nano cores are published here (no RV32C variants).

## Repository structure

```
fire_core_nano/
├── README.md          this file
├── LICENSE            MIT (third-party code keeps its own license)
├── cores/
│   ├── fc32e1s_nano_fpga/   FPGA build: 32-bit ALU, register file in LUTRAM
│   ├── fc32e1s_nano_asic/   ASIC build: byte-serial ALU, latch register file, sky130 flow
│   └── serv/                SERV (Olof Kindgren, ISC), the reference core, with our sky130 flow
├── common/            shared RTL and testbench models (memories, latch register file)
├── bench/cpi_test/    one C CPI test for every core (nano FPGA / ASIC, SERV, FPGA board tops)
├── bench/power/       sky130 CPU power from the CPI test's gate-level switching activity
└── results/           FireCore nano vs SERV: sky130 layouts, FPGA synthesis, CPI
```

Each core directory has the same layout:

| Directory | Contents |
|---|---|
| `rtl/` | SystemVerilog sources, `HISTORY` (revisions) |
| `verif/` | verification environment (Spike ISS vs RTL) |
| `appl/` | implementation flows (Gowin GW2A project, Vivado, LibreLane sky130) |
| `example/`, `sw/` | example subsystem and its software (ASIC build) |

## Cores

| Core | ISA | Registers | Datapath | Target |
|---|---|---|---|---|
| `fc32e1s_nano_fpga` | RV32E | 6 | 32-bit ALU, one cycle per ALU op | FPGA (Gowin GW2A, Xilinx 7-series) |
| `fc32e1s_nano_asic` | RV32E | 6 | byte-serial ALU (4 cycles per ALU op), latch register file | ASIC (SkyWater sky130) |
| `serv` | RV32I / RV32E | 32 / 16 | bit-serial | reference |

Name: **fc** FireCore, **32** XLEN, **e** RV32E, **1s** single-stage (one instruction in flight),
**nano** 6-register variant.

## Status

The core directories are **not initialized yet**: their sources are in place but not yet
self-contained (some flows and testbenches still refer to files of the original development
repository). They will be committed core by core with their own README, build instructions and
verification results.

The comparison with SERV is in [`results/`](results/).

## License

MIT, see [`LICENSE`](LICENSE). `cores/serv/` is SERV by Olof Kindgren under the ISC License
([`cores/serv/LICENSE`](cores/serv/LICENSE)); `serv_compdec.v` is Apache-2.0.
