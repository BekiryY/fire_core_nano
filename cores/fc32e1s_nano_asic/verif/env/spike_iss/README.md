# Çekirdek Doğrulama — Spike ISS ↔ RTL Komut İzi Karşılaştırması

Bu dizin, Silicore SoC'de kullanılan **CV32E40P** çekirdeğinin bireysel
(çekirdek seviyesi) testlerini barındırır. Testler hem **Spike ISS** altın
modelinde hem de RTL simülasyonunda koşulur; iki taraftan alınan komut izleri
(instruction trace) satır satır karşılaştırılır.

> Şartname karşılığı: *"SoC'de kullanılacak olan ve şartnamede tanımlanan
> işlemci çekirdeği doğrulanırken Spike ISS sonuçları ile karşılaştırılarak
> test programlarının doğru çalıştığı gösterilmelidir."* (Teknik Şartname
> v1.3, §4.1) ve EK-3 **Çekirdek Testleri** satırı (self-checking, çevrimdışı
> log karşılaştırması).

---

## 1. Hızlı başlangıç

Uçtan uca doğrulama (Spike + RTL + karşılaştırma, bkz. §7):

```bash
cd verification/cpu/spike_iss
./run_core_tests.sh
```

Yalnızca Spike altın izlerini üretmek için:

```bash
./run_spike.sh
```

Tek test için:

```bash
./run_spike.sh stres_test
```

Çıkış kodu: **0 = tüm testler geçti**, **1 = en az bir test başarısız**,
**127 = araç eksik**. Yani doğrudan CI/regresyon içinde kullanılabilir.

### Gereksinimler

| Araç | Bu akışın doğrulandığı sürüm | Kurulum |
|---|---|---|
| `riscv64-unknown-elf-gcc` | 13.2.0 (Ubuntu 13.2.0-11ubuntu1+12) | `apt install gcc-riscv64-unknown-elf` |
| `spike` | 1.1.1-dev | [riscv-isa-sim](https://github.com/riscv-software-src/riscv-isa-sim) |
| `bash`, `awk`, `grep`, `timeout` | coreutils | — |

`riscv64-unknown-elf-gcc` **rv32im/ilp32 multilib** içermelidir
(`riscv64-unknown-elf-gcc --print-multi-lib | grep rv32im`).

Akış **Linux/WSL** gerektirir; Windows üzerinde doğrudan çalışmaz.
Araç adları ortam değişkeniyle geçersiz kılınabilir:
`CC=... SPIKE=... ./run_spike.sh`

> **Satır sonu uyarısı.** Depoda `core.autocrlf=true` ve kök dizinde
> `.gitattributes` yok; yani Windows'ta yapılan checkout metin dosyalarını
> CRLF'e çeviriyor. CRLF'li bir `run_spike.sh` WSL altında
> `$'\r': command not found` ile patlar, CRLF'li golden log ise satır satır
> karşılaştırmayı bozar. Bu dizindeki `.gitattributes` metin dosyalarını
> LF'te sabitler — dosyayı silmeyin.

---

## 2. Dizin yapısı

```
verification/cpu/spike_iss/
├── run_spike.sh                 # Spike akışı: derle → koş → golden trace üret
├── checker.py                   # çevrimdışı trace karşılaştırıcı (RTL ↔ Spike)
├── env/
│   ├── test_env.h               # TEST_INIT / TEST_PASS / TEST_FAIL makroları
│   └── core_test.ld             # linker script (adres haritası + tohost)
├── basic_isa_tests/             # izole komut testleri
│   ├── assembly/*.s             # kaynak (tek gerçek girdi)
│   ├── assembly/*.dis           # üretilen: objdump disassembly
│   ├── elf/, hex/               # üretilen: ELF ve imem verilog hex
│   ├── spike_logs/*.log         # üretilen: KIRPILMIŞ golden trace
│   ├── spike_logs/*.raw.log     # üretilen: spike ham çıktısı (denetim için)
│   └── rtl_logs/*.log           # RTL simülasyonundan alınan iz
└── directed_functional_tests/   # algoritma seviyesi testler (aynı yapı)
```

`assembly/*.s` dışındaki her şey **üretilen çıktıdır**; `run_spike.sh`
yeniden üretir.

---

## 3. Testler nasıl bitiyor — HTIF `tohost`

### Önceki durum ve sorunu

Testler `j end` sonsuz döngüsüyle bitiyordu. Bunun ölçülmüş üç sonucu vardı:

1. **Log şişmesi.** Simülasyon timeout'a kadar aynı jump'ı trace'lediği için
   RTL loglarının ~%99'u tek bir satırın tekrarıydı:

   | Test | Eski RTL log | Gerçek komut | Tekil PC |
   |---|---|---|---|
   | `full_isa_test` | 26.546 | ~115 | 116 |
   | `stres_test` | 26.527 | ~18 | 19 |
   | `bubble_sort` | 26.494 | ~140 | 32 |

   `checker.py`'nin "5219 komut tam eşleşti" çıktısının 5099'u aynı `j end`
   satırıydı; raporlanan sayı bu yüzden gerçek kapsamı yansıtmıyordu.

2. **Uzunluk eşitliği kontrol edilemiyordu.** Spike ve RTL farklı yerlerde
   kesildiği için `checker.py` `min(len)` almak zorundaydı; kısa kalan taraf
   sessizce "başarılı" sayılabiliyordu.

3. **Spike hiç durmuyordu.** Ölçüldü: `tohost`'a yazmayan bir test spike'ı
   *sonsuza kadar* koşturur. Eski akışta spike'ı bir şekilde dışarıdan
   kesmek gerekiyordu, dolayısıyla trace uzunluğu keyfiydi.

### Şimdiki mekanizma

Testler `env/test_env.h` içindeki makrolarla, riscv-tests standardı olan
**HTIF `tohost`** protokolü üzerinden biter:

```asm
#include "test_env.h"
_start:
    TEST_INIT           # sp = _stack_top, x30 = 0 (test blok sayacı)
    ...
pass:
    TEST_PASS           # tohost <- 1
fail:
    TEST_FAIL           # tohost <- (x30 << 1) | 1
```

`tohost` yazılan kelime `(exit_code << 1) | 1` olarak kodlanır:

| Yazılan | Spike exit code | Anlamı |
|---|---|---|
| `1` | 0 | Test **geçti** |
| `(N<<1)\|1` | N | **x30 = N** numaralı test bloğunda hata |

Böylece:

- **Spike kendini temiz sonlandırır** ve pass/fail'i exit code olarak verir →
  test spike tarafında *self-checking* olur, manuel inceleme gerekmez.
- **RTL testbench** aynı adrese yapılan store'u görüp `$finish` eder.
- İki iz **aynı komutta** biter.

`x30` her test bloğunun başında artırıldığı için spike'ın exit code'u doğrudan
hangi blokta patladığını söyler.

### Hata yolu doğrulaması (fault injection)

Mekanizmanın hatayı gerçekten yakaladığı, `stres_test` üzerinde kasten hata
enjekte edilerek ölçüldü:

| Senaryo | Beklenen | Ölçülen |
|---|---|---|
| Sağlam test | exit 0 | **exit 0** |
| Blok 1 beklentisi bozuldu (`li x6, 0x10` → `0x11`) | exit 1 | **exit 1**, `*** FAILED *** (tohost = 1)` |
| Blok 3 beklentisi bozuldu (`li x14, 0x78` → `0x79`) | exit 3 | **exit 3**, `*** FAILED *** (tohost = 3)` |
| `tohost`'a hiç yazmayan eski tarz test | sonlanmamalı | **sonsuz koştu** → runner'da `timeout` zorunlu |

---

## 4. Golden trace neden kırpılıyor

Spike, HTIF'i her komutta değil belirli aralıklarla (INTERLEAVE) yoklar. Bu
yüzden `tohost` yazıldıktan sonra bekleme döngüsünü birkaç bin kez daha
koşturup loga yazabilir. Aynı ELF, aynı spike sürümüyle ölçülen kuyruk
uzunlukları:

| Spike log modu | tohost sonrası satır |
|---|---|
| `-l` (disassembly) | 1 |
| `-l --log-commits` | 4974 |
| `--log-commits` | 4973 |

Kuyruk uzunluğu **anlamlı bir değer değil, araç artifaktıdır** (RTL tarafında
da TB'nin `$finish`'e ne kadar gecikmeyle tepki verdiğine bağlıdır). Bu
nedenle `run_spike.sh`, golden trace'i `tohost` store satırında — o satır
**dahil** — keser:

```
core   0: 3 0x00000054 (0x00a2a023) mem 0x20001fc0 0x00000001   <- son satır
```

Ham çıktı `*.raw.log` olarak denetim için saklanır. **Aynı kırpma RTL logunda
da uygulanmalıdır**; ancak o zaman iki iz arasındaki uzunluk eşitliği
`checker.py` için geçerli bir kontrol haline gelir.

### Kırpma sonrası golden trace boyutları

| Test | Eski (dolgulu) | Şimdi | Tekil PC |
|---|---|---|---|
| `full_isa_test` | 26.546 | **125** | 125 |
| `full_isa_test_2` | 26.433 | **79** | 79 |
| `stres_test` | 26.527 | **32** | 32 |
| `bubble_sort` | 26.494 | **173** | 64 |
| `matrix_multiplication` | 26.555 | **227** | 81 |
| `xor_cipher` | 26.501 | **207** | 65 |

> `directed_functional_tests` degerleri, testler self-checking hale
> getirildikten sonraki (sonucu dogrulayan dongu dahil) hallerdir.

---

## 5. Spike çağrısı ve gerekçeleri

```bash
spike --isa=rv32imc_zicsr_zifencei \
      -m0x0:0x1000,0x20000000:0x2000 \
      --log-commits --log=<çıktı> <test>.elf
```

| Seçenek | Gerekçe |
|---|---|
| `--isa=rv32imc_zicsr_zifencei` | Silicore'daki `cv32e40p_top` örneği `COREV_PULP=0, COREV_CLUSTER=0, FPU=0, ZFINX=0, NUM_MHPMCOUNTERS=1` ile kurulu ([silicore_core_top.sv:310](../../rtl/top/silicore_core_top.sv)) ve compressed decoder aktif ([cv32e40p_if_stage.sv:273](../../rtl/cv32e40p/cv32e40p_if_stage.sv)) → çekirdek RV32IMC_Zicsr_Zifencei. ISS'in ISA'sı çekirdekle aynı olmazsa karşılaştırma anlamsızdır. |
| `-m0x0:0x1000,...` | IMEM 0x0 tabanlı. Üst sınır 4 KB, çünkü spike kendi reset vektörünü 0x1000'e (`DEFAULT_RSTVEC`) boot ROM olarak koyar; çakışmaması gerekir. Linker script bunu `ASSERT` ile zorlar. |
| `...,0x20000000:0x2000` | DMEM, gerçek tasarımla birebir: 0x2000_0000–0x2000_1FFF, 8 KB ([axi_internconnect.sv:49](../../rtl/control_and_bus/axi4/axi_internconnect.sv), [dmem_top.sv:5](../../rtl/memory/dmem/dmem_top.sv)). |
| `--log-commits` (tek başına, `-l` **yok**) | Register writeback ve memory adres/veri alanlarını üretir (`x5 0x...`, `mem 0x... 0x...`) — değer karşılaştırması için gerekli. `-l` eklenirse her komut için ayrıca bir disassembly satırı basılır ve satır bazlı parser'lar komutları **iki kez** sayar. |
| `timeout 30` | `tohost`'a yazmayan test spike'ı sonsuza kadar koşturur (§3'te ölçüldü). |

Derleme:

```bash
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -g \
  -x assembler-with-cpp -I env -T env/core_test.ld <test>.s -o <test>.elf
```

`-x assembler-with-cpp` gerekiyor çünkü testler `#include "test_env.h"`
kullanıyor (dosya uzantısı `.s` olduğu için gcc kendiliğinden cpp çalıştırmaz).

---

## 6. Adres haritası

`env/core_test.ld` içinde tanımlı; gerçek SoC haritasıyla birebir:

| Aralık | İçerik |
|---|---|
| `0x0000_0000` – `0x0000_0FFF` | `.text` (IMEM). 4 KB sınırı `ASSERT` ile zorlanır. |
| `0x2000_0000` – `0x2000_1EFF` | `.rodata` / `.data` / `.bss` (DMEM) |
| `0x2000_1F00` – `0x2000_1FBF` | yığın (yukarıdan aşağı büyür), `_stack_top = 0x2000_1FC0` |
| `0x2000_1FC0` | **`tohost`** ← RTL testbench bu adresi izler |
| `0x2000_1FC8` | `fromhost` |

`tohost`/`fromhost` `NOLOAD` bölümdedir: hex çıktısına girmez, yalnızca ELF
sembolü olarak bulunur. Spike bu iki sembolü ELF'ten okuyup HTIF'i bağlar;
sembol yoksa `tohost and fromhost symbols not in ELF` uyarısı verir ve test
sonucunu göremez.

`TOHOST_ADDR` üç yerde geçer ve **üçü de aynı olmak zorundadır**:
`env/test_env.h`, `env/core_test.ld`, `run_spike.sh`.

---

## 7. Tam regresyon

`run_spike.sh` yalnizca altin izleri uretir. Uctan uca dogrulama:

```bash
cd verification/cpu/spike_iss
./run_core_tests.sh
```

Uc asamayi sirayla kosar ve tek bir cikis kodu uretir:

1. `run_spike.sh` — Spike ISS altin izleri
2. `../tb/core/run_core_rtl.sh` — RTL izleri (xsim, cv32e40p_tracer)
3. `checker.py` — her test icin iki izi PC, buyruk, yazmac ve bellek
   alanlariyla karsilastirir

Guncel durum: **59/59 test, 59/59 iz birebir esliyor** (`TUM CEKIRDEK
REGRESYONU GECTI`, exit 0).

### Test gruplari

| Grup | Adet | Icerik |
|---|---:|---|
| `basic_isa_tests` | 8 | izole buyruk testleri (ISA, CSR, tuzak, hazard, sikistirilmis, veri baslatma) |
| `directed_functional_tests` | 3 | algoritma seviyesi (bubble sort, matris carpimi, XOR sifreleme) |
| `riscv_tests` | 48 | yukari akis riscv-tests suite'i (rv32ui + rv32um), bkz. [riscv_tests/PROVENANCE.md](riscv_tests/PROVENANCE.md) |

### Yukari akis riscv-tests

`riscv_tests/` altindaki test GOVDELERI yukari akistan degistirilmeden
alinmistir (BSD-3-Clause). Silicore'a ait tek dosya
[`riscv_tests/env/riscv_test.h`](riscv_tests/env/riscv_test.h): yukari akisin
`env/p` ortami kodu 0x8000_0000'a linkleyip kendi tuzak vektorunu kurar, bizim
haritamiz farkli (IMEM 0x0 / DMEM 0x2000_0000 / tohost 0x2000_1FC0). Bu env
suite'i bizim haritamiza ve HTIF tohost protokolune baglar.

Alinmayan iki test ve olculmus gerekceleri PROVENANCE.md'de: `ma_data`
(tuzak isleyici gerektiriyor) ve `fence_i` (buyruklari `.data`ya yazip
ORADAN calistiriyor; Silicore'un ayrik adres haritasinda DMEM'den buyruk
cekilemez -- cekirdek hatasi degil, harita farki).

### Bayat iz korumasi

RTL asamasi derleme/elaborasyon hatasi verirse `rtl_logs/` altindaki ESKI
izler yerinde kalir ve karsilastirma onlari kullanip "ESLESTI" yazabilir.
Bu gercekten yasandi: cekirdekten kaldirilan portlar TB'de surulmeye devam
edince `xelab` patladi, karsilastirma 4 gun onceki loglarla yapildi ve sonuc
inandirici bir sekilde dogru gorundu.

Onlem: `run_core_rtl.sh` derlemeden **once** `.rtl_run_stamp` damgasini siler,
derleme gecince yeniden atar. `run_core_tests.sh` her izin bu damgadan yeni
oldugunu dogrular; degilse `IZ BAYAT` deyip basarisiz olur. Elaborasyon
kasten bozularak test edildi: butun izler `IZ BAYAT`, exit 1.

Ayrica olculdu: ~8 tam kosumun **birinde** xsim kostu ama tracer iz dosyasini
olusturamadi (dosya tutamaci yarisi; tekrarlanmadi). `run_core_rtl.sh` artik
(a) onceki izin GERCEKTEN silindigini dogruluyor, (b) iz uretilmezse bir kez
yeniden deniyor ve yeniden denedigini `[xsim yeniden denendi]` diye
RAPORLUYOR -- kararsizlik gizlenmiyor, gorunur kaliyor.

### Tek RTL

Proje tek bir RTL kullaniyor; ASIC icin ayri tasarim yok. Eskiden
`cv32e40p_register_file`'in ikinci bir gerceklemesi (`rtl/asic/
cv32e40p_register_file_ff.sv`) ve buna bagli `--asic` / `--fpga` / `--both`
varyantlari vardi. O dizin `154f409`'da silindi; varyantlar da kaldirildi.
`rtl_logs/` altinda `*.asic.log` gorurseniz bayattir, silin.

---

## 8. Komut kapsami

`run_core_tests.sh` son asamada `coverage.py` calistirir ve
[`KAPSAM.md`](KAPSAM.md) uretir: hangi buyrugun kac kez yurutuldugu,
kume bazinda kapsam orani ve hic calismayan buyruklar.

Sartname EK-3'teki *"tanimlanan dogrulama kapsaminin genisligi ve bu kapsam
bunyesindeki dogrulama basarim orani"* puan satirinin nicel karsiligi budur;
"59 test gecti" tek basina bunu karsilamiyor.

Guncel kapsam: **73 / 73 buyruk (%100)**.

| Kume | Kapsam |
|---|---|
| RV32I (aritmetik, mantik, dallanma, ziplama, yukleme, saklama) | %100 |
| RV32M (carpma, bolme) | %100 |
| Zicsr | %100 |
| RV32I sistem (`fence`, `ecall`, `ebreak`, `mret`) | %100 |
| RV32C sikistirilmis | %100 |

### Tuzak isleyicisi neden boyut farkinda

`c.ebreak` uzun sure kapsanamadi: `trap_test.s`'in isleyicisi `mepc += 4`
yapiyordu, yani tuzaklanan her buyrugun 32-bit oldugunu varsayiyordu.
`c.ebreak` 2 byte oldugu icin o isleyiciyle donus adresi yanlis cikardi.

Isleyici artik buyrugu mepc'den okuyup uzunlugunu belirliyor (RISC-V
kodlamasinda alt iki bit `11` ise 32-bit, degilse 16-bit) ve mepc'yi 2 ya da
4 artiriyor. Bu yalnizca kapsam icin degil, dogrusu da bu: sikistirilmis
buyruk tuzaklayabilen her isleyici boyut farkinda olmak zorunda.

`trap_test.s` genelinde `-march=rv32im` kullaniliyor ki `ebreak` 32-bit
kalsin (C acikken assembler onu da `c.ebreak`'e sikistirir ve 32-bit ebreak
kapsami kaybolurdu). C yalnizca tek buyrukluk aciliyor:

```asm
    .option push
    .option arch, +c
    c.ebreak
    .option pop
```

Kapsam **paydasindan dusulen** iki buyruk var (KAPSAM.md'de gerekcesiyle):

| Buyruk | Neden erisilemez |
|---|---|
| `dret` | yalnizca hata ayiklama modunda gecerli; JTAG ile debug moduna girmeden yurutulemez |
| `wfi` | bekleyen kesme yokken cekirdegi uyutur, simulasyonu sonsuza kadar askida birakir |

### Kapsam sayimi tracer sozcuk dagarcigina gore

`coverage.py` RTL izini okur (spike commit logunda buyruk adi yok, yalnizca
32-bit kelime var). `cv32e40p_tracer` sikistirilmis bir buyrugu `"c."` oneki
+ **genisletilmis** 32-bit karsiliginin adiyla basar: `c.li`, `c.mv` ve
`c.nop` ucu de `c.addi` olarak, `c.beqz` ise `c.beq` olarak gorunur. ISA
listesi mimari isimlerle yazilsaydi kapsam kalici olarak eksik gorunurdu;
bu yuzden liste tracer'in dagarcigina gore tutuluyor.

---

## 9. Cekirdek yapilandirmasi ve ozellestirmeler

### Yapilandirma parametreleri

`cv32e40p_top` su parametrelerle orneklenir
([silicore_core_top.sv:310](../../rtl/top/silicore_core_top.sv)):

| Parametre | Deger | Etkisi |
|---|---|---|
| `COREV_PULP` | 0 | PULP ISA uzantilari, donanim dongusu, ozel CSR'lar KAPALI |
| `COREV_CLUSTER` | 0 | PULP cluster arayuzu (`cv.elw`) KAPALI |
| `FPU` | 0 | Kayan nokta birimi YOK |
| `ZFINX` | 0 | — |
| `NUM_MHPMCOUNTERS` | 1 | performans sayaci sayisi |

Buradan cekirdegin komut kumesi **RV32IMC_Zicsr_Zifencei** cikar; Spike da
ayni string ile kosulur (bkz. §5).

### Yukari akistan (upstream) farklar

| Ne | Nerede | Neden |
|---|---|---|
| Statik konfigurasyon portlari budandi (`pulp_clock_en_i`, `scan_cg_en_i`, `boot_addr_i`, `mtvec_addr_i`, `dm_halt_addr_i`, `hart_id_i`, `dm_exception_addr_i`) | [cv32e40p_top.sv:39-47](../../rtl/cv32e40p/cv32e40p_top.sv), commit `37621d1` | CPU sertlestirilmis makro olarak uretiliyor; makro pin listesi sabit. Degerler modul icinde baglaniyor: boot=0x0, mtvec=0x0, **dm_halt=0x200**, **dm_exception=0x208**, hart_id=0, pulp_clock_en=1, scan_cg_en=0 |
| Yazmac obegi Gowin LUTRAM tabanli | [cv32e40p_register_file_ff_gowin.sv](../../rtl/cv32e40p/cv32e40p_register_file_ff_gowin.sv) | FPGA kaynak kullanimini dusurmek icin |
| Ayri ASIC yazmac obegi kaldirildi | `rtl/asic/` (commit `154f409`) | Tek RTL kullaniliyor; CPU ASIC'e makro olarak giriyor |

`dm_halt_addr` / `dm_exception_addr` **sifir olamaz**: cekirdek hata ayiklama
moduna girince PC'yi oraya alip komut cekmeye devam eder, dolayisiyla o
adreste anlamli kod bulunmak zorundadir. Degerler `rtl/control_and_bus/JTAG/debug_rom.sv`,
`rtl/control_and_bus/address_decoder.sv` ve `silicore_core_top.sv`'deki `DBG_ROM_BASE` ile
tutarli olmali; ucu ayrisirsa elaborate zamaninda hata verilir.

### ISS ile bilinen ve KABUL EDILEN farklar

Bunlar cekirdek hatasi degil, iz formati / modelleme farklaridir. `checker.py`
her birini acikca ele alir; sessizce yutmaz.

| Fark | Nasil ele aliniyor |
|---|---|
| Spike, **tuzaga dusen** buyruk icin commit satiri basmaz; tracer o buyrugu retire edilmis sayip basar | `checker.py compare()` uc kosul birden saglaniyorsa (PC ayristi, RTL adiminin yazmac/bellek etkisi yok, sonraki RTL adimi spike'in PC'sinde) RTL satirini atlar ve raporda sayar |
| Sikistirilmis buyruklarda spike ham 16-bit, tracer acilmis 32-bit kelime basar | buyruk kelimesi karsilastirilmaz, PC + yazmac + bellek karsilastirilir; atlanan sayisi raporlanir |
| Spike 0x1000'deki kendi boot ROM'unu kosar | `strip_spike_bootrom()` bastaki adimlari atar |
| `tohost` sonrasi bekleme dongusu | iki iz de tohost store satirinda kirpilir (§4) |
| **`mtvec` yalnizca [31:8]** saklanir (cv32e40p), Spike'ta daha genis yazilabilir | fark degil, KISIT: tuzak isleyicileri **256-byte hizali** olmak zorunda. `trap_test.s` bu yuzden `.balign 256` kullanir; hizasiz adres iki modeli ayristirir |

---

## 10. Bilinen eksikler

1. **Rastgele (random) test yok.** Butun testler yonlendirilmis (yukari akis
   riscv-tests dahil). `riscv-dv` ya da benzeri bir uretecle tohumlanmis
   kosumlar kapsami komut *kombinasyonlari* yonunde genisletirdi.
2. **Kesme (interrupt) yolu dogrulanmadi.** `trap_test.s` istisna yolunu
   (ecall/ebreak) kapsiyor; harici kesme, `mie`/`mip` ve kesme onceligi
   sinanmiyor. Cekirdek testi seviyesinde kesme uretmek TB destegi ister.
3. **`asic/` akisinda acik kalanlar** (cekirdek regresyonundan bagimsiz,
   `asic/scripts/preflight.sh` ile gorulebilir):
   `config.yaml` glob'lari `rtl/control_and_bus/axi4/axi_if.sv` ve `obi_if.sv` arayuz
   dosyalarini iceriye cekiyor (preflight bunlarin Yosys'i kirdigini
   soyluyor); SRAM makro gorunumleri indirilmemis; floorplan'da makro
   cakismalari var; `rtl/asic/prom_bootrom_asic.sv` uretilmemis.
