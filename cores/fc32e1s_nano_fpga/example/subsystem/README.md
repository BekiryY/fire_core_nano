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

Fetch takes 2 cycles; a RAM load or store takes 2 cycles. `halt_o` goes high on ECALL / EBREAK.

## Software and test

Programs use the shared CPI test set-up in [`bench/cpi_test/`](../../../../bench/cpi_test): the
same address map (RAM at 0x000, I/O at 0xFFFFF800), start-up code, linker script and
`build.sh`, which writes the per-lane RAM images (`<prog>_{0..3}.hex`) this subsystem loads.

```bash
../../../../bench/cpi_test/run.sh fc32e1s_nano_fpga_sub   # build + xsim of this top: PASS, CPI 3.49
```

On the board the CPI test shows 0x01 on the LEDs when all its results are correct.

## GW2A build

```bash
cd ../../appl/gw2a/subsystem
RUN=1 gw_sh fc32e1s_nano_fpga_subsystem.tcl    # needs bench/cpi_test/build/cpi_test_*.hex
```

GW2A-LV18PG256C8/I7, the user's standard strategy (`../../appl/gw2a/gw_project.tcl`), pins
not constrained: **1225 logic (963 LUT, 166 ALU, 16 RAM16), 171 registers, 4 BSRAM,
Fmax 61.6 MHz**. Add a `.cst` with your board's pins for the clock, the reset button and
the LEDs.
