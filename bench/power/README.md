# CPU power from real switching activity

LibreLane's power figure is OpenSTA's vectorless estimate: a default activity on the inputs,
propagated through the logic. This flow replaces it with the activity of a real program: the
CPI test ([`../cpi_test`](../cpi_test)) runs on each sky130 layout's final netlist, every cell
pin's toggles are recorded, and OpenSTA computes the power from them with the layout's
parasitics. Only the CPU is measured: the testbench memory is outside the netlist.

| File | |
|---|---|
| `run_power.sh` | the flow, per core: image, gate-level xsim with a SAIF window, OpenSTA |
| `tb/tb_gl_nano.sv`, `tb/tb_gl_serv.sv` | the netlist (`fc32e1s_nano_asic_hard`, `serv_rf_top_latch`) at its signed-off clock, with the CPI test's memory timing |
| `tb/tb_gl_end.svh` | shared: reset, window from reset release to the program's end, `$stop` |
| `fix_saif.py` | rewrites xsim's escaped names and drops the scopes OpenSTA cannot map |

```bash
MSYS_NO_PATHCONV=1 NANO_FINAL=<nano run>/final SERV_FINAL=<serv run>/final STA=<opensta>/bin/sta ./run_power.sh
```

`NANO_FINAL` / `SERV_FINAL` are the LibreLane runs' `final/` folders (`nl/`, `spef/nom/`, `sdc/`);
`PDK_ROOT` defaults to `~/.ciel` (sky130A). Git Bash on Windows (xsim on PATH, OpenSTA and Python
in WSL) or Linux. Both cores take about 3 minutes; results go to `build/<core>/summary.txt`,
`power_saif.rpt`, `power_vectorless.rpt`.

Method:

1. **Gate level, zero delay.** The final netlist with the PDK's functional cell models
   (`-d FUNCTIONAL`). It runs the CPI test in exactly the RTL cycle count (nano 36 392, SERV
   183 729 kernel cycles), at the signed-off clock period (nano 27.78 ns, SERV 13.2 ns).
2. **SAIF window**: from reset release to the program's last write (start-up code, the six
   kernels, the result checks), every cell instance's pins (`log_saif -r`).
3. **OpenSTA**: `sky130_fd_sc_hd__tt_025C_1v80`, the layout's nominal-RC SPEF and SDC,
   `read_saif`; every pin annotated (`annotation.rpt`: 0 unannotated).

Zero-delay simulation counts no glitches, so the switching power of deep combinational logic is
a lower bound; clock, register and latch power, the larger part of both cores, are not affected.
