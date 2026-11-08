/* link.ld -- fc32e1s_nano_fpga subsystem: one 2 KiB RAM at 0x000 for code, data and stack. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x000, LENGTH = 2K }
SECTIONS {
  .text   : { *(.init) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data   : { *(.data .data.* .sdata .sdata.*) } > RAM
  .bss    : { . = ALIGN(4); _bss_start = .; *(.bss .bss.* .sbss .sbss.* COMMON); . = ALIGN(4); _bss_end = .; } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_bss_end <= _stack_top - 256, "program leaves less than 256 B of stack")
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
