#!/usr/bin/env python3
"""
coverage.py -- cekirdek testlerinin KOMUT KAPSAMI metrigi

NE ISE YARAR
------------
Sartname EK-3, dogrulama puanlamasinda "tanimlanan dogrulama kapsaminin
genisligi ve bu kapsam bunyesindeki dogrulama basarim orani" diyor.
"6 test kostu, hepsi gecti" bunu karsilamiyor; hangi BUYRUKLARIN gercekten
calistirildigini gostermek gerekiyor.

Bu betik RTL komut izlerini okuyup her buyrugun kac kez yurutuldugunu sayar
ve CV32E40P'nin destekledigi RV32IMC + Zicsr kumesine gore kapsam tablosu
uretir.

NEDEN RTL IZI, SPIKE IZI DEGIL
------------------------------
Iki iz checker.py ile birebir esit dogrulaniyor, yani ayni yurutmeyi
gosteriyorlar. RTL izi (cv32e40p_tracer) buyruk adini COZULMUS halde basiyor
("lw x30, 0(x29)"); spike commit logunda yalnizca 32-bit kelime var. Ayni
bilgiyi bedavaya almak icin RTL izi okunuyor.

KULLANIM
--------
    ./coverage.py                    # tum testler, konsol tablosu
    ./coverage.py --md kapsam.md     # ayrica markdown dosyasi yaz
    ./coverage.py --test stres_test  # tek test

CIKIS KODU
    0  basarili
    2  hic iz bulunamadi (once ./run_core_tests.sh kosun)
"""

import argparse
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
GROUPS = ("riscv_tests", "tiny_tests", "random_tests", "c_tests")

# ---------------------------------------------------------------------------
# CV32E40P'nin destekledigi kume (COREV_PULP=0, FPU=0 yapilandirmasi).
# Kaynak: cv32e40p_decoder.sv + cv32e40p_compressed_decoder.sv.
# Kapsam yuzdesi bu listeye gore hesaplanir; listede olmayip izde gorunen bir
# buyruk "LISTE DISI" olarak ayrica raporlanir (sessizce yutulmaz).
# ---------------------------------------------------------------------------
ISA = {
    "RV32I -- aritmetik/mantik (yazmac)": [
        "add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"],
    "RV32I -- aritmetik/mantik (anlik)": [
        "addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"],
    "RV32I -- ust anlik": ["lui", "auipc"],
    "RV32I -- dallanma": ["beq", "bne", "blt", "bge", "bltu", "bgeu"],
    "RV32I -- ziplama": ["jal", "jalr"],
    "RV32I -- yukleme": ["lb", "lh", "lw", "lbu", "lhu"],
    "RV32I -- saklama": ["sb", "sh", "sw"],
    "RV32I -- sistem": ["fence", "ecall", "ebreak", "mret", "dret", "wfi"],
    "Zicsr": ["csrrw", "csrrs", "csrrc", "csrrwi", "csrrsi", "csrrci"],
    "RV32M -- carpma": ["mul", "mulh", "mulhsu", "mulhu"],
    "RV32M -- bolme": ["div", "divu", "rem", "remu"],
    # RVC adlari, cv32e40p_tracer'in SOZCUK DAGARCIGINA gore yazilmistir:
    # tracer 16-bit bir buyrugu "c." oneki + GENISLETILMIS 32-bit karsiliginin
    # adiyla basar. Yani c.li / c.mv / c.nop ayri ayri gorunmez, ucu de
    # "c.addi" olarak; c.beqz "c.beq", c.bnez "c.bne" olarak cikar. Mimari
    # isim listesi kullanilsaydi kapsam kalici olarak eksik gorunurdu.
    "RV32C -- sikistirilmis": [
        "c.addi", "c.add", "c.sub", "c.and", "c.or", "c.xor", "c.andi",
        "c.slli", "c.srli", "c.srai", "c.lui", "c.lw", "c.sw",
        "c.beq", "c.bne", "c.jal", "c.jalr", "c.ebreak"],
}

# Cekirdek testinden ERISILEMEYEN buyruklar -- kapsam paydasindan dusulur,
# raporda gerekcesiyle ayrica listelenir. Sessizce "kapsanmadi" saymak
# yaniltici olurdu; bunlar test yazilmadigi icin degil, bu ortamda
# calistirilamadiklari icin yok.
OUT_OF_SCOPE = {
    "dret": "yalnizca hata ayiklama (debug) modunda gecerli; "
            "JTAG ile debug moduna girmeden yurutulemez",
    "wfi":  "bekleyen kesme yokken cekirdegi uyutur; "
            "cekirdek testinde simulasyonu sonsuza kadar askida birakir",
}

# ---------------------------------------------------------------------------
# --isa rv32i (fc32e1s_nano_fpga): plain RV32I core -- no M, C, Zicsr, no trap unit.
# ecall/ebreak exist in RV32I but fc32e1s_nano_fpga halts on them and Spike traps, so they
# cannot be compared in a trace; they are out of scope, not "uncovered".
# ---------------------------------------------------------------------------
ISA_RV32I = {k: v for k, v in ISA.items() if k.startswith("RV32I") and "sistem" not in k}
ISA_RV32I["RV32I -- sistem"] = ["fence", "ecall", "ebreak"]
OUT_OF_SCOPE_RV32I = {
    "ecall":  "fc32e1s_nano_fpga halts on ECALL (no trap unit); Spike traps -- not trace-comparable",
    "ebreak": "fc32e1s_nano_fpga halts on EBREAK (no trap unit); Spike traps -- not trace-comparable",
}

# Tracer bazi buyruklari sozde-buyruk (pseudo-instruction) adiyla basabilir;
# gercek buyruga geri esle ki kapsam sayimi dogru olsun.
ALIAS = {
    "nop": "addi", "mv": "addi", "not": "xori", "neg": "sub",
    "seqz": "sltiu", "snez": "sltu", "j": "jal", "jr": "jalr",
    "ret": "jalr", "beqz": "beq", "bnez": "bne", "bltz": "blt",
    "bgez": "bge", "li": "addi", "la": "addi",
    "csrr": "csrrs", "csrw": "csrrw", "csrs": "csrrs", "csrc": "csrrc",
    "csrwi": "csrrwi", "csrsi": "csrrsi", "csrci": "csrrci",
}

# Iz satiri: "<zaman> <cevrim> <pc> <buyruk> <mnemonic> ..."
# pc 8 hex hane; buyruk 4 (sikistirilmis) ya da 8 hex hane.
LINE_RE = re.compile(
    r"^\s*\d+\s+\d+\s+([0-9a-f]{8})\s+([0-9a-f]{4,8})\s+(\S+)")


def parse_trace(path):
    """Bir RTL izinden mnemonic sayaci uretir."""
    counts = Counter()
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LINE_RE.match(line)
            if not m:
                continue          # baslik satiri vb.
            mn = m.group(3).lower()
            counts[ALIAS.get(mn, mn)] += 1
    return counts


def collect(filter_name=None, root=HERE):
    per_test, total = {}, Counter()
    for grp in GROUPS:
        d = os.path.join(root, grp, "rtl_logs")
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.startswith("rtl_") or fn.endswith(".raw.log"):
                continue
            if not fn.endswith(".log"):
                continue
            name = fn[len("rtl_"):-len(".log")]
            if filter_name and name != filter_name:
                continue
            per_test[name] = parse_trace(os.path.join(d, fn))
            total.update(per_test[name])
    return per_test, total


def report(per_test, total):
    known = {i for lst in ISA.values() for i in lst}
    extra = sorted(set(total) - known)

    def in_scope(insts):
        return [i for i in insts if i not in OUT_OF_SCOPE]

    out = []
    add = out.append

    add("# Cekirdek Testleri -- Komut Kapsami")
    add("")
    add("Kaynak: `<build>/*/rtl_logs/rtl_*.log`")
    add("(Spike altin izleriyle birebir esit dogrulanmis izler.)")
    add("")

    add("## Test basina yurutulen buyruk sayisi")
    add("")
    add("| Test | Buyruk | Tekil buyruk turu |")
    add("|---|---:|---:|")
    for name in sorted(per_test):
        c = per_test[name]
        add("| `%s` | %d | %d |" % (name, sum(c.values()), len(c)))
    add("| **TOPLAM** | **%d** | **%d** |" % (sum(total.values()), len(total)))
    add("")

    add("## Kume bazinda kapsam")
    add("")
    add("| Kume | Kapsanan / Toplam | Oran |")
    add("|---|---:|---:|")
    gcov = gtot = 0
    for grp, insts in ISA.items():
        scoped = in_scope(insts)
        if not scoped:
            continue
        cov = sum(1 for i in scoped if total.get(i))
        gcov += cov
        gtot += len(scoped)
        add("| %s | %d / %d | %%%.0f "
            "|" % (grp, cov, len(scoped), 100.0 * cov / len(scoped)))
    add("| **TOPLAM** | **%d / %d** | **%%%.1f** |"
        % (gcov, gtot, 100.0 * gcov / gtot if gtot else 0.0))
    add("")

    add("## Yurutulen buyruklar (azalan sayida)")
    add("")
    add("| Buyruk | Adet |")
    add("|---|---:|")
    for mn, n in total.most_common():
        add("| `%s` | %d |" % (mn, n))
    add("")

    add("## Hic yurutulmeyen buyruklar")
    add("")
    any_miss = False
    for grp, insts in ISA.items():
        miss = [i for i in in_scope(insts) if not total.get(i)]
        if miss:
            any_miss = True
            add("- **%s**: %s" % (grp, ", ".join("`%s`" % i for i in miss)))
    if not any_miss:
        add("Yok -- kapsam dahilindeki butun buyruklar en az bir kez yurutuldu.")
    add("")

    add("## Kapsam disi (paydaya dahil degil)")
    add("")
    for i in sorted(OUT_OF_SCOPE):
        add("- `%s` -- %s" % (i, OUT_OF_SCOPE[i]))
    add("")

    if extra:
        add("## Liste disi (izde var, ISA listesinde yok)")
        add("")
        add("Ya tracer sozde-buyruk adi ya da ISA listesinin eksigi.")
        add("")
        for i in extra:
            add("- `%s` (%d kez)" % (i, total[i]))
        add("")

    return "\n".join(out), gcov, gtot


def main():
    ap = argparse.ArgumentParser(description="Cekirdek testleri komut kapsami")
    ap.add_argument("--md", metavar="DOSYA", help="markdown raporu buraya yaz")
    ap.add_argument("--test", metavar="AD", help="yalnizca bu test")
    ap.add_argument("--root", metavar="DIZIN", default=HERE,
                    help="<grup>/rtl_logs dizinlerini iceren kok (varsayilan: bu dizin)")
    ap.add_argument("--isa", choices=("rv32imc", "rv32i"), default="rv32imc",
                    help="kapsam paydasi: rv32imc (cv32e40p) ya da rv32i (fc32e1s_nano_fpga)")
    args = ap.parse_args()

    if args.isa == "rv32i":
        global ISA, OUT_OF_SCOPE
        ISA, OUT_OF_SCOPE = ISA_RV32I, OUT_OF_SCOPE_RV32I

    per_test, total = collect(args.test, args.root)
    if not per_test:
        sys.stderr.write(
            "[!] hic RTL izi bulunamadi -- once ./run_core_tests.sh kosun\n")
        return 2

    md, cov, tot = report(per_test, total)
    print(md)

    if args.md:
        path = args.md if os.path.isabs(args.md) else os.path.join(HERE, args.md)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(md + "\n")
        sys.stderr.write("\n[+] markdown yazildi: %s\n" % path)

    sys.stderr.write("[+] kapsam: %d/%d buyruk (%%%.1f)\n"
                     % (cov, tot, 100.0 * cov / tot if tot else 0.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
