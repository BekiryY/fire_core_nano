/* link.ld -- toolchain tests on Spike: 64 KiB at 0x80000000 (spike's default RAM base) for
 * code, data and stack; tohost / fromhost for the result. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K }
SECTIONS
{
  .text   : { KEEP(*(.text.start)) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data   : { *(.data .data.* .sdata .sdata.*) } > RAM
  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM
  .tohost (NOLOAD) : { *(.tohost) } > RAM
  __stack = ORIGIN(RAM) + LENGTH(RAM);
}
