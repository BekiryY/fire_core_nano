// fc32e1s_nano_fpga_fetch.sv
// Instruction fetch: AXI4-Lite read master + instruction register.
//
// The core holds req_i high (with a stable pc_i) until done_o. One transaction at a time:
//
//   address phase : ARVALID = req_i, held until ARREADY
//   data phase    : RREADY = 1, wait for RVALID; the word is latched into instr_o
//
// done_o is high in the cycle of the R handshake; instr_o holds the new instruction from
// the next cycle on. err_o qualifies done_o: RRESP was SLVERR or DECERR.
// Only the read channels are used; the core top ties the write channels off.

module fc32e1s_nano_fpga_fetch
  import fc32e1s_nano_fpga_pkg::*;
#(
  parameter int IADDR_W = 32           // fetch address width (the core's PC_W)
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_i,
  input  logic [IADDR_W-1:0] pc_i,
  output logic        done_o,
  output logic        err_o,
  output logic [31:0] instr_o,

  // AXI4-Lite read channels
  output logic [IADDR_W-1:0] m_axi_araddr,
  output logic [2:0]  m_axi_arprot,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [31:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready
);

  logic        addr_done_q;   // AR accepted, waiting for R
  logic [31:0] instr_q;

  assign m_axi_araddr  = pc_i;
  assign m_axi_arprot  = AXI_PROT_INSTR;
  assign m_axi_arvalid = req_i && !addr_done_q;
  assign m_axi_rready  = addr_done_q;

  assign done_o  = m_axi_rvalid && m_axi_rready;
  assign err_o   = done_o && m_axi_rresp[1];
  assign instr_o = instr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_done_q <= 1'b0;
    end else if (m_axi_arvalid && m_axi_arready) begin
      addr_done_q <= 1'b1;
    end else if (done_o) begin
      addr_done_q <= 1'b0;
    end
  end

  // Not reset: the core never decodes instr_q before the first fetch completes.
  always_ff @(posedge clk_i) begin
    if (done_o) instr_q <= m_axi_rdata;
  end

endmodule
