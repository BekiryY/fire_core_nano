// fc32e1s_nano_sram2k_v2_cpu.sv
// The logic half of the hard macro sky130_sram_2kbyte_1rw1r_32x512_8_fc32e1s_nano_v2: the
// frozen fc32e1s_nano core, its fetch port and the boot ROM, placed and routed inside the free
// space of the OpenRAM 2 KB macro (see ../README.md).
//
// v2 against v1 (../sky130_sram_macro): the instruction side is inside the macro.
//   - The fetch port reads the SRAM's port 1 directly. The ram1_* ports are pins of this
//     block that sit on the SRAM's own port-1 pin stubs (scripts/gen_config.py); in the
//     merged macro they are wires, not pins.
//   - Data master: 12-bit addresses (the MCU's address map is 4 KiB, upper bits dropped;
//     software reaches 0x800 - 0xFFF as 0xFFFFF800 + offset, one instruction off x0), no
//     AxPROT (the core drives 3'b000), and ONE address bus m_axi_d_addr for AW and AR: the
//     core drives the same word address on both (fc32e1s_nano_asic_lsu: m_axi_awaddr =
//     m_axi_araddr = word_addr). The parent connects it to both AWADDR and ARADDR
//     (user decision 2026-10-11: 111 -> 99 CPU pins).
//   - The data master comes straight from the core (the macro of run t8): clk -> m_axi_d_addr
//     12.0 ns tt / 21.7 ns ss, WSTRB 12.5 / 24.1 ns, WDATA 14.2 ns ss. The PARENT puts a
//     register stage right at these pins (../mcu/fc32e1s_nano_sram2k_v2_dslice.sv), so its
//     interconnect decodes from flops; each load / store then takes one cycle more.
//     The same stage inside the macro (FC32E1S_NANO_V2_DM_REG, below; user decision
//     2026-10-11) does not route: the macro's right side has no room left for it. Runs t12 -
//     t18 all failed detailed routing at the SRAM's right row decoder (met2 wall x 570.38,
//     y 99 - 360, legal crossings only at its top end): global routing overflowed there by
//     ~140 because both ways round were full; t8 has the same overflow and converged by luck.
//
// Fetch address map (the nano core's fetch address is PC_W = 11 bits: the PC wraps at 2 KiB,
// so unlike the tiny core's 32-bit PC nothing can reach 0x800 and the fetch port has no SLVERR):
//   0x000 - 0x07F  boot ROM (fc32e1s_nano_sram2k_v2_bootrom, 32 words); reset PC 0x000
//   0x080 - 0x7FF  SRAM port 1 (0x000 - 0x07F of the SRAM: data only)
//
// Fetch timing: the core issues one read at a time and raises RREADY from the cycle after
// the AR handshake until R (fc32e1s_nano_asic_fetch), so the port needs no response buffer:
//   cycle 0  AR handshake; the SRAM latches ram1_addr at the end of the cycle; ROM index,
//            ROM hit and SLVERR decode are registered
//   cycle 1  RVALID; RDATA = the ROM word (from the registered index) or the SRAM's dout,
//            valid after the falling edge (SPICE tt: 3.11 ns); the core's instruction
//            register takes it at the end of the cycle
// The core's instruction register is the SRAM's capture register: one 2:1 mux between dout
// and it (same as v1's tiny_soc fetch path), half a clock cycle for dout + wire + mux.
// Fetch takes 2 cycles (v1 chip: 3, through axil_ram_rport's response buffer).

module fc32e1s_nano_sram2k_v2_cpu (
`ifdef USE_POWER_PINS
  inout  wire         vccd1,
  inout  wire         vssd1,
`endif
  input  logic        clk_i,
  input  logic        rst_ni,             // asynchronous, active low (the core's reset)

  // ---- AXI4-Lite master: data, 12-bit address shared by AW and AR ----
  output logic [11:0] m_axi_d_addr,
  output logic        m_axi_d_awvalid,
  input  logic        m_axi_d_awready,
  output logic [31:0] m_axi_d_wdata,
  output logic [3:0]  m_axi_d_wstrb,
  output logic        m_axi_d_wvalid,
  input  logic        m_axi_d_wready,
  input  logic [1:0]  m_axi_d_bresp,
  input  logic        m_axi_d_bvalid,
  output logic        m_axi_d_bready,
  output logic        m_axi_d_arvalid,
  input  logic        m_axi_d_arready,
  input  logic [31:0] m_axi_d_rdata,
  input  logic [1:0]  m_axi_d_rresp,
  input  logic        m_axi_d_rvalid,
  output logic        m_axi_d_rready,

  // ---- status (sticky until reset) ----
  output logic        halt_o,
  output logic        illegal_o,
  output logic        bus_err_o,

  // ---- SRAM port 1 (read only): wired to the SRAM's clk1 / csb1 / addr1 / dout1 ----
  output logic        ram1_clk,
  output logic        ram1_csb,           // active low
  output logic [8:0]  ram1_addr,          // word address
  input  logic [31:0] ram1_dout
);

  // ---------------------------------------------------------------------------
  // Core
  // ---------------------------------------------------------------------------
  logic [10:0] i_araddr;                        // PC_W
  logic [11:0] d_awaddr, d_araddr;              // DADDR_W
  logic [31:0] i_rdata;
  logic [1:0]  i_rresp;
  logic        i_arvalid, i_arready, i_rvalid, i_rready;
  logic [31:0] d_wdata;
  logic [3:0]  d_wstrb;
  logic        d_awvalid, d_awready, d_wvalid, d_wready, d_arvalid, d_arready;
  logic        d_bready, d_rready;

  fc32e1s_nano_asic_core u_core (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),

    .m_axi_i_awaddr  (),
    .m_axi_i_awprot  (),
    .m_axi_i_awvalid (),
    .m_axi_i_awready (1'b0),
    .m_axi_i_wdata   (),
    .m_axi_i_wstrb   (),
    .m_axi_i_wvalid  (),
    .m_axi_i_wready  (1'b0),
    .m_axi_i_bresp   (2'b00),
    .m_axi_i_bvalid  (1'b0),
    .m_axi_i_bready  (),
    .m_axi_i_araddr  (i_araddr),
    .m_axi_i_arprot  (),
    .m_axi_i_arvalid (i_arvalid),
    .m_axi_i_arready (i_arready),
    .m_axi_i_rdata   (i_rdata),
    .m_axi_i_rresp   (i_rresp),
    .m_axi_i_rvalid  (i_rvalid),
    .m_axi_i_rready  (i_rready),

    .m_axi_d_awaddr  (d_awaddr),
    .m_axi_d_awprot  (),
    .m_axi_d_awvalid (d_awvalid),
    .m_axi_d_awready (d_awready),
    .m_axi_d_wdata   (d_wdata),
    .m_axi_d_wstrb   (d_wstrb),
    .m_axi_d_wvalid  (d_wvalid),
    .m_axi_d_wready  (d_wready),
    .m_axi_d_bresp   (m_axi_d_bresp),
    .m_axi_d_bvalid  (m_axi_d_bvalid),
    .m_axi_d_bready  (d_bready),
    .m_axi_d_araddr  (d_araddr),
    .m_axi_d_arprot  (),
    .m_axi_d_arvalid (d_arvalid),
    .m_axi_d_arready (d_arready),
    .m_axi_d_rdata   (m_axi_d_rdata),
    .m_axi_d_rresp   (m_axi_d_rresp),
    .m_axi_d_rvalid  (m_axi_d_rvalid),
    .m_axi_d_rready  (d_rready),

    .halt_o          (halt_o),
    .illegal_o       (illegal_o),
    .bus_err_o       (bus_err_o)
  );

`ifndef FC32E1S_NANO_V2_DM_REG
  // ---------------------------------------------------------------------------
  // Data master straight from the core (run t8): the parent puts the register stage at the
  // pins (../mcu/fc32e1s_nano_sram2k_v2_dslice.sv). AW and AR carry the same word address
  // (fc32e1s_nano_asic_lsu); d_araddr is not used.
  // ---------------------------------------------------------------------------
  assign m_axi_d_addr    = d_awaddr;
  assign m_axi_d_awvalid = d_awvalid;
  assign d_awready       = m_axi_d_awready;
  assign m_axi_d_wdata   = d_wdata;
  assign m_axi_d_wstrb   = d_wstrb;
  assign m_axi_d_wvalid  = d_wvalid;
  assign d_wready        = m_axi_d_wready;
  assign m_axi_d_bready  = d_bready;
  assign m_axi_d_arvalid = d_arvalid;
  assign d_arready       = m_axi_d_arready;
  assign m_axi_d_rready  = d_rready;
`else
  // ---------------------------------------------------------------------------
  // FC32E1S_NANO_V2_DM_REG: one register stage on AW, W and AR inside the macro (does not
  // route, see the header; kept for the record). Address, WSTRB and VALIDs from flops, WDATA
  // the core's (stable until B: registering it too was worse, t12 - t14).
  // ---------------------------------------------------------------------------
  // A channel's register takes the core's request when it is empty or the bus takes its
  // current one in the same cycle; the core sees that as its handshake, the bus sees VALID
  // and the payload from the register one cycle later (WDATA: see below). AW and AR share the address register:
  // the core has one transaction open at a time (fc32e1s_nano_asic_lsu: the next starts after R or
  // B), so a load's AR is never pending while a store's AW is, and the core drives the same
  // word address on both (d_araddr is not used).
  // BREADY / RREADY are 1: the core sets its response state in the cycle its request enters a
  // register, so it waits for R / B before any can come, and it takes R / B in the cycle they
  // arrive (fc32e1s_nano_asic_lsu: done_o = resp_q && RVALID / BVALID); its own BREADY / RREADY
  // (resp_q && we) are therefore high whenever R / B are.
  logic        aw_q, w_q, ar_q;
  logic [11:0] addr_q;
  logic [3:0]  wstrb_q;

  assign d_awready = !aw_q || m_axi_d_awready;
  assign d_wready  = !w_q  || m_axi_d_wready;
  assign d_arready = !ar_q || m_axi_d_arready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_q <= 1'b0;
      w_q  <= 1'b0;
      ar_q <= 1'b0;
    end else begin
      if (d_awready) aw_q <= d_awvalid;
      if (d_wready)  w_q  <= d_wvalid;
      if (d_arready) ar_q <= d_arvalid;
    end
  end

  // Not reset: only on the bus while the channel's valid is set.
  always_ff @(posedge clk_i) begin
    if ((d_awvalid && d_awready) || (d_arvalid && d_arready)) addr_q <= d_awaddr;
    if (d_wvalid && d_wready) wstrb_q <= d_wstrb;
  end

  assign m_axi_d_addr    = addr_q;
  assign m_axi_d_awvalid = aw_q;
  // WDATA from the core: it keeps store_data (rs2) until done_o, i.e. after B, so it is
  // stable from the cycle the W register takes the request until the bus takes W.
  assign m_axi_d_wdata   = d_wdata;
  assign m_axi_d_wstrb   = wstrb_q;
  assign m_axi_d_wvalid  = w_q;
  assign m_axi_d_arvalid = ar_q;
  assign m_axi_d_bready  = 1'b1;
  assign m_axi_d_rready  = 1'b1;
`endif

  // ---------------------------------------------------------------------------
  // Fetch port: boot ROM over 0x000 - 0x07F, SRAM port 1 up to 0x7FF
  // ---------------------------------------------------------------------------
  logic       busy_q, rom_hit_q;
  logic [4:0] rom_idx_q;
  logic [31:0] rom_word;
  logic       ar_fire;

  assign i_arready = !busy_q;
  assign ar_fire   = i_arvalid && i_arready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                   busy_q <= 1'b0;
    else if (ar_fire)              busy_q <= 1'b1;
    else if (i_rvalid && i_rready) busy_q <= 1'b0;
  end

  // Not reset: only used while busy_q is set, which an AR handshake precedes.
  always_ff @(posedge clk_i) begin
    if (ar_fire) begin
      rom_hit_q <= (i_araddr[10:7] == '0);
      rom_idx_q <= i_araddr[6:2];
    end
  end

  fc32e1s_nano_sram2k_v2_bootrom u_bootrom (.addr_i (rom_idx_q), .data_o (rom_word));

  assign ram1_clk  = clk_i;
  assign ram1_csb  = !ar_fire;
  assign ram1_addr = i_araddr[10:2];

  assign i_rvalid = busy_q;
  assign i_rdata  = rom_hit_q ? rom_word : ram1_dout;
  assign i_rresp  = 2'b00;                      // OKAY

endmodule
