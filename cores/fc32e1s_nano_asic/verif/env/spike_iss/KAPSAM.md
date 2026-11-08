# Cekirdek Testleri -- Komut Kapsami

Kaynak: `verification/cpu/spike_iss/*/rtl_logs/rtl_*.log`
(Spike altin izleriyle birebir esit dogrulanmis izler.)

## Test basina yurutulen buyruk sayisi

| Test | Buyruk | Tekil buyruk turu |
|---|---:|---:|
| `add` | 432 | 6 |
| `addi` | 209 | 5 |
| `and` | 452 | 6 |
| `andi` | 165 | 6 |
| `auipc` | 25 | 7 |
| `beq` | 258 | 6 |
| `bge` | 276 | 6 |
| `bgeu` | 301 | 6 |
| `blt` | 258 | 6 |
| `bltu` | 283 | 6 |
| `bne` | 258 | 5 |
| `bubble_sort` | 168 | 11 |
| `compressed_test` | 81 | 24 |
| `csr_test` | 76 | 12 |
| `data_init_test` | 81 | 11 |
| `div` | 63 | 6 |
| `divu` | 64 | 6 |
| `full_isa_test` | 120 | 37 |
| `full_isa_test_2` | 74 | 20 |
| `hazard_test` | 97 | 11 |
| `jal` | 22 | 6 |
| `jalr` | 82 | 6 |
| `lb` | 220 | 6 |
| `lbu` | 220 | 6 |
| `ld_st` | 930 | 12 |
| `lh` | 236 | 6 |
| `lhu` | 245 | 6 |
| `lui` | 32 | 6 |
| `lw` | 250 | 6 |
| `matrix_multiplication` | 222 | 11 |
| `mul` | 426 | 6 |
| `mulh` | 426 | 6 |
| `mulhsu` | 426 | 6 |
| `mulhu` | 426 | 6 |
| `or` | 455 | 6 |
| `ori` | 172 | 6 |
| `rem` | 63 | 6 |
| `remu` | 63 | 6 |
| `sb` | 421 | 9 |
| `sh` | 474 | 9 |
| `simple` | 8 | 4 |
| `sll` | 460 | 6 |
| `slli` | 208 | 6 |
| `slt` | 426 | 6 |
| `slti` | 204 | 6 |
| `sltiu` | 204 | 6 |
| `sltu` | 426 | 6 |
| `sra` | 479 | 6 |
| `srai` | 223 | 6 |
| `srl` | 473 | 6 |
| `srli` | 217 | 6 |
| `st_ld` | 450 | 12 |
| `stres_test` | 27 | 8 |
| `sub` | 424 | 6 |
| `sw` | 481 | 7 |
| `trap_test` | 103 | 15 |
| `xor` | 454 | 6 |
| `xor_cipher` | 202 | 11 |
| `xori` | 174 | 6 |
| **TOPLAM** | **15195** | **73** |

## Kume bazinda kapsam

| Kume | Kapsanan / Toplam | Oran |
|---|---:|---:|
| RV32I -- aritmetik/mantik (yazmac) | 10 / 10 | %100 |
| RV32I -- aritmetik/mantik (anlik) | 9 / 9 | %100 |
| RV32I -- ust anlik | 2 / 2 | %100 |
| RV32I -- dallanma | 6 / 6 | %100 |
| RV32I -- ziplama | 2 / 2 | %100 |
| RV32I -- yukleme | 5 / 5 | %100 |
| RV32I -- saklama | 3 / 3 | %100 |
| RV32I -- sistem | 4 / 4 | %100 |
| Zicsr | 6 / 6 | %100 |
| RV32M -- carpma | 4 / 4 | %100 |
| RV32M -- bolme | 4 / 4 | %100 |
| RV32C -- sikistirilmis | 18 / 18 | %100 |
| **TOPLAM** | **73 / 73** | **%100.0** |

## Yurutulen buyruklar (azalan sayida)

| Buyruk | Adet |
|---|---:|
| `addi` | 8132 |
| `bne` | 2191 |
| `lui` | 1625 |
| `auipc` | 478 |
| `sw` | 304 |
| `lw` | 242 |
| `add` | 163 |
| `bge` | 121 |
| `sb` | 110 |
| `lb` | 109 |
| `sh` | 108 |
| `lh` | 107 |
| `slli` | 83 |
| `mul` | 81 |
| `jal` | 79 |
| `sub` | 59 |
| `xor` | 58 |
| `sra` | 58 |
| `srl` | 58 |
| `sll` | 57 |
| `beq` | 54 |
| `slt` | 54 |
| `lhu` | 54 |
| `lbu` | 53 |
| `sltu` | 53 |
| `mulh` | 50 |
| `mulhu` | 50 |
| `mulhsu` | 50 |
| `bgeu` | 47 |
| `and` | 42 |
| `or` | 42 |
| `blt` | 40 |
| `bltu` | 40 |
| `srai` | 34 |
| `c.addi` | 32 |
| `srli` | 31 |
| `slti` | 31 |
| `sltiu` | 31 |
| `andi` | 25 |
| `csrrs` | 20 |
| `ori` | 20 |
| `xori` | 20 |
| `div` | 12 |
| `rem` | 12 |
| `jalr` | 10 |
| `divu` | 10 |
| `remu` | 10 |
| `csrrw` | 9 |
| `mret` | 5 |
| `ecall` | 3 |
| `c.add` | 2 |
| `c.sw` | 2 |
| `c.lw` | 2 |
| `csrrwi` | 2 |
| `csrrsi` | 2 |
| `c.sub` | 1 |
| `c.and` | 1 |
| `c.or` | 1 |
| `c.xor` | 1 |
| `c.andi` | 1 |
| `c.slli` | 1 |
| `c.srli` | 1 |
| `c.srai` | 1 |
| `c.lui` | 1 |
| `c.beq` | 1 |
| `c.bne` | 1 |
| `c.jal` | 1 |
| `c.jalr` | 1 |
| `csrrc` | 1 |
| `csrrci` | 1 |
| `fence` | 1 |
| `ebreak` | 1 |
| `c.ebreak` | 1 |

## Hic yurutulmeyen buyruklar

Yok -- kapsam dahilindeki butun buyruklar en az bir kez yurutuldu.

## Kapsam disi (paydaya dahil degil)

- `dret` -- yalnizca hata ayiklama (debug) modunda gecerli; JTAG ile debug moduna girmeden yurutulemez
- `wfi` -- bekleyen kesme yokken cekirdegi uyutur; cekirdek testinde simulasyonu sonsuza kadar askida birakir

