# Real activity factor and real power of a sky130 layout

How `bench/power/run_power.sh` replaces LibreLane's guessed activity with the activity of a real
program, and the traps found on the way. Applies to any LibreLane (OpenROAD) run on sky130 with
xsim and OpenSTA.

## Why

LibreLane's power number is OpenSTA's **vectorless** estimate: a default toggle rate on the inputs
and the registers, propagated through the logic as probabilities. It ignores what the design
actually does: registers that hold, clock gates that stay closed, a byte-serial datapath that
switches one lane at a time. For these two cores it was 2.5x (nano) and 2.1x (SERV) too high, and
not by the same factor, so even the ratio between the cores was off (SERV s8 / nano energy: 5.5x
vectorless vs 6.5x measured).

The real activity comes from simulating the **final netlist** (the one the parasitics belong
to) running a real program, recording how often every cell pin toggles, and handing those toggle
counts to OpenSTA instead of the default.

## Flow

```
program image ─► gate-level sim of final netlist ─► SAIF (toggles per pin) ─► fix_saif.py ─► OpenSTA
 (cpi_test)       (xsim, zero delay, PDK models)      (reset release..end)                    (liberty + SPEF + SDC)
```

1. **Program.** The CPI test (1 KiB, 6 kernels + start-up + checks), built per core with its own
   compiler. Short enough to simulate at gate level in seconds to minutes, long enough to cover
   all instruction classes. The memory is a testbench model outside the netlist, so only the
   CPU is measured.

2. **Gate-level simulation.**
   - Netlist: `final/nl/<top>.nl.v` (post-route, with clock tree, buffers, fill and tap cells).
   - Cell models: the PDK's `primitives.v` and `sky130_fd_sc_hd.v`, compiled with
     `-d FUNCTIONAL -d UNIT_DELAY=` (functional models, zero delay). Both files start with
     `` `default_nettype none ``, which breaks the implicit nets in the netlist: change it to
     `wire` on a copy.
   - Clock: the signed-off period (nano 27.78 ns, SERV 13.2 ns). With zero delay the period does
     not change the toggles; it only sets the time, hence the power (toggles / time).
   - Check: the gate-level run must give exactly the RTL cycle count and PASS (nano 36 392, SERV
     183 729 kernel cycles). Any difference means the netlist simulation is wrong, not the core.
   - `xelab --debug typical`, otherwise the nets are not visible to `log_saif`.

3. **SAIF window.** xsim Tcl:
   ```tcl
   run <reset time> ns                         ;# reset is held 4 cycles, window opens on release
   open_saif act.saif
   log_saif [get_objects -r /tb_gl/u_dut/*]    ;# -r: every cell instance and its pins
   run -all                                    ;# the testbench $stop's at the program's end
   close_saif
   ```
   The window is reset release to the program's last write: start-up code, kernels and checks,
   no idle cycles. Logging the top-level nets only (no `-r`) annotates just the ports (143 pins);
   OpenSTA then propagates the rest vectorless, which defeats the purpose.

4. **SAIF clean-up (`fix_saif.py`).** xsim's SAIF does not map onto OpenSTA's names as written:
   - **Escaped identifiers.** A netlist name `\u_core.addr_q[0] ` comes out as
     `\\u_core\\.addr_q\\[0\\]\\ `. OpenSTA's name for it is `u_core.addr_q\[0\]`: drop the
     leading backslashes and the escaped trailing space, unescape the dots, **keep** `\[ \]` (else
     OpenSTA reads them as a bus index). Getting the brackets wrong left exactly the clock gates
     and clock buffers unannotated (180 pins), the most power-relevant cells.
   - **Scopes below a cell.** The PDK models are built from UDPs (`dff0`, `dlatch0`,
     `mux_2to10`), and `-r` logs them as nested INSTANCEs. OpenSTA has no such instances and
     **segfaults** on them. Keep only depth `tb / dut / cell`.
   - **Cells without a liberty model** (`FILLER_*`, `TAP_*`, `PHY_*`): black boxes, no power;
     their scopes also crash `read_saif`. Drop them.

5. **OpenSTA.**
   ```tcl
   read_liberty sky130_fd_sc_hd__tt_025C_1v80.lib
   read_verilog <top>.nl.v ; link_design <top>
   read_sdc <top>.sdc ; read_spef <top>.nom.spef     ;# the layout's real wire load
   report_power -digits 4 > power_vectorless.rpt     ;# LibreLane-style, for comparison
   read_saif -scope tb_gl/u_dut act_fix.saif
   report_activity_annotation > annotation.rpt       ;# must say 0 unannotated
   report_power -digits 4 > power_saif.rpt
   ```
   Typical corner, nominal RC. `report_activity_annotation` is the acceptance test: every pin
   annotated from the SAIF (nano 6477, SERV 8156), none left to the default activity.

6. **Energy.** Energy = power x window time; per cycle = energy / cycles; per instruction =
   energy / retired instructions (counted by the testbench monitor in the same window). Energy
   for a program is clock-independent (power scales with the clock), so it is the fair number
   between cores at different clocks.

## Results (CPI test, tt 25 C 1.8 V)

Layouts: nano `fc32e1s_nano_asic` v73 (153.5 x 155.3 um), SERV s8 (205 x 205 um, 76.8 %, pins
N + S). Kernel cycles in the window as in RTL: SERV 183 729, nano 36 392.

| | nano (36 MHz) | SERV (76 MHz) |
|---|---|---|
| Power, real activity | 0.777 mW | 2.062 mW |
| sequential / combinational / clock | 0.208 / 0.370 / 0.199 mW | 1.111 / 0.195 / 0.756 mW |
| Power, vectorless | 1.949 mW | 4.395 mW |
| Window | 1057 us | 2589 us (196 149 cycles, 3744 instructions) |
| Energy | 0.821 uJ | 5.338 uJ (**6.5x** nano) |
| per cycle / per instruction | 21.6 / 150 pJ | 27.2 / 1426 pJ |

SERV history: the earlier s6 layout (238 x 238 um, 85 MHz) measured 2.279 mW, 5.259 uJ,
26.8 pJ/cycle. s8 takes 1.5 % more energy for the same toggles: clock tree +3.3 %, combinational
+1.8 %, sequential +0.3 % (a new floorplan and clock tree). Energy, not power, is the number to
compare: the power drops with the lower clock, the energy per program does not.

Run time: about 3 minutes for both (simulation 30 s nano, 1.5 min SERV; SAIF a few MB). The
CPU-only scope is what keeps it this short; a subsystem with SRAM models would cost much more.

## Limits

- **Zero delay, no glitches.** Combinational switching is a lower bound. Clock, flip-flop and
  latch power (most of both cores) are exact to the toggle. A timing-annotated simulation (SDF)
  would add the glitches at many times the run time.
- **Liberty internal power and leakage** are the PDK's tt characterization; the result is a
  simulation, not silicon.
- **Program-dependent.** The activity is the CPI test's; a program with a different instruction
  mix gives different power. Extrapolating to a longer program by energy per cycle (as done for
  `cpi_bench`) assumes a similar mix.
