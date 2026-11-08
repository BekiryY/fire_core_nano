# fc32e1s_nano CPU subsystem

> **nano copy (2026-10-31).** Copied from [`fc32e1s_tiny`](../../../deprecated/fc32e1s_tiny/example/subsystem) with the core
> renamed; the core is the 6-register nano (x0, ra, sp, a0..a2: software adds
> `-ffixed-a3 -ffixed-a4`). There is no nano hard macro or chip yet: the hard-macro, chip,
> size and Gowin notes below are the tiny MCU's. The CPU logic half takes the nano core's
> 11-bit fetch / 12-bit data addresses (the PC wraps at 2 KiB, so the fetch port has no
> SLVERR). Verified with [`../../verif/mcu/run_mcu.sh`](../../verif/mcu/run_mcu.sh)
> (`MACRO=rtl` and `sub`): PASS, 2026-10-31.

The frozen core with its instruction side and memory: **core + fetch port + boot ROM + 2 KiB
RAM**. On the sky130 chip this is one hard macro,
`sky130_sram_2kbyte_1rw1r_32x512_8_fc32e1s_nano_v2` (the logic half placed in the free space
of the OpenRAM SRAM, [`../../appl/sky130_sram_macro_v2`](../../appl/sky130_sram_macro_v2)); the
same logic on a generic RAM is `fc32e1s_nano_subsystem`, for simulation and FPGA.

```
  +------------------------------------------------------------------+
  |  fc32e1s_nano_sram2k_v2_cpu                                      |
  |    core m_axi_i --> fetch port --+--> boot ROM   0x000 - 0x07F   |
  |                                  +--> RAM port 1 0x080 - 0x7FF   |
  |    core m_axi_d ---------------------------------------------------> m_axi_d_* (12-bit)
  +------------------------------------------------------------------+
     RAM (OpenRAM macro / fc32e1s_nano_ram) port 0 <------------------- clk0 csb0 web0 wmask0
                                                                        addr0 din0 dout0
```

| File | Module | Role |
|---|---|---|
| `fc32e1s_nano_sram2k_v2_cpu.sv` | `fc32e1s_nano_sram2k_v2_cpu` | the hard macro's logic half: core, fetch port (2-cycle fetch, no response buffer), fetch decode (ROM / RAM / SLVERR from 0x800), one 12-bit data address for AW and AR |
| `fc32e1s_nano_sram2k_v2_bootrom.sv` | `fc32e1s_nano_sram2k_v2_bootrom` | 32-word boot ROM, **generated** by `sw/src/bootrom/build_bootrom.sh` from `boot_spi.S` |
| `fc32e1s_nano_subsystem.sv` | `fc32e1s_nano_subsystem` | logic half + `fc32e1s_nano_ram`, the macro's pins without power and port-1 stubs |
| `fc32e1s_nano_ram.sv` | `fc32e1s_nano_ram` | 512 x 32, port 0 read / write with byte mask, port 1 read; one array per byte lane |

Unlike `fc32ec3fs_subsystem`, the data-side memory controller is **not** in here: the MCU
([`../mcu/tiny_soc.sv`](../mcu/tiny_soc.sv)) registers `m_axi_d` (`fc32e1s_nano_sram2k_v2_dslice`),
decodes it in its interconnect and drives RAM port 0 through `axil_mem_ctrl` (CPU data and the
SPI flash's memory master). On the chip the hard macro's boundary is the SRAM's pins, and the
subsystem keeps that boundary so the MCU RTL is the same for the macro and for the RTL version:
`tiny_soc` instantiates `fc32e1s_nano_subsystem` by default and the hard macro when
`FC32E1S_NANO_HARD_MACRO` is defined (the sky130 chip configs do; same instance name
`u_macro`). The default needs no define, because the Gowin IDE cannot pass one reliably.

Address map, reset and fetch timing: [`../../appl/sky130_sram_macro_v2/README.md`](../../appl/sky130_sram_macro_v2/README.md).
The logic half is also built with `FC32E1S_NANO_ASIC_SKY130` (latch register file) for the macro;
the FPGA build leaves it undefined (LUTRAM register file).

The RAM is one 512 x 8 array per byte lane, each enabled only when it reads or writes: Gowin
then infers a dual-port block RAM in normal write mode per lane. A single 32-bit array with
byte-masked writes made GowinSynthesis infer read-before-write on port 0 (DPB `WRITE_MODE0`
2'b10), which GW2A place and route rejects (PA2122).

Verification: [`../../verif/mcu`](../../verif/mcu) (`run_mcu.sh`, `MACRO=sub` for this
module): same result as the hard macro's model, cycle for cycle.
