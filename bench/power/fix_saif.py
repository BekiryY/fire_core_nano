#!/usr/bin/env python3
"""fix_saif.py <in.saif> <out.saif> -- makes an xsim SAIF of a flat gate-level netlist readable by
OpenSTA's read_saif (saif.tcl logs it recursively: one INSTANCE per standard cell, with the
cell's pins as NETs).

1. Escaped identifiers. xsim writes a Verilog escaped identifier, net or instance
   (\\u_core.addr_q[0] in the netlist), as `\\u_core\\.addr_q\\[0\\]\\ ` (the Verilog backslash
   and the terminating space kept, escaped). OpenSTA names that instance or net
   `u_core.addr_q\\[0\\]` (the SAIF divider is '/', the brackets stay escaped so they are not a
   bus index), so the SAIF gets `u_core.addr_q\\[0\\]`: leading backslashes, escaped trailing
   space and dot escapes dropped. Plain names and bus bits (`d_addr_o\\[2\\]`) are kept.
2. Scopes OpenSTA cannot map, which crash its read_saif: the primitives inside the PDK's cell
   models (dff0, dlatch0, mux_2to10 ... below a cell instance) and the cells without a liberty
   model (FILLER_*, TAP_*: black boxes, no power). Their INSTANCE blocks are dropped.
"""
import re
import sys

ESC = re.compile(r"(\(|\(INSTANCE +)\\{1,2}(\S+?)\\ ")
INST = re.compile(r"^\s*\(INSTANCE +(\S+)")
CELL_DEPTH = 3                        # tb_gl / u_dut / <cell>
NO_LIB = ("FILLER_", "TAP_", "PHY_")


def parens(line):
    s = re.sub(r"\\.", "", line)      # escaped characters are part of names
    return s.count("(") - s.count(")")


src, dst = sys.argv[1], sys.argv[2]
n_esc = n_drop = 0
stack = []                            # paren depth at which each open INSTANCE started
depth = 0
skip_to = None                        # paren depth that ends the block being dropped
with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8", newline="\n") as g:
    for line in f:
        line, k = ESC.subn(lambda m: m.group(1) + m.group(2).replace("\\.", ".") + " ", line)
        n_esc += k
        if skip_to is not None:
            depth += parens(line)
            if depth <= skip_to:
                skip_to = None
            continue
        m = INST.match(line)
        if m:
            while stack and stack[-1] >= depth:
                stack.pop()
            if len(stack) + 1 > CELL_DEPTH or m.group(1).startswith(NO_LIB):
                skip_to = depth
                depth += parens(line)
                n_drop += 1
                if depth <= skip_to:
                    skip_to = None
                continue
            stack.append(depth)
        depth += parens(line)
        g.write(line)
print(f"[i] {src}: {n_esc} escaped names rewritten, {n_drop} scopes dropped -> {dst}")
