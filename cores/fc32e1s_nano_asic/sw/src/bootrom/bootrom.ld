/* bootrom.ld -- tiny MCU boot ROM at 0x0000, 128 bytes, text only (the ROM is fetch-only). */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x0;
  .text : { *(.text) *(.text.*) }
  ASSERT(. <= 0x80, "boot ROM code exceeds 128 bytes")
  .data : { *(.rodata*) *(.data*) *(.sdata*) *(.bss*) *(.sbss*) }
  ASSERT(SIZEOF(.data) == 0, "boot ROM must be pure text: no .data/.rodata/.bss (fetch-only ROM)")
}
