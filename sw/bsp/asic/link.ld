/* link.ld -- fc32e1s_nano_asic subsystem: the 2 KiB SRAM holds the whole program; the flash
 * image (flash 0x000 - 0x7FF, copied by the boot ROM) is the memory image byte for byte.
 *   0x000 - 0x07F  .low: data only -- the fetch port sees the boot ROM there, the data port
 *                  the SRAM (word 0: image signature 0x7117B007, checked by the boot ROM)
 *   0x080          .text (_start first: the boot ROM jumps to 0x080), .rodata, .data, .bss
 *   ... 0x7FF      stack, sp = 0x800 at start (STACK_MIN bytes kept free)
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
STACK_MIN = 0x100;
MEMORY
{
  LOW (r)   : ORIGIN = 0x000, LENGTH = 0x080
  RAM (rwx) : ORIGIN = 0x080, LENGTH = 0x780
}
SECTIONS
{
  .low : {
    LONG(0x7117B007)
    *(.lowdata .lowdata.*)
  } > LOW
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
  __stack = 0x800;
  ASSERT(_start == 0x80, "_start must be at 0x080 (boot ROM jump target)")
  ASSERT(__bss_end <= __stack - STACK_MIN, "program + data leave less than STACK_MIN for the stack")
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) }
}
