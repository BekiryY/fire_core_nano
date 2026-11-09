# fc32e1s_nano_asic CPU subsystem

The core with its instruction side and memory: **core + fetch port + boot ROM + 2 KiB RAM**,
in RTL. The RAM's port 0 and the core's data master are left outside, so the parent decides
how data accesses reach the RAM and its peripherals.

```
  +------------------------------------------------------------------+
  |  fc32e1s_nano_sram2k_v2_cpu                                      |
  |    core m_axi_i --> fetch port --+--> boot ROM   0x000 - 0x07F   |
  |                                  +--> RAM port 1 0x080 - 0x7FF   |
  |    core m_axi_d ---------------------------------------------------> m_axi_d_* (12-bit)
  +------------------------------------------------------------------+
     fc32e1s_nano_ram port 0 (read / write) <-------------------------- clk0 csb0 web0 wmask0
                                                                        addr0 din0 dout0
```

| File | Module | Role |
|---|---|---|
| `fc32e1s_nano_subsystem.sv` | `fc32e1s_nano_subsystem` | top: the CPU block below + `fc32e1s_nano_ram` |
| `fc32e1s_nano_sram2k_v2_cpu.sv` | `fc32e1s_nano_sram2k_v2_cpu` | core, fetch port (2-cycle fetch), fetch decode (ROM / RAM), one 12-bit data address for AW and AR |
| `fc32e1s_nano_sram2k_v2_bootrom.sv` | `fc32e1s_nano_sram2k_v2_bootrom` | 32-word boot ROM, **generated** by `../../sw/src/bootrom/build_bootrom.sh` from `boot_spi.S` |
| `fc32e1s_nano_ram.sv` | `fc32e1s_nano_ram` | 512 x 32: port 0 read / write with byte mask, port 1 read; one array per byte lane |

- **Fetch:** the core's PC is 11 bits, so it wraps at 2 KiB. Reset PC 0x000 is the boot ROM.
- **Data:** 12-bit addresses (4 KiB); software reaches 0x800 - 0xFFF as `0xFFFFF800 + offset`,
  one instruction off x0.
- **Boot ROM:** waits for an SPI flash's power-up time, copies flash 0x000 - 0x7FF into the RAM
  through an SPI flash controller expected at data address 0xA00, and jumps to 0x080. The
  controller is not part of this repository; replace `boot_spi.S` for another boot source.
