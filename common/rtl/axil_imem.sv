// axil_imem.sv
// Instruction memory: simple dual-port RAM (sdp_ram), one clock.
//
//   read port  -> AXI4-Lite slave AR/R (CPU instruction fetch)
//   write port -> native port wr_*_i (program loader; tie off while there is none)
//
// AXI4-Lite side:
//   - read latency 1: the RAM is read in the AR handshake cycle, RVALID/RDATA follow in
//     the next cycle from the RAM output register (block-RAM timing)
//   - one read per cycle: ARREADY = !RVALID || RREADY
//   - writes over AXI are not supported: AW+W are accepted together and answered with
//     SLVERR, memory unchanged (a mis-wired master gets an error instead of hanging)
//   - aligned access only: ADDR[LSB-1:0] are discarded, the word index is ADDR[AW+LSB-1:LSB]
//     (addresses beyond DEPTH wrap)
//
// Native write port: byte address (bits [LSB-1:0] discarded), byte enables, written on the
// rising edge. Same structure as axil_dmem; only the write port's source differs.
//
// Synchronous, active-low reset on the control flops only.
// DATA_W = 32 or 64 (bus and word width), ADDR_W = AXI address width; LSB = log2(DATA_W/8).
// INIT_FILE (optional): $readmemh image, one DATA_W-bit word per line.

module axil_imem #(
  parameter int    DEPTH     = 512,    // DATA_W-bit words
  parameter int    DATA_W    = 32,
  parameter int    ADDR_W    = 32,
  parameter string INIT_FILE = ""
) (
  input  logic                clk,
  input  logic                rst_n,            // synchronous, active low

  // ---- AXI4-Lite slave (CPU: read only) ----
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
  input  logic                s_axi_rready,

  // ---- native write port (loader) ----
  input  logic                wr_en_i,
  input  logic [DATA_W/8-1:0] wr_be_i,
  input  logic [ADDR_W-1:0]   wr_addr_i,        // byte address, [LSB-1:0] discarded
  input  logic [DATA_W-1:0]   wr_data_i
);

  localparam int AW  = $clog2(DEPTH);
  localparam int LSB = $clog2(DATA_W / 8);

  logic ar_fire;

  sdp_ram #(.DEPTH(DEPTH), .DATA_W(DATA_W), .INIT_FILE(INIT_FILE)) u_ram (
    .clk       (clk),
    .wr_en_i   (wr_en_i),
    .wr_be_i   (wr_be_i),
    .wr_addr_i (wr_addr_i[AW+LSB-1:LSB]),
    .wr_data_i (wr_data_i),
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
  // AXI write: not supported -> SLVERR
  // ---------------------------------------------------------------------------
  logic wr_fire;

  assign s_axi_awready = s_axi_awvalid && s_axi_wvalid && (!s_axi_bvalid || s_axi_bready);
  assign s_axi_wready  = s_axi_awready;
  assign wr_fire       = s_axi_awready;   // AW and W handshake together
  assign s_axi_bresp   = 2'b10;           // SLVERR

  always_ff @(posedge clk) begin
    if (!rst_n)            s_axi_bvalid <= 1'b0;
    else if (wr_fire)      s_axi_bvalid <= 1'b1;
    else if (s_axi_bready) s_axi_bvalid <= 1'b0;
  end

endmodule
