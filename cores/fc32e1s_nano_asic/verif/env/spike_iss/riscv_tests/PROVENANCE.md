# riscv-tests -- kaynak ve kapsam

## Nereden geldi

| | |
|---|---|
| Depo | https://github.com/riscv-software-src/riscv-tests |
| Commit | `2ebecad997fa58cd9e5724340ba75aa4b59bd1d0` |
| Tarih | 2026-08-15 |
| Lisans | BSD-3-Clause (bkz. [LICENSE](LICENSE)) |

Yukari akistan **degistirilmeden** alinan dosyalar:

| Yol | Icerik |
|---|---|
| `assembly/*.S` | rv32ui + rv32um sarmalayicilari |
| `rv64ui/*.S`, `rv64um/*.S` | test govdeleri (sarmalayicilar bunlari dahil eder) |
| `macros/test_macros.h` | TEST_CASE / TEST_RR_OP vb. makrolar |

Silicore'a ait olan tek dosya `env/riscv_test.h`; suite'i bizim bellek
haritamiza ve HTIF tohost protokolumuze bagliyor. Gerekcesi o dosyanin
basliginda.

## Alinmayan testler

| Test | Neden |
|---|---|
| `rv32ui/ma_data` | Hizasiz veri erisiminin TUZAK uretmesini bekliyor. Minimal env'imizde tuzak isleyici yok; test spike'ta sonsuza kadar kosuyor. Tuzak yolu ayrica `basic_isa_tests/trap_test.s` ile dogrulaniyor. |

rv32uc (sikistirilmis), rv32ua (atomik), rv32uf/ud (kayan nokta) ve rv32si
kumeleri alinmadi: cekirdek yapilandirmasi FPU=0 ve A uzantisi yok;
sikistirilmis yol `basic_isa_tests/compressed_test.s` ile kapsaniyor.

## Guncelleme

Yukari akisi tazelemek icin depoyu klonlayip bu dizindeki dosyalari
degistirin ve `PROVENANCE.md`'deki commit'i guncelleyin. `env/riscv_test.h`
BIZE ait -- ustune yazmayin.

## fence_i neden cikarildi (olculdu)

`rv32ui/fence_i` kendi kendini degistiren kodu sinar: buyruklari `.data`
bolumune yazar, `fence.i` cagirir ve **oradan calistirir**. Bizim linker
scriptimiz `.data`yi DMEM'e (0x2000_0000) koyuyor; Silicore'un adres haritasi
ayrik (IMEM 0x0000_0000 / DMEM 0x2000_0000) ve cekirdek testbench'i bunu
sadakatle modelliyor -- DMEM'den buyruk cekilemiyor.

Olculen davranis: RTL 23 buyrukta `[TB] HATA: IMEM disi buyruk cekme adresi`
ile duruyor, spike ise 263 buyruk kosuyor.

Bu bir cekirdek hatasi degil, adres haritasi farki. `Zifencei` yine de ISA
string'inde (`rv32imc_zicsr_zifencei`) ve `fence.i` buyrugu cozuluyor;
kapsanmayan sey yalnizca DMEM'den yurutme senaryosu.
