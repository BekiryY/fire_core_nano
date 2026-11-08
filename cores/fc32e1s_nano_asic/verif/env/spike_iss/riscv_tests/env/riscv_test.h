// ============================================================
//  riscv_test.h -- riscv-tests suite'i icin SILICORE ortami
//
//  NEDEN KENDI ENV'IMIZ VAR
//    Yukari akistaki riscv-tests, "env/p" ortamiyla gelir: kod 0x8000_0000'a
//    linklenir, kendi tuzak vektorunu kurar ve HTIF'i orada konumlandirir.
//    Silicore'un bellek haritasi farkli:
//        IMEM  0x0000_0000 (.text)
//        DMEM  0x2000_0000 (.data / .rodata)
//        tohost 0x2000_1FC0
//    Ayrica cekirdek testlerimiz zaten bu haritayla kosuyor (env/core_test.ld)
//    ve RTL testbench'i de ayni haritaya gore kurulu. Bu yuzden env/p yerine
//    suite'i BIZIM ortamimiza baglayan ince bir env yaziliyor.
//
//    Sonuc: rv32ui / rv32um test GOVDELERI yukari akistan degistirilmeden
//    kullanilir; yalnizca cerceve (baslangic, bitis, pass/fail) bize ait.
//
//  BITIS PROTOKOLU
//    Kendi testlerimizle AYNI: HTIF tohost'a yazilir (bkz. env/test_env.h).
//      pass -> tohost = 1                 -> spike exit 0
//      fail -> tohost = (TESTNUM<<1)|1    -> spike exit = TESTNUM
//    TESTNUM (x10) hangi alt testte patlandigini soyler; riscv-tests bunu
//    zaten her TEST_CASE basinda yaziyor.
//
//  TESTNUM
//    test_macros.h bu ismi bekler ve `fail` etiketine dallanir.
//    Yukari akis gp (x3) kullanir; fc32e1s_nano_asic x10 kullanir (yalniz x0,x1,x2,x10..x12 var).
// ============================================================

#ifndef SILICORE_RISCV_TEST_H
#define SILICORE_RISCV_TEST_H

//-----------------------------------------------------------------------
// tohost adresi -- env/test_env.h, env/core_test.ld ve run_spike.sh ile
// AYNI olmak zorunda.
//-----------------------------------------------------------------------
#define SILICORE_TOHOST 0x20001FC0

#define TESTNUM x10

//-----------------------------------------------------------------------
// ISA secicileri.
// rv32ui/*.S dosyalari "#define RVTEST_RV64U RVTEST_RV32U" yapip rv64ui
// govdesini dahil ediyor; dolayisiyla hepsinin tanimli olmasi yeterli.
//-----------------------------------------------------------------------
#define RVTEST_RV32U
#define RVTEST_RV64U
#define RVTEST_RV32M
#define RVTEST_RV64M
#define RVTEST_RV32S
#define RVTEST_RV64S

//-----------------------------------------------------------------------
// Kod cercevesi
//-----------------------------------------------------------------------
#define RVTEST_CODE_BEGIN                                               \
        .section .text;                                                 \
        .global _start;                                                 \
_start:                                                                 \
        la    sp, _stack_top;                                           \
        li    TESTNUM, 0;

#define RVTEST_CODE_END

//-----------------------------------------------------------------------
// Bitis: tohost'a 64-bit sonuc yaz.
// Ust kelime ONCE sifirlanir; spike tohost'u 64-bit okuyor, alt kelimeyi
// yazmadan once ustte cop kalmamali.
// x11/x12 kullaniliyor -- test bitmis durumda, ezilmeleri sorun degil.
//-----------------------------------------------------------------------
#define SILICORE_WRITE_TOHOST(val_reg)                                  \
        li    x11, SILICORE_TOHOST;                                     \
        sw    x0, 4(x11);                                               \
        sw    val_reg, 0(x11);                                          \
1:      j     1b;

#define RVTEST_PASS                                                     \
        li    x12, 1;                                                   \
        SILICORE_WRITE_TOHOST(x12)

// TESTNUM = 0 iken (hic TEST_CASE calismadan patlandi) cikis kodu 0 olup
// "basarili" gorunmesin diye en az 1'e cekilir.
#define RVTEST_FAIL                                                     \
        bnez  TESTNUM, 1f;                                              \
        li    TESTNUM, 1;                                               \
1:      slli  x12, TESTNUM, 1;                                          \
        ori   x12, x12, 1;                                              \
        SILICORE_WRITE_TOHOST(x12)

//-----------------------------------------------------------------------
// Veri bolumu.
// core_test.ld bunlari DMEM'e (0x2000_0000) yerlestirir; run_spike.sh
// baslatilmis veriyi ayri bir <test>.dmem.hex olarak uretir ve RTL
// testbench'i onu DMEM'e yukler (bkz. README §"data_init_test").
//-----------------------------------------------------------------------
#define RVTEST_DATA_BEGIN .balign 4;
#define RVTEST_DATA_END

#endif // SILICORE_RISCV_TEST_H
