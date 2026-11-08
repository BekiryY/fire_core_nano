// tb_cpi_nano.sv -- the CPI test on a nano core alone: fc32e1s_nano_fpga_core or
// fc32e1s_nano_asic_core (same ports) with a 2 KiB memory model on both AXI4-Lite masters,
// loaded with image.hex (../build.sh), and the SIM register at data address 0x80C.
// Fetch: R one cycle after AR. Data: AW and W together, B / R one cycle after the request.
// Tops: tb_cpi_nano_fpga, tb_cpi_nano_asic (../run.sh).

`timescale 1ns/1ps

module cpi_nano_harness #(
  parameter bit ASIC = 1'b0
);

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [31:0] mem [0:511];
  initial $readmemh("image.hex", mem);

  logic [10:0] i_araddr;
  logic [31:0] i_rdata;
  logic        i_arvalid, i_arready, i_rvalid, i_rready;
  logic [11:0] d_awaddr, d_araddr;
  logic [31:0] d_wdata, d_rdata;
  logic [3:0]  d_wstrb;
  logic        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  logic        d_arvalid, d_arready, d_rvalid, d_rready;
  logic        halt, illegal, bus_err;

`define CPI_NANO_PORTS \
    .clk_i (clk), .rst_ni (rst_n), \
    .m_axi_i_awaddr (), .m_axi_i_awprot (), .m_axi_i_awvalid (), .m_axi_i_awready (1'b0), \
    .m_axi_i_wdata (), .m_axi_i_wstrb (), .m_axi_i_wvalid (), .m_axi_i_wready (1'b0), \
    .m_axi_i_bresp (2'b00), .m_axi_i_bvalid (1'b0), .m_axi_i_bready (), \
    .m_axi_i_araddr (i_araddr), .m_axi_i_arprot (), .m_axi_i_arvalid (i_arvalid), \
    .m_axi_i_arready (i_arready), .m_axi_i_rdata (i_rdata), .m_axi_i_rresp (2'b00), \
    .m_axi_i_rvalid (i_rvalid), .m_axi_i_rready (i_rready), \
    .m_axi_d_awaddr (d_awaddr), .m_axi_d_awprot (), .m_axi_d_awvalid (d_awvalid), \
    .m_axi_d_awready (d_awready), .m_axi_d_wdata (d_wdata), .m_axi_d_wstrb (d_wstrb), \
    .m_axi_d_wvalid (d_wvalid), .m_axi_d_wready (d_wready), .m_axi_d_bresp (2'b00), \
    .m_axi_d_bvalid (d_bvalid), .m_axi_d_bready (d_bready), .m_axi_d_araddr (d_araddr), \
    .m_axi_d_arprot (), .m_axi_d_arvalid (d_arvalid), .m_axi_d_arready (d_arready), \
    .m_axi_d_rdata (d_rdata), .m_axi_d_rresp (2'b00), .m_axi_d_rvalid (d_rvalid), \
    .m_axi_d_rready (d_rready), .halt_o (halt), .illegal_o (illegal), .bus_err_o (bus_err)

  if (ASIC) begin : g_asic
    fc32e1s_nano_asic_core u_core (`CPI_NANO_PORTS);
  end else begin : g_fpga
    fc32e1s_nano_fpga_core u_core (`CPI_NANO_PORTS);
  end

  // ---- fetch ----
  assign i_arready = !i_rvalid;
  always_ff @(posedge clk) begin
    if (!rst_n)                      i_rvalid <= 1'b0;
    else if (i_arvalid && i_arready) begin
      i_rvalid <= 1'b1;
      i_rdata  <= mem[i_araddr[10:2]];
    end else if (i_rready)           i_rvalid <= 1'b0;
  end

  // ---- data: RAM 0x000 - 0x7FF, SIM 0x80C ----
  logic wr, rd, sim_we;
  assign wr        = d_awvalid && d_wvalid && !d_bvalid;
  assign rd        = d_arvalid && !d_rvalid;
  assign d_awready = wr;
  assign d_wready  = wr;
  assign d_arready = rd;
  assign sim_we    = wr && d_awaddr[11] && d_awaddr[3:2] == 2'd3;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      d_bvalid <= 1'b0;
      d_rvalid <= 1'b0;
    end else begin
      if (wr) begin
        d_bvalid <= 1'b1;
        if (!d_awaddr[11])
          for (int b = 0; b < 4; b++)
            if (d_wstrb[b]) mem[d_awaddr[10:2]][8*b +: 8] <= d_wdata[8*b +: 8];
      end else if (d_bready) d_bvalid <= 1'b0;
      if (rd) begin
        d_rvalid <= 1'b1;
        d_rdata  <= d_araddr[11] ? '0 : mem[d_araddr[10:2]];
      end else if (d_rready) d_rvalid <= 1'b0;
    end
  end

  logic done, pass;
  cpi_monitor #(.NAME (ASIC ? "fc32e1s_nano_asic" : "fc32e1s_nano_fpga")) u_mon (
    .clk_i (clk), .sim_we_i (sim_we), .sim_data_i (d_wdata),
    .retire_i (i_rvalid && i_rready), .done_o (done), .pass_o (pass)
  );

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    fork
      wait (done);
      wait (halt || illegal || bus_err);
      begin repeat (500_000) @(posedge clk); $display("  TIMEOUT"); end
    join_any
    if (pass) $display("PASS");
    else      $display("FAIL (halt %0b, illegal %0b, bus_err %0b)", halt, illegal, bus_err);
    $finish;
  end

endmodule

module tb_cpi_nano_fpga; cpi_nano_harness #(.ASIC (1'b0)) u (); endmodule
module tb_cpi_nano_asic; cpi_nano_harness #(.ASIC (1'b1)) u (); endmodule
