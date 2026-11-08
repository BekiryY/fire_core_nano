#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
checker.py -- Spike ISS altin izi ile RTL komut izini karsilastirir.

    python3 checker.py <spike_log> <rtl_log>

CIKIS KODU
    0  iki iz birebir eslesti
    1  uyusmazlik / uzunluk farki
    2  kullanim hatasi, dosya yok veya iz ayristirilamadi

Sifir disi cikis kodu ONEMLI: regresyon betikleri (run_core_tests.sh) bu
kodla karar veriyor. Eski surum uyusmazlikta da 0 donduruyordu, dolayisiyla
hicbir otomasyon hatayi goremiyordu.

NE KARSILASTIRILIYOR
--------------------
Her komut icin:
    PC                     her iki tarafta da var
    buyruk kelimesi        her iki tarafta da var
    yazmac yazmalari       spike: "x13 0x00000078"   RTL: "x13=00000078"
    bellek erisim adresi   spike: "mem 0x20000000"   RTL: "PA:20000000"
    store verisi           spike: "mem 0x... 0x..."  RTL: "WD:12345678"

Store verisi RTL tarafinda upstream tracer'da BASILMIYORDU; yerel bir
degisiklikle eklendi (rtl/cv32e40p/bhv/cv32e40p_instr_trace.svh, bkz.
rtl/cv32e40p/bhv/README.md). Load'larda spike veri basmadigi icin
karsilastirma yalnizca adres uzerinden yapilir -- yuklenen deger zaten
hedef yazmacta gorunuyor.

STORE VERISI NORMALIZASYONU
---------------------------
RTL'de data_wdata_o veri yoluna BYTE SERIDINE DONDURULMUS cikar; spike ise
mimari degeri basar. Ornek (sh x14, 6(x11), x14=0x0000ddcc):

    spike: mem 0x20000006 0xddcc
    rtl  : PA:20000006 WD:ddcc0000 BE:c

Ikisi ayni store'dur. Checker, BE alanindaki en dusuk aktif byte kadar saga
kaydirip yalnizca aktif byte'lari maskeleyerek RTL degerini mimari degere
cevirir. BE de yerel bir tracer ekidir; olmayan izlerde (eski loglar) store
verisi karsilastirmasi atlanir.

IZ HIZALAMA
-----------
Spike, ELF'i yuklemeden once kendi boot ROM'unu 0x1000'den (DEFAULT_RSTVEC)
kosuyor; bunlar RTL'de yok. Bu yuzden spike izinin basindaki 0x1000-0x1FFF
araligindaki komutlar atlanir. Bizim IMEM'imiz 0x0-0x0FFF ile sinirli
(core_test.ld), dolayisiyla bu aralik yalnizca spike bootrom'una ait
olabilir -- karisma riski yok.

Hizalamadan sonra IKI IZIN UZUNLUGU ESIT OLMAK ZORUNDA. Her iki taraf da
tohost store satirinda kirpiliyor (run_spike.sh ve run_core_rtl.sh), yani
esitlik gecerli bir kontrol. Eski surum min(len) alip kisa tarafi sessizce
"basarili" sayabiliyordu.

BILINEN SINIR
-------------
Sikistirilmis (RVC) buyruklarda spike 16-bit ham kelimeyi, cv32e40p_tracer
ise ID asamasindaki ACILMIS 32-bit kelimeyi basiyor. Bu durumda buyruk
kelimesi karsilastirmasi atlanir (PC ve etkiler yine karsilastirilir) ve
ozette raporlanir. Testler -march=rv32im ile derlendigi icin su an bu yola
girilmiyor.
"""

import os
import re
import sys

MAX_REPORTED = 10  # en fazla kac uyusmazlik basilsin

# ----------------------------------------------------------------------------
# Spike --log-commits satiri:
#   core   0: 3 0x00000048 (0x00c5a023) mem 0x20000000 0x12345678
#   core   0: 3 0x0000004c (0x0005c683) x13 0x00000078 mem 0x20000000
# ----------------------------------------------------------------------------
SPIKE_RE = re.compile(
    r"^core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)(.*)$"
)
SPIKE_REG_RE = re.compile(r"(?:^|\s)([xf])(\d+)\s+0x([0-9a-fA-F]+)")
SPIKE_MEM_RE = re.compile(r"(?:^|\s)mem\s+0x([0-9a-fA-F]+)(?:\s+0x([0-9a-fA-F]+))?")

# ----------------------------------------------------------------------------
# cv32e40p_tracer satiri:
#   <time> <cycle> <pc> <instr> <ctx> <mnemonic...> x12:... x15=000066bb  PA:.. WD:..
# ctx alani bos olabilir; mnemonic serbest metin oldugu icin alanlar
# desenle cekilir, konumla degil.
# ----------------------------------------------------------------------------
RTL_RE = re.compile(r"^\s*\d+\s+(\d+)\s+([0-9a-fA-F]{8})\s+([0-9a-fA-F]{8})\s(.*)$")
RTL_REG_RE = re.compile(r"(?:^|\s)([xf])(\d+)=([0-9a-fA-F]{8})")
RTL_MEM_RE = re.compile(r"(?:^|\s)PA:([0-9a-fA-F]{8})")
RTL_WD_RE = re.compile(r"(?:^|\s)WD:([0-9a-fA-F]{8})")
RTL_BE_RE = re.compile(r"(?:^|\s)BE:([0-9a-fA-F])")


def arch_store_value(wdata, be):
    """RTL veri yolu degerini mimari store degerine cevir.

    Veri yolunda degerin bulundugu byte seridi be ile belirlidir; en dusuk
    aktif byte'a kadar saga kaydirip aktif byte sayisi kadar maskeleriz.
        wdata=0xddcc0000, be=0b1100 -> 0xddcc
        wdata=0x000000bb, be=0b0001 -> 0xbb
    """
    if be == 0:
        return wdata
    lowest = 0
    while not (be >> lowest) & 1:
        lowest += 1
    nbytes = bin(be).count("1")
    return (wdata >> (8 * lowest)) & ((1 << (8 * nbytes)) - 1)


class Step(object):
    """Tek bir komutun izdeki gorunumu."""

    __slots__ = ("pc", "instr", "regs", "mem_addr", "mem_wdata", "line", "lineno")

    def __init__(self, pc, instr, regs, mem_addr, mem_wdata, line, lineno):
        self.pc = pc
        self.instr = instr
        self.regs = regs  # [(ad, deger)] -- x0 ayiklanmis
        self.mem_addr = mem_addr  # None ya da int
        self.mem_wdata = mem_wdata  # None ya da int; RTL tarafinda BE ile
        # mimari degere normalize edilmis halde tutulur
        self.line = line
        self.lineno = lineno


def _regs_sorted(pairs):
    """x0 yazmalarini at, sirala (iki arac farkli sirada basabilir)."""
    return sorted((n, v) for (n, v) in pairs if n != "x0")


def parse_spike(path):
    steps = []
    with open(path, "r", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            m = SPIKE_RE.match(line)
            if not m:
                continue  # ">>>> sembol" anotasyonlari, exception satirlari vb.
            pc = int(m.group(1), 16)
            instr = int(m.group(2), 16)
            tail = m.group(3)

            regs = [
                (g[0] + str(int(g[1])), int(g[2], 16)) for g in SPIKE_REG_RE.findall(tail)
            ]
            mem_addr = mem_wdata = None
            mm = SPIKE_MEM_RE.search(tail)
            if mm:
                mem_addr = int(mm.group(1), 16)
                if mm.group(2) is not None:
                    mem_wdata = int(mm.group(2), 16)

            steps.append(
                Step(pc, instr, _regs_sorted(regs), mem_addr, mem_wdata, line.rstrip(), lineno)
            )
    return steps


def parse_rtl(path):
    steps = []
    with open(path, "r", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            m = RTL_RE.match(line)
            if not m:
                continue  # baslik satiri
            pc = int(m.group(2), 16)
            instr = int(m.group(3), 16)
            tail = m.group(4)

            regs = [
                (g[0] + str(int(g[1])), int(g[2], 16)) for g in RTL_REG_RE.findall(tail)
            ]
            mem_addr = mem_wdata = None
            mm = RTL_MEM_RE.search(tail)
            if mm:
                mem_addr = int(mm.group(1), 16)
                wm = RTL_WD_RE.search(tail)
                bm = RTL_BE_RE.search(tail)
                if wm and bm:
                    # BE olmadan veri yolu degeri mimari degerle
                    # karsilastirilamaz; BE yoksa store verisi atlanir.
                    mem_wdata = arch_store_value(
                        int(wm.group(1), 16), int(bm.group(1), 16)
                    )

            steps.append(
                Step(pc, instr, _regs_sorted(regs), mem_addr, mem_wdata, line.rstrip(), lineno)
            )
    return steps


def strip_spike_bootrom(steps):
    """Spike'in 0x1000 tabanli boot ROM adimlarini bastan at."""
    i = 0
    while i < len(steps) and 0x1000 <= steps[i].pc < 0x2000:
        i += 1
    return steps[i:], i


def _fmt_regs(regs):
    return " ".join("%s=%08x" % (n, v) for (n, v) in regs) if regs else "-"


def _fmt_mem(step):
    if step.mem_addr is None:
        return "-"
    if step.mem_wdata is None:
        return "0x%08x (load)" % step.mem_addr
    return "0x%08x <- 0x%08x" % (step.mem_addr, step.mem_wdata)


def compare(spike, rtl):
    """Adim adim karsilastir.

    (uyusmazlik_sayisi, rvc_atlanan, tuzak_atlanan) dondurur.

    Iki iz uzerinde IKI AYRI imlecle yurunur (i: spike, j: rtl) cunku
    tuzaga dusen buyruklarda iki tarafin satir sayisi bilerek ayrisir --
    bkz. asagidaki TUZAKLANAN BUYRUK notu.
    """
    mismatches = 0
    rvc_skipped = 0
    trap_skipped = 0
    i = j = 0

    while i < len(spike) and j < len(rtl):
        s, r = spike[i], rtl[j]
        problems = []

        # --- TUZAKLANAN BUYRUK ---
        # Spike, tuzaga dusen buyruk icin commit satiri BASMAZ; dogrudan
        # tuzak vektorundeki ilk buyrugu loglar. cv32e40p_tracer ise o
        # buyrugu retire edilmis sayip basar. Bu bir cekirdek hatasi degil,
        # iz formati farki (trap_test.s ile olculdu: ecall @0x24 yalnizca
        # RTL izinde var, sonraki her satir birebir esliyor).
        #
        # Desen -- ucu birden saglanmali ki gercek bir sapmayi yutmayalim:
        #   1) PC'ler ayrisiyor
        #   2) RTL adiminin yazmac/bellek etkisi YOK (tuzak commit etmez)
        #   3) bir SONRAKI RTL adimi spike'in su anki PC'siyle ayni
        #      (yani gercekten tuzak vektorune dallanilmis)
        if (
            s.pc != r.pc
            and not r.regs
            and r.mem_addr is None
            and j + 1 < len(rtl)
            and rtl[j + 1].pc == s.pc
        ):
            trap_skipped += 1
            j += 1
            continue

        if s.pc != r.pc:
            problems.append("PC       spike=0x%08x  rtl=0x%08x" % (s.pc, r.pc))

        # RVC: spike ham 16-bit, tracer acilmis 32-bit basar -> kiyaslanamaz
        is_rvc = (s.instr & 0x3) != 0x3
        if is_rvc:
            rvc_skipped += 1
        elif s.instr != r.instr:
            problems.append("BUYRUK   spike=0x%08x  rtl=0x%08x" % (s.instr, r.instr))

        if s.regs != r.regs:
            problems.append(
                "YAZMAC   spike=%s  rtl=%s" % (_fmt_regs(s.regs), _fmt_regs(r.regs))
            )

        if s.mem_addr != r.mem_addr:
            problems.append(
                "BELLEK   spike=%s  rtl=%s" % (_fmt_mem(s), _fmt_mem(r))
            )
        elif (
            s.mem_wdata is not None
            and r.mem_wdata is not None
            and s.mem_wdata != r.mem_wdata
        ):
            problems.append(
                "STORE    spike=0x%08x  rtl=0x%08x" % (s.mem_wdata, r.mem_wdata)
            )

        if problems:
            mismatches += 1
            if mismatches <= MAX_REPORTED:
                print("")
                print("[-] UYUSMAZLIK @ adim %d  (spike satir %d / rtl satir %d)"
                      % (i, s.lineno, r.lineno))
                for p in problems:
                    print("      " + p)
                print("      spike: %s" % s.line.strip())
                print("      rtl  : %s" % r.line.strip())

        i += 1
        j += 1

    if mismatches > MAX_REPORTED:
        print("")
        print("    ... ve %d uyusmazlik daha (ilk %d tanesi gosterildi)"
              % (mismatches - MAX_REPORTED, MAX_REPORTED))

    return mismatches, rvc_skipped, trap_skipped


def main():
    if len(sys.argv) != 3:
        print("Kullanim: python3 checker.py <spike_log> <rtl_log>")
        return 2

    spike_path, rtl_path = sys.argv[1], sys.argv[2]
    for p in (spike_path, rtl_path):
        if not os.path.exists(p):
            print("[!] HATA: dosya yok: %s" % p)
            return 2

    spike_all = parse_spike(spike_path)
    rtl = parse_rtl(rtl_path)

    if not spike_all:
        print("[!] HATA: spike izinde hic komut ayristirilamadi: %s" % spike_path)
        return 2
    if not rtl:
        print("[!] HATA: RTL izinde hic komut ayristirilamadi: %s" % rtl_path)
        return 2

    spike, skipped = strip_spike_bootrom(spike_all)
    if not spike:
        print("[!] HATA: spike izi bootrom disinda komut icermiyor")
        return 2

    print("spike : %-52s %d komut (%d bootrom adimi atlandi)"
          % (os.path.basename(spike_path), len(spike), skipped))
    print("rtl   : %-52s %d komut" % (os.path.basename(rtl_path), len(rtl)))

    rc = 0

    mismatches, rvc, traps = compare(spike, rtl)
    if mismatches:
        rc = 1

    # --- uzunluk esitligi ---
    # RTL izi, tuzaga dusen her buyruk icin spike'ta karsiligi olmayan bir
    # satir tasir (bkz. compare() TUZAKLANAN BUYRUK notu); beklenen fark
    # tam olarak o kadardir.
    if len(spike) != len(rtl) - traps:
        print("")
        print("[-] UZUNLUK FARKI: spike %d komut, rtl %d komut "
              "(%d tuzak satiri dusuldukten sonra fark %+d)"
              % (len(spike), len(rtl), traps, len(rtl) - traps - len(spike)))
        print("    Iki iz de tohost store satirinda kirpiliyor; esit olmalilar.")
        print("    Kisa kalan taraf erken durmus ya da kirpma noktasi bulunamamis.")
        rc = 1

    print("")
    if traps:
        print("    not: %d tuzaklanan buyruk RTL izinde var, spike izinde yok "
              "(spike tuzak eden buyruk icin commit satiri basmaz)" % traps)
    if rvc:
        print("    not: %d sikistirilmis buyrukta buyruk kelimesi karsilastirilmadi "
              "(spike 16-bit, tracer acilmis 32-bit basiyor)" % rvc)

    if rc == 0:
        print("[+] BASARILI: %d komut PC, buyruk, yazmac ve bellek alanlariyla "
              "birebir eslesti." % len(spike))
    else:
        print("[!] BASARISIZ: %d uyusmazlik." % mismatches)
    return rc


if __name__ == "__main__":
    sys.exit(main())
