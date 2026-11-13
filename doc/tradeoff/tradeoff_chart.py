#!/usr/bin/env python3
"""tradeoff_chart.py -- the CPU trade-off chart: fc32e1s_nano vs SERV on six independent axes,
one hexagon for ASIC (sky130) and one for FPGA (Vivado, core alone).

    python3 tradeoff_chart.py            # -> tradeoff.svg (rsvg-convert -w 1600 tradeoff.svg -o tradeoff.png)

Every axis is higher = better and is normalized to the better core = 1, on a log scale over
one decade (the centre is 1/10 of the better core). Effective MIPS and MIPS per area are not
axes: they are products of the axes (Fmax x IPC, x area efficiency) and printed below.

PPA score: one number per core, the weighted geometric mean of its six axis values relative to the
better core, x 100 (the better core on every axis = 100). Effective IPC weighs 2 (a CPU is a
device that executes: the work done per cycle is the core's main figure), and so does code
density (SERV's lead: program memory often outweighs the core); every other axis 1. Fmax only
says whether the core runs at the system clock. A geometric mean, so each ratio
counts the same however large the unit, and no axis is clipped (the chart's centre is).
Sources of every number: ../../results/README.md.
"""
import math

REF_INSTR = 1101473        # cpi_bench, SERV's RV32E instruction count: the program's work
REF_TEXT = 4972            # cpi_bench .text, RV32E (16 registers)
CPI_TEST_INSTR = 3744      # CPI test, SERV's RV32E instruction count in the power window
BRAM18_LUT = 288           # RAMB18 = 18 Kb / 64 bits per LUTRAM LUT6

# axis: (label, unit line)
AXES = [
    ("Fmax", "MHz"),
    ("Effective IPC", "RV32E instr / cycle"),
    ("Area efficiency", "1 / area"),
    ("Energy efficiency", "RV32E instr / uJ"),
    ("Code density", "RV32E .text / own .text"),
    ("Wait-state tolerance", "CPI 0 waits / CPI 2 waits"),
]
WEIGHTS = [1, 2, 1, 1, 2, 1]   # score weight per axis: Effective IPC and code density x 2


def core(fmax, cycles0, cycles2, area, energy_per_instr_pj, text):
    return [fmax, REF_INSTR / cycles0, 1.0 / area, 1e6 / energy_per_instr_pj, REF_TEXT / text,
            cycles0 / cycles2]


# ASIC: sky130 layouts (nano v73, SERV s8), signed-off clocks, die area in um2; energy from the
# CPI test's gate-level activity (tt), per RV32E reference instruction
ASIC = {
    "fc32e1s_nano_asic": core(36.0, 10839619, 14581143, 23843, 0.821e6 / CPI_TEST_INSTR, 5460),
    "SERV": core(76.0, 61037635, 63614357, 42025, 5.338e6 / CPI_TEST_INSTR, 4972),
}
ASIC_AREA_TXT = {"fc32e1s_nano_asic": "23 843 um2", "SERV": "42 025 um2"}

# FPGA: Vivado 2025.2 out-of-context synthesis, xc7z020, AreaOptimized_high; area in LUT6
# equivalents (LUT + 288 x RAMB18); energy from the vectorless dynamic power at 100 MHz
# (default toggle rates: an estimate), per RV32E reference instruction
def fpga_energy_pj(p_dyn_uw_100mhz, cycles0):
    return p_dyn_uw_100mhz * 1e-6 / (100e6 * REF_INSTR / cycles0) * 1e12


FPGA = {
    "fc32e1s_nano_fpga": core(81.7, 4931283, 8672807, 529, fpga_energy_pj(6652.5, 4931283), 5460),
    "SERV": core(150.4, 61037635, 63614357, 123 + BRAM18_LUT, fpga_energy_pj(3859.6, 61037635), 4972),
}
FPGA_AREA_TXT = {"fc32e1s_nano_fpga": "529 LUT-eq", "SERV": "411 LUT-eq"}   # SERV: 123 LUT + 1 RAMB18

NANO_C, SERV_C = "#f0883e", "#58a6ff"
FG, DIM, GRID, BG = "#e6edf3", "#8b949e", "#30363d", "#0d1117"


def radius(v, best):
    return max(0.0, 1.0 + math.log10(v / best))   # best -> 1, best / 10 -> 0


def score(v, best):
    return 100.0 * math.exp(sum(w * math.log(v[i] / best[i]) for i, w in enumerate(WEIGHTS)) / sum(WEIGHTS))


def fmt(i, v):
    if i == 0:
        return f"{v:.1f} MHz"
    if i == 1:
        return f"{v:.3f}"
    if i == 2:
        return ""
    if i == 3:
        return f"{v:,.0f}".replace(",", " ")
    return f"{v:.2f}"


def hexagon(cx, cy, R, title, sub, data, area_txt):
    names = list(data)
    best = [max(data[n][i] for n in names) for i in range(6)]
    sc = [score(data[n], best) for n in names]
    out = [f'<text x="{cx}" y="{cy - R - 340}" font-size="46" font-weight="bold" text-anchor="middle">{title}</text>',
           f'<text x="{cx}" y="{cy - R - 292}" font-size="28" fill="{DIM}" text-anchor="middle">{sub}</text>',
           f'<text x="{cx}" y="{cy - R - 190}" font-size="30" fill="{DIM}" text-anchor="middle">PPA score '
           f'<tspan fill="{NANO_C}" font-size="64" font-weight="bold">{sc[0]:.0f}</tspan><tspan>   vs   </tspan>'
           f'<tspan fill="{SERV_C}" font-size="64" font-weight="bold">{sc[1]:.0f}</tspan></text>']
    ang = [math.radians(-90 + 60 * i) for i in range(6)]
    pt = lambda r, a: (cx + R * r * math.cos(a), cy + R * r * math.sin(a))
    for k, r in enumerate((0.25, 0.5, 0.75, 1.0)):   # rings at 1/10^(0.75 .. 0) of the best
        poly = " ".join("%.1f,%.1f" % pt(r, a) for a in ang)
        out.append(f'<polygon points="{poly}" fill="none" stroke="{GRID}" stroke-width="2"/>')
    for a in ang:
        x, y = pt(1, a)
        out.append(f'<line x1="{cx}" y1="{cy}" x2="{x:.1f}" y2="{y:.1f}" stroke="{GRID}" stroke-width="2"/>')
    for n, col in zip(names, (NANO_C, SERV_C)):
        poly = " ".join("%.1f,%.1f" % pt(radius(data[n][i], best[i]), ang[i]) for i in range(6))
        out.append(f'<polygon points="{poly}" fill="{col}" fill-opacity="0.22" stroke="{col}" stroke-width="5" stroke-linejoin="round"/>')
        for i in range(6):
            x, y = pt(radius(data[n][i], best[i]), ang[i])
            out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="8" fill="{col}"/>')
    for i, (lab, unit) in enumerate(AXES):
        x, y = pt(1.0, ang[i])
        dx, dy = (x - cx) / R, (y - cy) / R
        tx, ty = x + dx * 40, y + dy * 40
        anchor = "middle" if abs(dx) < 0.2 else ("start" if dx > 0 else "end")
        if dy < -0.9:
            ty -= 70
        elif dy > 0.9:
            ty += 30
        else:
            ty -= 20
        vals = []
        for n, col in zip(names, (NANO_C, SERV_C)):
            v = data[n][i]
            t = area_txt[n] if i == 2 else fmt(i, v)
            vals.append(f'<tspan fill="{col}">{t}</tspan>')
        out.append(f'<text x="{tx:.0f}" y="{ty:.0f}" font-size="32" font-weight="bold" text-anchor="{anchor}">{lab}</text>')
        out.append(f'<text x="{tx:.0f}" y="{ty + 36:.0f}" font-size="24" fill="{DIM}" text-anchor="{anchor}">{unit}</text>')
        out.append(f'<text x="{tx:.0f}" y="{ty + 70:.0f}" font-size="27" text-anchor="{anchor}">{vals[0]}<tspan fill="{DIM}">  vs  </tspan>{vals[1]}</text>')
    # derived headline numbers
    m = {n: data[n][0] * data[n][1] for n in names}
    a = {n: data[n][2] for n in names}
    unit = "per mm2" if "um2" in next(iter(area_txt.values())) else "per 1000 LUT-eq"
    scale = 1e6 if unit == "per mm2" else 1e3
    y0 = cy + R + 210
    for k, (n, col) in enumerate(zip(names, (NANO_C, SERV_C))):
        out.append(f'<text x="{cx}" y="{y0 + 44 * k}" font-size="30" text-anchor="middle"><tspan fill="{col}" font-weight="bold">{n}</tspan>'
                   f'<tspan fill="{FG}">  {m[n]:.2f} effective MIPS  ·  {m[n] * a[n] * scale:.1f} MIPS {unit}</tspan></text>')
    return out


def main():
    W, H, R = 3300, 1620, 340
    body = []
    body += hexagon(880, 950, R, "ASIC  ·  sky130", "final layouts, signed-off clocks, measured energy", ASIC, ASIC_AREA_TXT)
    body += hexagon(2420, 950, R, "FPGA  ·  Vivado 7-series, core alone", "AreaOptimized_high, estimated Fmax and energy", FPGA, FPGA_AREA_TXT)
    svg = [f'<svg xml:space="preserve" xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
           f'<rect width="{W}" height="{H}" fill="{BG}"/>',
           f'<g font-family="DejaVu Sans, Arial, sans-serif" fill="{FG}">',
           f'<text x="80" y="100" font-size="64" font-weight="bold">CPU trade-off chart</text>',
           f'<text x="80" y="155" font-size="32" fill="{DIM}">Higher = better on every axis. Each axis: the better core at the edge, log scale, centre = 1/10 of it.</text>',
           f'<text x="80" y="200" font-size="32" fill="{DIM}">PPA score: weighted geometric mean of the six axes vs the better core, x 100; Effective IPC and code density weigh 2, the others 1.</text>',
           f'<rect x="2400" y="68" width="34" height="34" fill="{NANO_C}"/><text x="2448" y="98" font-size="34">fc32e1s_nano</text>',
           f'<rect x="2760" y="68" width="34" height="34" fill="{SERV_C}"/><text x="2808" y="98" font-size="34">award-winning SERV</text>']
    svg += body + ["</g>", "</svg>"]
    with open("tradeoff.svg", "w") as f:
        f.write("\n".join(svg) + "\n")
    for t, d in (("ASIC", ASIC), ("FPGA", FPGA)):
        for n, v in d.items():
            best = [max(w[i] for w in d.values()) for i in range(6)]
            print(t, n, " ".join(f"{x:.4g}" for x in v), f"score {score(v, best):.1f}")


if __name__ == "__main__":
    main()
