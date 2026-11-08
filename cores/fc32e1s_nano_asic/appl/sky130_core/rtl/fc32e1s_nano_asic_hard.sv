// fc32e1s_nano_asic_hard.sv -- block top for the standalone sky130 core layout (appl/sky130_core).
// fc32e1s_nano_asic_core with the pins that carry no information removed:
//   - instruction master write channels (AW / W / B): tied off in the core, read-only fetch
//   - AWPROT / ARPROT: constants (AXI_PROT_INSTR / AXI_PROT_DATA)
//   - RRESP[0] / BRESP[0]: the core only looks at bit 1 (SLVERR / DECERR); bit 0 is tied 0 here
//   - data AWADDR / ARADDR: the same word address in the LSU -> one d_addr bus, bits [1:0] are 0
// A subsystem that uses this block drives the dropped AXI fields with the same constants.

module fc32e1s_nano_asic_hard #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter int          PC_W     = 11,
  parameter int          DADDR_W  = 12
) (
  input  logic               clk_i,
  input  logic               rst_ni,

  // ---- instruction fetch: AR / R ----
  output logic [PC_W-1:0]    i_araddr_o,
  output logic               i_arvalid_o,
  input  logic               i_arready_i,
  input  logic [31:0]        i_rdata_i,
  input  logic               i_rerr_i,      // RRESP[1]
  input  logic               i_rvalid_i,
  output logic               i_rready_o,

  // ---- data: shared word address, AW / W / B / AR / R ----
  output logic [DADDR_W-1:2] d_addr_o,
  output logic               d_awvalid_o,
  input  logic               d_awready_i,
  output logic [31:0]        d_wdata_o,
  output logic [3:0]         d_wstrb_o,
  output logic               d_wvalid_o,
  input  logic               d_wready_i,
  input  logic               d_berr_i,      // BRESP[1]
  input  logic               d_bvalid_i,
  output logic               d_bready_o,
  output logic               d_arvalid_o,
  input  logic               d_arready_i,
  input  logic [31:0]        d_rdata_i,
  input  logic               d_rerr_i,      // RRESP[1]
  input  logic               d_rvalid_i,
  output logic               d_rready_o,

  // ---- status ----
  output logic               halt_o,
  output logic               illegal_o,
  output logic               bus_err_o
);

  logic [DADDR_W-1:0] d_araddr;

  fc32e1s_nano_asic_core #(
    .RESET_PC (RESET_PC),
    .PC_W     (PC_W),
    .DADDR_W  (DADDR_W)
  ) u_core (
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
    .m_axi_i_araddr  (i_araddr_o),
    .m_axi_i_arprot  (),
    .m_axi_i_arvalid (i_arvalid_o),
    .m_axi_i_arready (i_arready_i),
    .m_axi_i_rdata   (i_rdata_i),
    .m_axi_i_rresp   ({i_rerr_i, 1'b0}),
    .m_axi_i_rvalid  (i_rvalid_i),
    .m_axi_i_rready  (i_rready_o),

    .m_axi_d_awaddr  (),
    .m_axi_d_awprot  (),
    .m_axi_d_awvalid (d_awvalid_o),
    .m_axi_d_awready (d_awready_i),
    .m_axi_d_wdata   (d_wdata_o),
    .m_axi_d_wstrb   (d_wstrb_o),
    .m_axi_d_wvalid  (d_wvalid_o),
    .m_axi_d_wready  (d_wready_i),
    .m_axi_d_bresp   ({d_berr_i, 1'b0}),
    .m_axi_d_bvalid  (d_bvalid_i),
    .m_axi_d_bready  (d_bready_o),
    .m_axi_d_araddr  (d_araddr),
    .m_axi_d_arprot  (),
    .m_axi_d_arvalid (d_arvalid_o),
    .m_axi_d_arready (d_arready_i),
    .m_axi_d_rdata   (d_rdata_i),
    .m_axi_d_rresp   ({d_rerr_i, 1'b0}),
    .m_axi_d_rvalid  (d_rvalid_i),
    .m_axi_d_rready  (d_rready_o),

    .halt_o          (halt_o),
    .illegal_o       (illegal_o),
    .bus_err_o       (bus_err_o)
  );

  assign d_addr_o = d_araddr[DADDR_W-1:2];

endmodule
