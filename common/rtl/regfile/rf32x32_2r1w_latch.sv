// rf32x32_2r1w_latch.sv
// RISC-V register file for sky130: 32 x 32 bits, 2 asynchronous read ports, 1 write port.
// x0 reads as zero and has no storage (31 words). Storage is one sky130_fd_sc_hd__dlxtp_1 latch
// per bit; each word has its own clock gate (sky130_fd_sc_hd__dlclkp_1). Built as an area
// alternative to an OpenRAM macro (128 B 1r1w: 340.7 x 200.5 um).
//
// Write: the write data is registered at the write edge (wdata_q); the clock gate of the
// selected word, enabled during the write cycle, opens its latches for the high phase that
// follows, while wdata_q holds the value (as the nano cores' latch register file). The new
// value can be read from the middle of the cycle after the write.
//
// Define RF_LATCH_SKY130 for sky130 synthesis (library latch and clock-gate cells); without it
// behavioural models are used (simulation, other targets).
//
// Registers are not reset: an unwritten register reads X in 4-state simulation.
//
// NREG = 16 gives the RV32E file (x0..x15, 15 words): the address keeps 5 bits, bit 4 is
// ignored (x16..x31 alias x0..x15; RV32E code does not use them).

module rf32x32_2r1w_latch #(
  parameter int NREG = 32               // 32 (RV32I) or 16 (RV32E)
) (
  input  logic        clk_i,

  input  logic [4:0]  raddr1_i,
  output logic [31:0] rdata1_o,
  input  logic [4:0]  raddr2_i,
  output logic [31:0] rdata2_o,

  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i
);

  // Loaded every cycle (no enable): only the clock-gated word picks it up.
  logic [31:0] wdata_q;
  always_ff @(posedge clk_i) wdata_q <= wdata_i;

  localparam int AW = $clog2(NREG);

  logic [31:0] regs [NREG];
  assign regs[0] = '0;

  for (genvar i = 1; i < NREG; i++) begin : g_word
    logic gclk;
    logic en;

    assign en = we_i && (waddr_i[AW-1:0] == AW'(i));

`ifdef RF_LATCH_SKY130
    sky130_fd_sc_hd__dlclkp_1 u_icg (.CLK (clk_i), .GATE (en), .GCLK (gclk));

    for (genvar b = 0; b < 32; b++) begin : g_bit
      sky130_fd_sc_hd__dlxtp_1 u_lat (.D (wdata_q[b]), .GATE (gclk), .Q (regs[i][b]));
    end
`else
    logic en_l;
    always_latch begin
      if (!clk_i) en_l <= en;
    end
    assign gclk = clk_i & en_l;

    logic [31:0] q;
    always_latch begin
      if (gclk) q <= wdata_q;
    end
    assign regs[i] = q;
`endif
  end

  assign rdata1_o = regs[raddr1_i[AW-1:0]];
  assign rdata2_o = regs[raddr2_i[AW-1:0]];

endmodule
