#!/usr/bin/env python3
"""mkimage.py <prog.bin> <out prefix> -- the 2 KiB memory image of a nano-core program.

Writes <prefix>.img (2048 bytes: the ASIC flash image / boot ROM copy), <prefix>.hex
(512 words, $readmemh) and <prefix>_0.hex .. <prefix>_3.hex (one byte per line per RAM byte
lane: the INIT_FILE of fc32e1s_nano_fpga_ram).
"""
import sys

SIZE = 2048
data = open(sys.argv[1], "rb").read()
if len(data) > SIZE:
    sys.exit(f"mkimage: image {len(data)} B > {SIZE} B")
data = data.ljust(SIZE, b"\0")
out = sys.argv[2]
open(f"{out}.img", "wb").write(data)
with open(f"{out}.hex", "w") as f:
    f.write("".join(f"{int.from_bytes(data[4 * w:4 * w + 4], 'little'):08x}\n" for w in range(SIZE // 4)))
for lane in range(4):
    with open(f"{out}_{lane}.hex", "w") as f:
        f.write("".join(f"{data[4 * w + lane]:02x}\n" for w in range(SIZE // 4)))
