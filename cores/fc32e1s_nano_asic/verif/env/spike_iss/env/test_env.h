/* ============================================================
 *  test_env.h -- Spike ISS <-> RTL karsilastirmali cekirdek
 *                testleri icin ortak test ortami
 *
 *  NEDEN VAR
 *  ---------
 *  Testler eskiden "j end" sonsuz dongusuyle bitiyordu. Bunun iki
 *  sonucu vardi:
 *    1) Simulasyon timeout'a kadar ayni komutu trace'ledigi icin RTL
 *       logunun ~%99'u ayni jump satiriydi (26.500 satirin 26.400'u).
 *    2) Spike ve RTL farkli yerlerde kesildigi icin iki trace'in
 *       uzunlugu esit degildi; checker min(len) aldigi icin kisa
 *       kalan taraf sessizce "basarili" sayilabiliyordu.
 *
 *  Cozum: HTIF "tohost" protokolu (riscv-tests standardi).
 *    - Test biterken tohost adresine bir sonuc kelimesi yazilir.
 *    - Spike bu yazmayi gorup kendini TEMIZ sekilde sonlandirir ve
 *      exit code uretir  -> test spike tarafinda self-checking olur.
 *    - RTL testbench ayni adrese yapilan store'u gorup $finish eder.
 *    - Iki trace boylece AYNI komutta biter; uzunluk esitligi
 *      checker icin gecerli bir kontrol haline gelir.
 *
 *  TOHOST KODLAMASI (fesvr syscall device, device=0 cmd=0)
 *  ------------------------------------------------------
 *    yazilan_kelime = (exit_code << 1) | 1
 *      1            -> exit_code 0  -> BASARILI
 *      (N << 1) | 1 -> exit_code N  -> N numarali test blogunda HATA
 *  TEST_CNT (x10) test sayaci oldugu icin TEST_FAIL exit code olarak onu
 *  yollar: spike'in exit code'u dogrudan patlayan blogu soyler.
 *
 *  KULLANIM
 *  --------
 *    #include "test_env.h"
 *        _start:  TEST_INIT
 *                 ...
 *        pass:    TEST_PASS
 *        fail:    TEST_FAIL
 *
 *  Derleme (cpp gerekiyor, bkz. run_core_tests.sh):
 *    riscv64-unknown-elf-gcc -x assembler-with-cpp -Ienv ...
 * ============================================================ */

#ifndef TEST_ENV_H
#define TEST_ENV_H

/* Test block counter register. fc32e1s_nano_asic has only x0, x1, x2, x10..x12,
 * so x10 (a0) is the counter. TEST_FAIL turns it into the exit code in a0
 * itself (slli a0, a0, 1 -- read before write, no extra register needed). */
#define TEST_CNT x10

/* Testbench'in izledigi sabit adresler. core_test.ld ile birebir
 * ayni olmak zorunda -- degistirirsen ikisini birlikte degistir. */
#define TOHOST_ADDR   0x20001FC0
#define FROMHOST_ADDR 0x20001FC8

/* ------------------------------------------------------------
 * TEST_INIT -- yigin isaretcisi ve test sayacini kur.
 * TEST_CNT (x10) tum testlerde "kacinci blokta oldugumuz" sayacidir;
 * hata halinde exit code olarak kullanilir.
 * ------------------------------------------------------------ */
.macro TEST_INIT
    la   sp, _stack_top
    li   TEST_CNT, 0
.endm

/* ------------------------------------------------------------
 * TEST_END_WRITE -- tohost'a 64-bit sonucu yaz.
 * Ust kelime ONCE sifirlanir: spike her adimdan sonra tohost'u
 * 64-bit okur, alt kelimeyi yazmadan once ustte cop kalmamali.
 * ------------------------------------------------------------ */
.macro TEST_END_WRITE
    li   a1, TOHOST_ADDR
    sw   x0, 4(a1)          /* tohost[63:32] = 0 */
    sw   a0, 0(a1)          /* tohost[31:0]  = sonuc -> spike burada durur */
1:  j    1b                 /* RTL TB $finish edene kadar bekle */
.endm

/* ------------------------------------------------------------
 * TEST_PASS -- exit code 0
 * ------------------------------------------------------------ */
.macro TEST_PASS
    li   a0, 1
    TEST_END_WRITE
.endm

/* ------------------------------------------------------------
 * TEST_FAIL -- exit code = TEST_CNT (patlayan test blogunun numarasi)
 * TEST_CNT = 0 ise exit code 0 ile "basarili" gorunmesin diye en az 1'e
 * cekilir.
 * ------------------------------------------------------------ */
.macro TEST_FAIL
    bnez TEST_CNT, 1f
    li   TEST_CNT, 1             /* sayac hic artmamissa yine de hata bildir */
1:  slli a0, TEST_CNT, 1
    ori  a0, a0, 1
    TEST_END_WRITE
.endm

/* ------------------------------------------------------------
 * TEST_FAIL_CODE <n> -- sabit hata kodu ile bitir
 * ------------------------------------------------------------ */
.macro TEST_FAIL_CODE code
    li   a0, (((\code) << 1) | 1)
    TEST_END_WRITE
.endm

#endif /* TEST_ENV_H */
