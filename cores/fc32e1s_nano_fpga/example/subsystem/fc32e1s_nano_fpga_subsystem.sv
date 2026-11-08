// fc32e1s_nano_fpga_subsystem.sv
// fc32e1s_nano_fpga CPU subsystem: the core on a 2 KiB RAM that holds code, data and stack,
// plus one AXI4-Lite master for the user's peripherals. The program is the RAM's initial
// contents (INIT_FILE, block RAM initialization on the FPGA), so there is no boot ROM.
//
//   +----------------------------------------------------------------------------+
//   |  core m_axi_i --> fetch port --> RAM port 1                 0x000 - 0x7FF   |
//   |  core m_axi_d --+--> RAM port 0 (load / store)              0x000 - 0x7FF   |
//   |                 +------------------------------------------> m_axi_* 0x800 - 0xFFF
//   +----------------------------------------------------------------------------+
//
// Address map (12-bit data addresses; software reaches 0x800 - 0xFFF as 0xFFFFF800 + offset,
// one instruction off x0):
//   0x000 - 0x7FF  RAM: reset PC 0x000, code, data and stack (the fetch address is 11 bits)
//   0x800 - 0xFFF  m_axi_*: peripherals (address bit 11 set)
//
// Timing: fetch 2 cycles (AR, then R with the RAM word); RAM load / store 2 cycles (request,
// then R / B). The core has one fetch and at most one data transaction open at a time, and
// raises RREADY / BREADY from the cycle after its request until the response, so neither
// port needs a response buffer. The peripheral port is passed through: the core's AW and W
// may be taken in different cycles there.
//
// retire_o: one pulse per instruction fetched; the core is single-stage, so every fetch
// retires (instruction counter for the peripherals).

module fc32e1s_nano_fpga_subsystem #(
  parameter string INIT_FILE = ""      // RAM image prefix (fc32e1s_nano_fpga_ram)
) (
  input  logic        clk_i,
  input  logic        rst_ni,           // asynchronous, active low

  // ---- AXI4-Lite master: peripherals, 0x800 - 0xFFF ----
  output logic [11:0] m_axi_awaddr,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [31:0] m_axi_wdata,
  output logic [3:0]  m_axi_wstrb,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,
  output logic [11:0] m_axi_araddr,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [31:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  // ---- status (sticky until reset) ----
  output logic        halt_o,           // ECALL / EBREAK
  output logic        illegal_o,
  output logic        bus_err_o,
  output logic        retire_o
);

  // ---------------------------------------------------------------------------
  // Core
  // ---------------------------------------------------------------------------
  logic [10:0] i_araddr;
  logic [31:0] i_rdata;
  logic        i_arvalid, i_arready, i_rvalid, i_rready;

  logic [11:0] d_awaddr, d_araddr;
  logic [31:0] d_wdata, d_rdata;
  logic [3:0]  d_wstrb;
  logic [1:0]  d_bresp, d_rresp;
  logic        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  logic        d_arvalid, d_arready, d_rvalid, d_rready;

  fc32e1s_nano_fpga_core u_core (
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
    .m_axi_i_rresp   (2'b00),
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
    .m_axi_d_bresp   (d_bresp),
    .m_axi_d_bvalid  (d_bvalid),
    .m_axi_d_bready  (d_bready),
    .m_axi_d_araddr  (d_araddr),
    .m_axi_d_arprot  (),
    .m_axi_d_arvalid (d_arvalid),
    .m_axi_d_arready (d_arready),
    .m_axi_d_rdata   (d_rdata),
    .m_axi_d_rresp   (d_rresp),
    .m_axi_d_rvalid  (d_rvalid),
    .m_axi_d_rready  (d_rready),

    .halt_o          (halt_o),
    .illegal_o       (illegal_o),
    .bus_err_o       (bus_err_o)
  );

  // ---------------------------------------------------------------------------
  // RAM
  // ---------------------------------------------------------------------------
  logic        ram0_en, ram0_we;
  logic [8:0]  ram0_addr;
  logic [31:0] ram0_dout, ram1_dout;

  // ---------------------------------------------------------------------------
  // Fetch port: AR in cycle 0 (the RAM takes the address), R in cycle 1
  // ---------------------------------------------------------------------------
  logic i_busy_q;

  assign i_arready = !i_busy_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                   i_busy_q <= 1'b0;
    else if (i_arvalid && i_arready) i_busy_q <= 1'b1;
    else if (i_rvalid && i_rready)   i_busy_q <= 1'b0;
  end

  assign i_rvalid = i_busy_q;
  assign i_rdata  = ram1_dout;
  assign retire_o = i_rvalid && i_rready;

  // ---------------------------------------------------------------------------
  // Data side: address bit 11 selects RAM (0) or the peripheral port (1)
  // ---------------------------------------------------------------------------
  logic wr_ram, rd_ram;                 // a RAM request this cycle
  logic ram_b_q, ram_r_q;               // RAM response pending

  // RAM: AW and W are taken together; the core drives both in the same cycle.
  assign wr_ram = d_awvalid && d_wvalid && !d_awaddr[11] && !ram_b_q;
  assign rd_ram = d_arvalid && !d_araddr[11] && !ram_r_q;

  assign ram0_en   = wr_ram || rd_ram;
  assign ram0_we   = wr_ram;
  assign ram0_addr = wr_ram ? d_awaddr[10:2] : d_araddr[10:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ram_b_q <= 1'b0;
      ram_r_q <= 1'b0;
    end else begin
      if (wr_ram)                         ram_b_q <= 1'b1;
      else if (ram_b_q && d_bready)       ram_b_q <= 1'b0;
      if (rd_ram)                         ram_r_q <= 1'b1;
      else if (ram_r_q && d_rready)       ram_r_q <= 1'b0;
    end
  end

  // Peripheral port: pass-through when address bit 11 is set.
  assign m_axi_awaddr  = d_awaddr;
  assign m_axi_awvalid = d_awvalid && d_awaddr[11];
  assign m_axi_wdata   = d_wdata;
  assign m_axi_wstrb   = d_wstrb;
  assign m_axi_wvalid  = d_wvalid && d_awaddr[11];
  assign m_axi_bready  = d_bready && !ram_b_q;
  assign m_axi_araddr  = d_araddr;
  assign m_axi_arvalid = d_arvalid && d_araddr[11];
  assign m_axi_rready  = d_rready && !ram_r_q;

  assign d_awready = d_awaddr[11] ? m_axi_awready : wr_ram;
  assign d_wready  = d_awaddr[11] ? m_axi_wready  : wr_ram;
  assign d_arready = d_araddr[11] ? m_axi_arready : rd_ram;

  assign d_bvalid = ram_b_q || m_axi_bvalid;
  assign d_bresp  = ram_b_q ? 2'b00 : m_axi_bresp;
  assign d_rvalid = ram_r_q || m_axi_rvalid;
  assign d_rdata  = ram_r_q ? ram0_dout : m_axi_rdata;
  assign d_rresp  = ram_r_q ? 2'b00 : m_axi_rresp;

  fc32e1s_nano_fpga_ram #(.INIT_FILE (INIT_FILE)) u_ram (
    .clk_i    (clk_i),
    .en0_i    (ram0_en),
    .we0_i    (ram0_we),
    .wmask0_i (d_wstrb),
    .addr0_i  (ram0_addr),
    .din0_i   (d_wdata),
    .dout0_o  (ram0_dout),
    .en1_i    (i_arvalid && i_arready),
    .addr1_i  (i_araddr[10:2]),
    .dout1_o  (ram1_dout)
  );

endmodule
