# sw: C programs for the nano cores

The board support package (BSP) and examples, built with the `-mnano` toolchain
([`../toolchain`](../toolchain)) and picolibc.

```sh
make                              # examples/hello for the FPGA subsystem -> build/fpga/
make TARGET=asic                  # the ASIC subsystem (boot ROM image, UART console)
make PROG=myprog SRCS="a.c b.c"   # your own program
bsp/fpga/sim/run_sim.sh hello     # run it on the FPGA subsystem RTL in xsim (Vivado on PATH)
```

| File | Contents |
|---|---|
| `bsp/crt0.S` | Start-up: sets `sp`, clears `.bss`, calls `main`, passes its result to `_exit`. |
| `bsp/stdio.c` | picolibc `stdin`/`stdout`/`stderr` on `bsp_putc` / `bsp_getc`. |
| `bsp/printf_tiny.c` | A `printf` of about 0.8 KiB (`%d %i %u %x %X %p %c %s`, width, `0` and `-` flags). It is the default; `PRINTF=m\|i\|d` uses picolibc's printf (1.4 / 2.4 / 4.8 KiB) instead. |
| `bsp/fpga/` | `link.ld`: 2 KiB RAM at 0x000. `bsp.c`: console on SIM 0x80C; `_exit` puts the result on the LEDs (0x01 means pass), then ECALL. `sim/`: console testbench. |
| `bsp/asic/` | `link.ld`: image signature at 0x000 and `_start` at 0x080, the boot ROM's jump target. `bsp.c`: console on a UART at 0x900, using the FireCore nano MCU register layout. |
| `tools/mkimage.py` | Writes the 2 KiB image (`.img`), `.hex`, and `_0..3.hex` (one file per FPGA RAM byte lane). |

The BSP functions are weak, so a program can define its own `bsp_putc`, `bsp_getc` and `_exit`.
Each build checks every instruction against the six registers the cores have.

`examples/hello` takes 1.5 KiB and runs on the FPGA subsystem in 17,118 cycles.
