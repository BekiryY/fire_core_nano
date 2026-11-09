// tb_gl_nano.sv -- the CPI test (../cpi_test) on the fc32e1s_nano_asic sky130 layout's final
// netlist (fc32e1s_nano_asic_hard, zero-delay gate level), clocked at the layout's signed-off
// period. Same memory as ../cpi_test/tb/tb_cpi_nano.sv: a 2 KiB model loaded with image.hex,
// R one cycle after AR, B / R one cycle after the data request, SIM register at 0x80C. The model
// is outside the netlist, so the SAIF of u_dut (saif.tcl) holds the CPU's activity only.
// Ends with $stop at the program's KDONE write, which closes the SAIF window.

`timescale 1ns/1ps

module tb_gl;

  parameter real PERIOD = 27.7778;     // ns, 36 MHz

  logic clk = 1'b0, rst_n = 1'b0;
  always #(PERIOD / 2.0) clk = ~clk;

  logic [31:0] mem [0:511];
  initial $readmemh("image.hex", mem);

  logic [10:0] i_araddr;
  logic [11:2] d_addr;
  logic [31:0] i_rdata, d_wdata, d_rdata;
  logic [3:0]  d_wstrb;
  logic        i_arvalid, i_arready, i_rvalid, i_rready;
  logic        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  logic        d_arvalid, d_arready, d_rvalid, d_rready;
  logic        halt, illegal, bus_err;

  fc32e1s_nano_asic_hard u_dut (
    .clk_i (clk), .rst_ni (rst_n),
    .i_araddr_o (i_araddr), .i_arvalid_o (i_arvalid), .i_arready_i (i_arready),
    .i_rdata_i (i_rdata), .i_rerr_i (1'b0), .i_rvalid_i (i_rvalid), .i_rready_o (i_rready),
    .d_addr_o (d_addr), .d_awvalid_o (d_awvalid), .d_awready_i (d_awready),
    .d_wdata_o (d_wdata), .d_wstrb_o (d_wstrb), .d_wvalid_o (d_wvalid), .d_wready_i (d_wready),
    .d_berr_i (1'b0), .d_bvalid_i (d_bvalid), .d_bready_o (d_bready),
    .d_arvalid_o (d_arvalid), .d_arready_i (d_arready), .d_rdata_i (d_rdata),
    .d_rerr_i (1'b0), .d_rvalid_i (d_rvalid), .d_rready_o (d_rready),
    .halt_o (halt), .illegal_o (illegal), .bus_err_o (bus_err)
  );

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
  assign sim_we    = wr && d_addr[11] && d_addr[3:2] == 2'd3;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      d_bvalid <= 1'b0;
      d_rvalid <= 1'b0;
    end else begin
      if (wr) begin
        d_bvalid <= 1'b1;
        if (!d_addr[11])
          for (int b = 0; b < 4; b++)
            if (d_wstrb[b]) mem[d_addr[10:2]][8*b +: 8] <= d_wdata[8*b +: 8];
      end else if (d_bready) d_bvalid <= 1'b0;
      if (rd) begin
        d_rvalid <= 1'b1;
        d_rdata  <= d_addr[11] ? '0 : mem[d_addr[10:2]];
      end else if (d_rready) d_rvalid <= 1'b0;
    end
  end

  logic done, pass;
  cpi_monitor #(.NAME ("fc32e1s_nano_asic gl")) u_mon (
    .clk_i (clk), .sim_we_i (sim_we), .sim_data_i (d_wdata),
    .retire_i (i_rvalid && i_rready), .done_o (done), .pass_o (pass)
  );

  `include "tb_gl_end.svh"

endmodule
