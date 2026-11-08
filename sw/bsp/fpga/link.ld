/* link.ld -- fc32e1s_nano_fpga example subsystem: one 2 KiB RAM at 0x000 holds code, data and
 * stack. Reset PC 0x000 (_start), sp = 0x800. The image is the RAM's initial contents.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
STACK_MIN = 0x100;
MEMORY { RAM (rwx) : ORIGIN = 0x000, LENGTH = 2K }
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
  __stack = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_start == 0, "_start must be at 0x000 (reset PC)")
  ASSERT(__bss_end <= __stack - STACK_MIN, "program + data leave less than STACK_MIN for the stack")
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) }
}
