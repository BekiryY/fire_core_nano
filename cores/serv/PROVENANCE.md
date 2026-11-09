# SERV -- provenance

- Upstream: https://github.com/olofk/serv (Olof Kindgren)
- Commit: f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8 (2026-08-25), copied 2026-11-01 from a clone
- License: `LICENSE` (ISC); `rtl/serv_compdec.v` is Apache-2.0 (its SPDX header)
- Kept: `rtl/`, `doc/`, `sw/`, `verif/` (RISCOF plugins), `README.md`, `LICENSE`.
  Not copied: `bench/`, `data/`, `servant/`, `servile/`, `serving/`, `zephyr/`, the FuseSoC
  `*.core` files, `NEWS`, `west.yml`. Not committed (`.gitignore`): `verif/bin/sail-riscv.tar.gz`
  (7.6 MB prebuilt Sail model, download it from upstream).
- Local change: `rtl/serv_synth_wrapper.v` defaults PRE_REGISTER = 0, RESET_STRATEGY = "NONE",
  WITH_CSR = 0 (upstream 1 / "MINI" / 1). Every other file is upstream as is.
- GW2A synthesis of `serv_rf_top` alone (default parameters): 288 LUT, 182 FF, 1 BSRAM, est.
  114.9 MHz; place & route not possible (the bare top has 195 pins, the GW2A-18 191).
- Benchmarks here: `bench/cpi_test` (`serv`, `serv_fpga`), `bench/power`; results in `results/`.
- Added for the FPGA comparison (not upstream): `example/subsystem/serv_fpga_top.sv` (SERV on the
  nano's GW2A board top: same 2 KiB block RAM, peripheral, reset) and
  `appl/gw2a/subsystem/serv_fpga_top.tcl` (same Gowin strategy as the nano): 388 logic, 281 FF,
  5 BSRAM, 139.8 MHz after place and route.
