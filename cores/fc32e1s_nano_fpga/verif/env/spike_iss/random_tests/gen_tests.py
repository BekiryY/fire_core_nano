#!/usr/bin/env python3
# ============================================================
#  gen_tests.py -- seeded random instruction tests for fc32e1s_nano_fpga
#
#  Writes assembly/rand_<seed>.S (generated, gitignored). run_spike.sh runs
#  this before assembling the group, so the tests always match the script.
#
#  Every test uses only x0, x1, x2, x10..x12 (the core's register set):
#    - registers start from corner values (0, 1, -1, 0x8000_0000, 0x7fff_ffff,
#      0xffff_f800, 0x7ff, random), re-seeded with fresh corner values now and then
#    - x2 is the base pointer of a 256-byte initialised .data block in DMEM;
#      loads/stores are aligned and stay inside the block. x2 is only written
#      by short "move base" sequences that put it back on the block.
#    - x0 also appears as rd (writes must be discarded)
#    - branches and JAL/JALR only jump forward over 1..3 instructions, so the
#      program always terminates
#  The test is not self-checking; correctness comes from the lock-step trace
#  comparison with spike (every rd write and every store is compared).
#
#  USAGE   python3 gen_tests.py              seeds 1..N_TESTS
#          RAND_SEEDS="7 99" python3 gen_tests.py
#          RAND_LEN=<n>                      random instructions per test
# ============================================================
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assembly")

N_TESTS = 10
LEN = int(os.environ.get("RAND_LEN", "600"))   # IMEM is 4 KB; ~2 words per entry worst case
SEEDS = [int(s) for s in os.environ.get("RAND_SEEDS", "").split()] or list(range(1, N_TESTS + 1))

RD = ["x1", "x10", "x11", "x12"]         # freely writable
RS = ["x0", "x1", "x2", "x10", "x11", "x12"]
CORNER = [0, 1, -1, 0x80000000, 0x7FFFFFFF, 0xFFFFF800, 0x7FF, 0x800, 31, 32, 0xAAAAAAAA, 0x55555555]

R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
LOADS = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
DATA_BYTES = 256


def u32(v):
    return v & 0xFFFFFFFF


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.lines = []
        self.lbl = 0

    def rd(self):
        # x0 as destination now and then: the write must vanish
        return "x0" if self.r.random() < 0.04 else self.r.choice(RD)

    def rs(self):
        return self.r.choice(RS)

    def val(self):
        return self.r.choice(CORNER) if self.r.random() < 0.6 else self.r.getrandbits(32)

    def imm12(self):
        return self.r.choice([0, 1, -1, 2047, -2048, self.r.randint(-2048, 2047)])

    def emit(self, s):
        self.lines.append("        " + s)

    def label(self):
        self.lbl += 1
        return "L%d" % self.lbl

    # one straight-line (non-control) instruction
    def simple(self):
        k = self.r.random()
        if k < 0.30:
            self.emit("%-6s %s, %s, %s" % (self.r.choice(R_OPS), self.rd(), self.rs(), self.rs()))
        elif k < 0.50:
            self.emit("%-6s %s, %s, %d" % (self.r.choice(I_OPS), self.rd(), self.rs(), self.imm12()))
        elif k < 0.60:
            self.emit("%-6s %s, %s, %d" % (self.r.choice(SH_OPS), self.rd(), self.rs(),
                                           self.r.choice([0, 1, 31, self.r.randint(0, 31)])))
        elif k < 0.65:
            self.emit("%-6s %s, 0x%x" % (self.r.choice(["lui", "auipc"]), self.rd(), self.r.getrandbits(20)))
        elif k < 0.82:
            op, n = self.r.choice(LOADS)
            self.emit("%-6s %s, %d(x2)" % (op, self.rd(), self.r.randrange(0, DATA_BYTES, n)))
        elif k < 0.95:
            op, n = self.r.choice(STORES)
            self.emit("%-6s %s, %d(x2)" % (op, self.rs(), self.r.randrange(0, DATA_BYTES, n)))
        elif k < 0.98:
            self.emit("li     %s, 0x%x" % (self.r.choice(RD), u32(self.val())))
        else:
            # move the base pointer through other registers and back (x2 as rd/rs)
            t = self.r.choice(RD)
            off = self.r.randrange(4, 64, 4)
            self.emit("addi   x2, x2, %d" % off)
            self.emit("mv     %s, x2" % t)
            self.emit("addi   x2, %s, %d" % (t, -off))

    def control(self):
        k = self.r.random()
        skip = self.r.randint(1, 3)
        l = self.label()
        if k < 0.70:
            self.emit("%-6s %s, %s, %s" % (self.r.choice(BRANCHES), self.rs(), self.rs(), l))
        elif k < 0.85:
            self.emit("jal    %s, %s" % (self.rd(), l))
        else:
            # JALR: base from any writable register, link into any (incl. rd == base)
            base = self.r.choice(RD)
            off = self.r.choice([0, 4, -4, 8])
            self.emit("la     %s, %s%+d" % (base, l, -off))
            self.emit("jalr   %s, %d(%s)" % (self.r.choice(RD + ["x0"]), off, base))
        for _ in range(skip):
            self.simple()
        self.lines.append("%s:" % l)

    def build(self, seed):
        r = self.r
        out = ["// generated by gen_tests.py (seed %d) -- do not edit" % seed,
               '#include "test_env.h"',
               "        .section .text",
               "        .global _start",
               "_start:",
               "        TEST_INIT",
               "        la     x2, rdata"]
        for x in RD:
            self.emit("li     %s, 0x%x" % (x, u32(self.val())))
        for _ in range(LEN):
            if r.random() < 0.12:
                self.control()
            else:
                self.simple()
        # dump the final register state (stores are trace-compared)
        self.emit("la     x2, rdata")
        for i, x in enumerate(RD):
            self.emit("sw     %s, %d(x2)" % (x, 4 * i))
        out += self.lines
        out += ["pass:   TEST_PASS",
                "fail:   TEST_FAIL",
                "",
                "        .section .data",
                "        .balign 4",
                "rdata:"]
        for i in range(0, DATA_BYTES // 4, 4):
            out.append("        .word " + ", ".join("0x%08x" % u32(self.val()) for _ in range(4)))
        return "\n".join(out) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("rand_") and f.endswith(".S"):
            os.remove(os.path.join(OUT, f))
    for s in SEEDS:
        with open(os.path.join(OUT, "rand_%d.S" % s), "w", newline="\n") as f:
            f.write(Gen(s).build(s))


if __name__ == "__main__":
    main()
