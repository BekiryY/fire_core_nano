# fc32e1s_nano_fpga CPU subsystem

A ready-to-use CPU for FPGA designs: the `fc32e1s_nano_fpga` core on a 2 KiB block RAM that
holds code, data and stack, with one AXI4-Lite port for your peripherals. The program is the
RAM's initial contents (block RAM initialization in the bitstream), so there is no boot ROM and
no flash.

```
  +--------------------------------------------------------------------------+
  |  fc32e1s_nano_fpga_subsystem                                             |
  |    core m_axi_i --> fetch port --> RAM port 1          0x000 - 0x7FF     |
  |    core m_axi_d --+--> RAM port 0 (load / store)       0x000 - 0x7FF     |
  |                   +----------------------------------> m_axi_*  0x800 - 0xFFF
  +--------------------------------------------------------------------------+
```

| File | Module | Role |
|---|---|---|
| `fc32e1s_nano_fpga_subsystem.sv` | `fc32e1s_nano_fpga_subsystem` | core + fetch port + RAM controller + peripheral port; `INIT_FILE` = program image |
| `fc32e1s_nano_fpga_ram.sv` | `fc32e1s_nano_fpga_ram` | 512 x 32 dual-port RAM, one array per byte lane (4 BSRAM on GW2A) |
| `fc32e1s_nano_fpga_top.sv` | `fc32e1s_nano_fpga_top` | board top: reset synchronizer, subsystem, LED / counter peripheral |
| `sw/` | | `cpi_test.c`, start-up, linker script, `build.sh` |
| `tb/` | | testbench of the top, run by `run_sim.sh` |

## Address map

Data addresses are 12 bits; software reaches 0x800 - 0xFFF as `0xFFFFF800 + offset` (one
instruction off x0).

| Address | |
|---|---|
| 0x000 - 0x7FF | RAM: reset PC 0x000, code, data, stack (top 0x800) |
| 0x800 - 0xFFF | `m_axi_*` peripheral port |

The top's peripheral (decoded on address bits 3:2):

| Address | Register | |
|---|---|---|
| 0x800 | LED | R/W, bits 7:0 drive `led_o` |
| 0x804 | CYCLE | R, clock cycles since reset |
| 0x808 | INSTRET | R, instructions retired since reset |
| 0x80C | SIM | W, the testbench prints every word written here |

Fetch takes 2 cycles; a RAM load or store takes 2 cycles. `halt_o` goes high on ECALL / EBREAK
(the start-up code ends with ECALL when `main` returns).

## Software

The core has 6 registers (x0, ra, sp, a0..a2): at most 3 arguments per call, and no multiply /
divide instructions (RV32E without M). `sw/build.sh` compiles with stock GCC restricted to those
registers (`-ffixed-*`), or with the 6-register GCC (`CC=riscv32-nano-elf-gcc`, `-mnano`), and
rejects a binary that uses any other register.

```bash
./sw/build.sh              # sw/cpi_test.c -> sw/build/cpi_test_{0..3}.hex (one file per byte lane)
./run_sim.sh               # build + xsim: per-kernel cycles, instructions, CPI; PASS / FAIL
```

`cpi_test` (1060 B) runs six kernels (sum, Fibonacci, CRC-32, insertion sort, byte loop,
shift-and-add multiply), checks their results and shows 0x01 on the LEDs when all pass.
In simulation: **CPI 3.51** over the kernels (17 771 cycles, 5 067 instructions).

## GW2A build

```bash
cd ../../appl/gw2a/subsystem
RUN=1 gw_sh fc32e1s_nano_fpga_subsystem.tcl    # needs sw/build/cpi_test_*.hex
```

GW2A-LV18PG256C8/I7, the user's standard strategy (`../../appl/gw2a/gw_project.tcl`), pins
not constrained: **1225 logic (963 LUT, 166 ALU, 16 RAM16), 171 registers, 4 BSRAM,
Fmax 61.6 MHz**. Add a `.cst` with your board's pins for the clock, the reset button and
the LEDs.
