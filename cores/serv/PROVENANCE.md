# SERV -- provenance

- Upstream: https://github.com/olofk/serv (Olof Kindgren)
- Commit: f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8 (2026-08-25), copied 2026-11-01 from a clone
- License: `LICENSE` (ISC); `rtl/serv_compdec.v` is Apache-2.0 (its SPDX header)
- Kept: `rtl/`, `doc/`, `sw/`, `verif/` (RISCOF plugins), `README.md`, `LICENSE`.
  Not copied: `bench/`, `data/`, `servant/`, `servile/`, `serving/`, `zephyr/`, the FuseSoC
  `*.core` files, `NEWS`, `west.yml`. Not committed (`.gitignore`): `verif/bin/sail-riscv.tar.gz`
  (7.6 MB prebuilt Sail model, download it from upstream), the Gowin `impl/` outputs.
- Local change: `rtl/serv_synth_wrapper.v` defaults PRE_REGISTER = 0, RESET_STRATEGY = "NONE",
  WITH_CSR = 0 (upstream 1 / "MINI" / 1). Every other file is upstream as is.
- `gw2a/serv/serv.gprj`: Gowin project (paths point at the original clone, C:/repos/serv).
  Its synthesis of `serv_rf_top` (default parameters): 288 LUT, 182 FF, 1 BSRAM, est. 114.9 MHz;
  place & route not run (the bare top has 195 pins, the GW2A-18 191).
- Benchmark: `scripts/bench/cores/serv.toml` + `common/tb/bench/tb_bench_serv.sv` (serv_rf_top,
  default parameters, Wishbone memories `wb_mem_model.sv`); results in `docs/core_catalog.md`.
