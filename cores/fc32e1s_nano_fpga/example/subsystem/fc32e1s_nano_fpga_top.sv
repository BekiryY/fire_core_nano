// fc32e1s_nano_fpga_top.sv
// Board top for the fc32e1s_nano_fpga subsystem: reset synchronizer, the subsystem, and one
// small peripheral on its AXI4-Lite port. The GW2A project (../../appl/gw2a/subsystem) builds
// this; the testbench (tb/) simulates it.
//
// Peripheral registers (software: 0xFFFFF800 + offset):
//   0x800  LED     R/W  bits 7:0 drive led_o
//   0x804  CYCLE   R    clock cycles since reset
//   0x808  INSTRET R    instructions retired since reset
//   0x80C  SIM     W    simulation output: the testbench prints every word written here
// Decoded on address bits 3:2 only: the four registers repeat over 0x800 - 0xFFF.

module fc32e1s_nano_fpga_top #(
  parameter string INIT_FILE = "cpi_test_"   // RAM image prefix (sw/build.sh)
) (
  input  logic       clk_i,
  input  logic       rst_ni,          // asynchronous, active low (button)
  output logic [7:0] led_o,
  output logic       halt_o,
  output logic       err_o            // illegal instruction or bus error
);

  // ---------------------------------------------------------------------------
  // Reset: asserted asynchronously, released synchronously
  // ---------------------------------------------------------------------------
  logic [1:0] rst_q;
  logic       rst_n;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rst_q <= 2'b00;
    else         rst_q <= {rst_q[0], 1'b1};
  end
  assign rst_n = rst_q[1];

  // ---------------------------------------------------------------------------
  // Subsystem
  // ---------------------------------------------------------------------------
  logic [11:0] awaddr, araddr;
  logic [31:0] wdata, rdata;
  logic [3:0]  wstrb;
  logic        awvalid, awready, wvalid, wready, bvalid, bready;
  logic        arvalid, arready, rvalid, rready;
  logic        illegal, bus_err, retire;

  fc32e1s_nano_fpga_subsystem #(.INIT_FILE (INIT_FILE)) u_sub (
    .clk_i         (clk_i),
    .rst_ni        (rst_n),
    .m_axi_awaddr  (awaddr),
    .m_axi_awvalid (awvalid),
    .m_axi_awready (awready),
    .m_axi_wdata   (wdata),
    .m_axi_wstrb   (wstrb),
    .m_axi_wvalid  (wvalid),
    .m_axi_wready  (wready),
    .m_axi_bresp   (2'b00),
    .m_axi_bvalid  (bvalid),
    .m_axi_bready  (bready),
    .m_axi_araddr  (araddr),
    .m_axi_arvalid (arvalid),
    .m_axi_arready (arready),
    .m_axi_rdata   (rdata),
    .m_axi_rresp   (2'b00),
    .m_axi_rvalid  (rvalid),
    .m_axi_rready  (rready),
    .halt_o        (halt_o),
    .illegal_o     (illegal),
    .bus_err_o     (bus_err),
    .retire_o      (retire)
  );

  assign err_o = illegal || bus_err;

  // ---------------------------------------------------------------------------
  // Peripheral: takes AW and W together, answers in the next cycle
  // ---------------------------------------------------------------------------
  logic [31:0] cycle_q, instret_q;
  logic [7:0]  led_q;
  logic        wr, rd;

  assign wr      = awvalid && wvalid && !bvalid;
  assign rd      = arvalid && !rvalid;
  assign awready = wr;
  assign wready  = wr;
  assign arready = rd;

  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q   <= '0;
      instret_q <= '0;
      led_q     <= '0;
      bvalid    <= 1'b0;
      rvalid    <= 1'b0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (retire) instret_q <= instret_q + 1'b1;
      if (wr && awaddr[3:2] == 2'd0 && wstrb[0]) led_q <= wdata[7:0];
      if (wr)                bvalid <= 1'b1;
      else if (bready)       bvalid <= 1'b0;
      if (rd)                rvalid <= 1'b1;
      else if (rready)       rvalid <= 1'b0;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rd) begin
      case (araddr[3:2])
        2'd0:    rdata <= {24'd0, led_q};
        2'd1:    rdata <= cycle_q;
        2'd2:    rdata <= instret_q;
        default: rdata <= '0;
      endcase
    end
  end

  assign led_o = led_q;

endmodule
