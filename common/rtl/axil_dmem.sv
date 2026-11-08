// axil_dmem.sv
// Data memory: simple dual-port RAM (sdp_ram), one clock.
//
//   read port  -> AXI4-Lite slave AR/R (CPU loads)
//   write port -> AXI4-Lite slave AW/W/B (CPU stores)
//
// AXI4-Lite side:
//   - read latency 1: the RAM is read in the AR handshake cycle, RVALID/RDATA follow in
//     the next cycle from the RAM output register (block-RAM timing)
//   - one read per cycle: ARREADY = !RVALID || RREADY
//   - write: AW and W are accepted together, in the cycle both are valid and the B slot
//     is free (AWREADY = WREADY = AWVALID && WVALID && (!BVALID || BREADY)); bytes are
//     written per WSTRB, BVALID follows in the next cycle. Waiting for both VALIDs before
//     asserting READY is legal AXI slave behaviour.
//   - aligned access only: ADDR[LSB-1:0] are discarded, the word index is ADDR[AW+LSB-1:LSB]
//     (addresses beyond DEPTH wrap). Responses are always OKAY.
//   - read and write to the same word in the same cycle: the read returns the old data
//     (AXI defines no ordering between the read and write channels)
//
// Same structure as axil_imem; only the write port's source differs.
// Synchronous, active-low reset on the control flops only.
// DATA_W = 32 or 64 (bus and word width), ADDR_W = AXI address width; LSB = log2(DATA_W/8).
// INIT_FILE (optional): $readmemh image, one DATA_W-bit word per line.

module axil_dmem #(
  parameter int    DEPTH     = 512,    // DATA_W-bit words
  parameter int    DATA_W    = 32,
  parameter int    ADDR_W    = 32,
  parameter string INIT_FILE = ""
) (
  input  logic                clk,
  input  logic                rst_n,            // synchronous, active low

  input  logic [ADDR_W-1:0]   s_axi_awaddr,
  input  logic [2:0]          s_axi_awprot,
  input  logic                s_axi_awvalid,
  output logic                s_axi_awready,
  input  logic [DATA_W-1:0]   s_axi_wdata,
  input  logic [DATA_W/8-1:0] s_axi_wstrb,
  input  logic                s_axi_wvalid,
  output logic                s_axi_wready,
  output logic [1:0]          s_axi_bresp,
  output logic                s_axi_bvalid,
  input  logic                s_axi_bready,
  input  logic [ADDR_W-1:0]   s_axi_araddr,
  input  logic [2:0]          s_axi_arprot,
  input  logic                s_axi_arvalid,
  output logic                s_axi_arready,
  output logic [DATA_W-1:0]   s_axi_rdata,
  output logic [1:0]          s_axi_rresp,
  output logic                s_axi_rvalid,
  input  logic                s_axi_rready
);

  localparam int AW  = $clog2(DEPTH);
  localparam int LSB = $clog2(DATA_W / 8);

  logic ar_fire, wr_fire;

  sdp_ram #(.DEPTH(DEPTH), .DATA_W(DATA_W), .INIT_FILE(INIT_FILE)) u_ram (
    .clk       (clk),
    .wr_en_i   (wr_fire),
    .wr_be_i   (s_axi_wstrb),
    .wr_addr_i (s_axi_awaddr[AW+LSB-1:LSB]),
    .wr_data_i (s_axi_wdata),
    .rd_en_i   (ar_fire),
    .rd_addr_i (s_axi_araddr[AW+LSB-1:LSB]),
    .rd_data_o (s_axi_rdata)
  );

  // ---------------------------------------------------------------------------
  // AXI read
  // ---------------------------------------------------------------------------
  assign s_axi_arready = !s_axi_rvalid || s_axi_rready;
  assign ar_fire       = s_axi_arvalid && s_axi_arready;
  assign s_axi_rresp   = 2'b00;  // OKAY

  always_ff @(posedge clk) begin
    if (!rst_n)            s_axi_rvalid <= 1'b0;
    else if (ar_fire)      s_axi_rvalid <= 1'b1;
    else if (s_axi_rready) s_axi_rvalid <= 1'b0;
  end

  // ---------------------------------------------------------------------------
  // AXI write
  // ---------------------------------------------------------------------------
  assign s_axi_awready = s_axi_awvalid && s_axi_wvalid && (!s_axi_bvalid || s_axi_bready);
  assign s_axi_wready  = s_axi_awready;
  assign wr_fire       = s_axi_awready;   // AW and W handshake together
  assign s_axi_bresp   = 2'b00;           // OKAY

  always_ff @(posedge clk) begin
    if (!rst_n)            s_axi_bvalid <= 1'b0;
    else if (wr_fire)      s_axi_bvalid <= 1'b1;
    else if (s_axi_bready) s_axi_bvalid <= 1'b0;
  end

endmodule
