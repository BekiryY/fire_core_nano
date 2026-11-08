/* ============================================================
 *  core_test.ld -- Spike ISS <-> RTL cekirdek testleri linker scripti
 *
 *  Adres haritasi Silicore SoC ile birebir ayni tutulmustur:
 *
 *    0x8000_0000 .. 0x8000_0FFF   .text   (IMEM, bkz. NOT-1)
 *    0x2000_0000 .. 0x2000_1EFF   .rodata/.data/.bss  (DMEM)
 *    0x2000_1F00 .. 0x2000_1FBF   yigin (yukaridan asagi buyur)
 *    0x2000_1FC0 .. 0x2000_1FC7   tohost    <- TB bu adresi izler
 *    0x2000_1FC8 .. 0x2000_1FCF   fromhost
 *
 *  fc32e1s_nano_fpga NOTE: IMEM moved from 0x0000_0000 to 0x8000_0000. Spike maps its
 *  debug module at 0x0000_0000-0x0000_0FFF; depending on the spike build that
 *  shadows a RAM region at 0x0 and the ELF fails to load ("Memory address 0x0
 *  is invalid" -- measured with spike 1.1.1-dev, Sep 2026). 0x8000_0000 is the
 *  riscv-tests/spike default base and no spike device lives there.
 *  The 4 KB limit now only mirrors the TB IMEM model size.
 *
 *  NOT-1: .text 4 KB ile sinirli. Spike kendi reset vektorunu
 *  0x0000_1000'e (DEFAULT_RSTVEC) bir boot ROM olarak koyuyor;
 *  RAM bolgesini oraya kadar tanimliyoruz ki cakisma olmasin.
 *  Cekirdek ISA testleri icin 4 KB fazlasiyla yeterli, tasarsa
 *  asagidaki ASSERT link zamaninda hata verir.
 *
 *  NOT-2: DMEM gercek tasarimda 0x2000_0000 - 0x2000_1FFF, 8 KB
 *  (bkz. rtl/memory/dmem/dmem_top.sv:5 ve rtl/control_and_bus/axi4/axi_internconnect.sv:49).
 *  tohost/fromhost bu araligin icinde, yiginin ustunde duruyor;
 *  boylece normal veri erisimleriyle cakismiyor.
 *
 *  NOT-3: tohost/fromhost NOLOAD -- hex ciktisina girmezler, sadece
 *  sembol olarak ELF'te bulunurlar. Spike bu iki sembolu ELF'ten
 *  okuyup HTIF'i baglar; sembol yoksa "tohost and fromhost symbols
 *  not in ELF" uyarisi verip test sonucunu goremez.
 * ============================================================ */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

/* HIDDEN: bu yardimci semboller ELF sembol tablosuna global olarak
 * girmesin. __imem_limit = 0x1000 spike bootrom PC'sine denk geldigi
 * icin global kalirsa spike loguna ">>>> __imem_limit" anotasyonu
 * dusuyor ve golden log gurultulenlyor. */
HIDDEN( __imem_base    = 0x80000000 );
HIDDEN( __imem_limit   = 0x80001000 );
HIDDEN( __dmem_base    = 0x20000000 );
HIDDEN( __dmem_limit   = 0x20002000 );
HIDDEN( __tohost_addr  = 0x20001FC0 );
HIDDEN( __stack_limit  = 0x20001FC0 );

SECTIONS
{
  /* ---------------- IMEM ---------------- */
  . = __imem_base;
  .text : {
    *(.init)
    *(.text)
    *(.text.*)
  }
  _text_end = .;

  /* ---------------- DMEM ---------------- */
  . = __dmem_base;
  .rodata : {
    *(.rodata) *(.rodata.*)
    *(.srodata) *(.srodata.*)
  }
  .data : {
    *(.data) *(.data.*)
    *(.sdata) *(.sdata.*)
  }
  .bss : {
    *(.bss) *(.bss.*)
    *(.sbss) *(.sbss.*)
    *(COMMON)
  }
  _data_end = .;

  /* Yigin tepesi tohost'un hemen altinda, 16-byte hizali */
  _stack_top = __stack_limit;

  /* ------------- HTIF sonuc alani -------------
   * NOLOAD: hex'e girmez, yalnizca sembol olarak var olur.        */
  . = __tohost_addr;
  .tohost (NOLOAD) : {
    tohost   = .; . += 8;
    fromhost = .; . += 8;
  }

  /* ---------------- Tasma kontrolleri ---------------- */
  ASSERT(_text_end <= __imem_limit,
         "HATA: .text 4 KB'i asti -- TB IMEM modeli 4 KB.")
  ASSERT(_data_end <= 0x20001F00,
         "HATA: veri bolumu yigin/tohost alanina tasti.")
}
