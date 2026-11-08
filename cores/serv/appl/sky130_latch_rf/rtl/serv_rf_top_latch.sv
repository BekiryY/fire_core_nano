// serv_rf_top_latch.sv -- SERV's serv_rf_top with a latch register file for sky130
// (common/rtl/regfile/rf32x32_2r1w_latch.sv: 31 x 32 sky130_fd_sc_hd__dlxtp_1 latches, x0 = 0)
// instead of serv_rf_ram.v (behavioural RAM). The top of the standalone sky130 layout
// (appl/sky130_latch_rf). Upstream serv_rf_top configuration (W = 1, reset strategy MINI, no
// compressed / MDU / debug) except WITH_CSR = 0: the 32 registers are the whole register file
// (no CSRs, no traps, no timer interrupt). The MDU / extension port is not brought out.
//
// serv_rf_ram_if at width 32 reads rs1 and rs2 one after the other through one port and expects
// a one-cycle synchronous read (as serv_rf_ram): the latch file's first read port feeds rdata_q,
// loaded when ren. Its second read port is unused (removed by synthesis). A write presented in
// cycle N (wen / waddr / wdata) is in the latches during the high phase of N + 1, so a read in
// N + 1 sees it, as with serv_rf_ram's write at the end of N.
//
// RV32E = 1: SERV itself has no RV32E option; only the register file shrinks to x0..x15
// (address bit 4 ignored). x16..x31 are not trapped: the core runs RV32E code only.

`default_nettype none

module serv_rf_top_latch #(
  parameter logic [31:0] RESET_PC = 32'd0,
  parameter bit          RV32E    = 1'b0     // 1: 16-register file (x0..x15), RV32E code only
) (
  input  wire        clk,
  input  wire        i_rst,

  // Wishbone instruction bus
  output wire [31:0] o_ibus_adr,
  output wire        o_ibus_cyc,
  input  wire [31:0] i_ibus_rdt,
  input  wire        i_ibus_ack,

  // Wishbone data bus
  output wire [31:0] o_dbus_adr,
  output wire [31:0] o_dbus_dat,
  output wire [3:0]  o_dbus_sel,
  output wire        o_dbus_we,
  output wire        o_dbus_cyc,
  input  wire [31:0] i_dbus_rdt,
  input  wire        i_dbus_ack
);

  localparam int W        = 1;
  localparam int WITH_CSR = 0;
  localparam int RF_WIDTH = 32;

  wire          rf_wreq, rf_rreq, rf_ready;
  wire [4:0]    wreg0, wreg1, rreg0, rreg1;
  wire          wen0, wen1;
  wire [W-1:0]  wdata0, wdata1, rdata0, rdata1;

  wire [4:0]    waddr, raddr;
  wire [31:0]   wdata, rf_q;
  wire          wen, ren;
  reg  [31:0]   rdata_q;

  serv_rf_ram_if #(
    .width          (RF_WIDTH),
    .reset_strategy ("MINI"),
    .csr_regs       (0),
    .W              (W)
  ) rf_ram_if (
    .i_clk    (clk),
    .i_rst    (i_rst),
    .i_wreq   (rf_wreq),
    .i_rreq   (rf_rreq),
    .o_ready  (rf_ready),
    .i_wreg0  (wreg0),
    .i_wreg1  (wreg1),
    .i_wen0   (wen0),
    .i_wen1   (wen1),
    .i_wdata0 (wdata0),
    .i_wdata1 (wdata1),
    .i_rreg0  (rreg0),
    .i_rreg1  (rreg1),
    .o_rdata0 (rdata0),
    .o_rdata1 (rdata1),
    .o_waddr  (waddr),
    .o_wdata  (wdata),
    .o_wen    (wen),
    .o_raddr  (raddr),
    .o_ren    (ren),
    .i_rdata  (rdata_q)
  );

  rf32x32_2r1w_latch #(.NREG (RV32E ? 16 : 32)) u_rf (
    .clk_i    (clk),
    .raddr1_i (raddr),
    .rdata1_o (rf_q),
    .raddr2_i (5'd0),
    .rdata2_o (),
    .we_i     (wen),
    .waddr_i  (waddr),
    .wdata_i  (wdata)
  );

  always @(posedge clk) if (ren) rdata_q <= rf_q;

  serv_top #(
    .RESET_PC       (RESET_PC),
    .PRE_REGISTER   (1),
    .RESET_STRATEGY ("MINI"),
    .WITH_CSR       (WITH_CSR),
    .DEBUG          (1'b0),
    .MDU            (1'b0),
    .COMPRESSED     (1'b0),
    .ALIGN          (1'b0),
    .W              (W)
  ) cpu (
    .clk          (clk),
    .i_rst        (i_rst),
    .i_timer_irq  (1'b0),
    .o_rf_rreq    (rf_rreq),
    .o_rf_wreq    (rf_wreq),
    .i_rf_ready   (rf_ready),
    .o_wreg0      (wreg0),
    .o_wreg1      (wreg1),
    .o_wen0       (wen0),
    .o_wen1       (wen1),
    .o_wdata0     (wdata0),
    .o_wdata1     (wdata1),
    .o_rreg0      (rreg0),
    .o_rreg1      (rreg1),
    .i_rdata0     (rdata0),
    .i_rdata1     (rdata1),
    .o_ibus_adr   (o_ibus_adr),
    .o_ibus_cyc   (o_ibus_cyc),
    .i_ibus_rdt   (i_ibus_rdt),
    .i_ibus_ack   (i_ibus_ack),
    .o_dbus_adr   (o_dbus_adr),
    .o_dbus_dat   (o_dbus_dat),
    .o_dbus_sel   (o_dbus_sel),
    .o_dbus_we    (o_dbus_we),
    .o_dbus_cyc   (o_dbus_cyc),
    .i_dbus_rdt   (i_dbus_rdt),
    .i_dbus_ack   (i_dbus_ack),
    .o_ext_rs1    (),
    .o_ext_rs2    (),
    .o_ext_funct3 (),
    .i_ext_rd     (32'd0),
    .i_ext_ready  (1'b0),
    .o_mdu_valid  ()
  );

endmodule

`default_nettype wire
