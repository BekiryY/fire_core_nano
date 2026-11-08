// fc32e1s_nano_asic_regfile.sv
// General-purpose registers x1, x2, x10..x12 (5 words, fc32e1s_nano_asic_pkg::reg_phys); x0 and
// the registers that do not exist read as zero. The decoder makes any instruction naming a
// missing register illegal, so such an address never reaches the write port.
// 1 asynchronous read port (rev 3: the core reads rs2 first, then rs1), 1 write port with a
// byte enable per lane (the byte-serial ALU
// writes rd one byte per cycle; everything else writes all four lanes at once).
//
// Each byte of each word is 8 latches behind its own clock gate (fc32e1s_tiny:
// one gate per word). The write data is registered at the write edge (wdata_q); the clock
// gate of a selected byte, enabled during the write cycle, opens its latches for the high
// phase that follows, while wdata_q holds the value. The value can be read from the middle
// of the cycle after the write. A shift reads back the rd it wrote in the cycle before
// (fc32e1s_nano_asic_core, multi-step shifter): that read path is half a cycle on this variant.
//
// Registers are intentionally NOT reset: reading an unwritten register yields X in
// 4-state simulation, which exposes software/RTL bugs instead of hiding them behind 0.

module fc32e1s_nano_asic_regfile
  import fc32e1s_nano_asic_pkg::*;
(
  input  logic        clk_i,

  input  logic [4:0]  raddr_i,
  output logic [31:0] rdata_o,

  input  logic [3:0]  be_i,          // write byte enables (0: no write)
  input  logic [4:0]  rd_addr_i,
  input  logic [31:0] rd_data_i
);

  logic [2:0]  pr, pd;

  assign pr = reg_phys(raddr_i);
  assign pd = reg_phys(rd_addr_i);

  // Loaded every cycle (no enable): only the clock-gated bytes pick it up.
  logic [31:0] wdata_q;
  always_ff @(posedge clk_i) wdata_q <= rd_data_i;

  logic [31:0] regs [1:NUM_PREGS];

  for (genvar i = 1; i <= NUM_PREGS; i++) begin : g_word
    for (genvar b = 0; b < 4; b++) begin : g_byte
      logic       gclk;
      logic [7:0] q;

      fc32e1s_nano_asic_clkgate u_cg (
        .clk_i  (clk_i),
        .en_i   (be_i[b] && pd == 3'(i)),
        .gclk_o (gclk)
      );

      always_latch begin
        if (gclk) q <= wdata_q[8*b +: 8];
      end

      assign regs[i][8*b +: 8] = q;
    end
  end

  assign rdata_o = (pr == '0) ? 32'd0 : regs[pr];

endmodule
