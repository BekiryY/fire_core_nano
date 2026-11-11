// tb_gl_serv.sv -- the CPI test (../cpi_test) on the SERV sky130 layout's final netlist
// (serv_rf_top_latch, RV32E, zero-delay gate level), clocked at the layout's signed-off period.
// Same memory as ../cpi_test/tb/tb_cpi_serv.sv: a 2 KiB model on both Wishbone buses loaded with
// image.hex, ack and data one cycle after CYC, SIM register at 0xFFFFF80C. The model is outside
// the netlist, so the SAIF of u_dut (saif.tcl) holds the CPU's activity only.
// Ends with $stop at the program's KDONE write, which closes the SAIF window.

`timescale 1ns/1ps

module tb_gl;

  parameter real PERIOD = 13.2;        // ns, 76 MHz

  logic clk = 1'b0, rst_n = 1'b0;
  always #(PERIOD / 2.0) clk = ~clk;

  logic [31:0] mem [0:511];
  initial $readmemh("image.hex", mem);

  logic [31:0] i_adr, i_rdt, d_adr, d_dat, d_rdt;
  logic [3:0]  d_sel;
  logic        i_cyc, i_ack = 1'b0, d_we, d_cyc, d_ack = 1'b0;

  serv_rf_top_latch u_dut (
    .clk (clk), .i_rst (!rst_n),
    .o_ibus_adr (i_adr), .o_ibus_cyc (i_cyc), .i_ibus_rdt (i_rdt), .i_ibus_ack (i_ack),
    .o_dbus_adr (d_adr), .o_dbus_dat (d_dat), .o_dbus_sel (d_sel), .o_dbus_we (d_we),
    .o_dbus_cyc (d_cyc), .i_dbus_rdt (d_rdt), .i_dbus_ack (d_ack)
  );

  always_ff @(posedge clk) begin
    i_ack <= i_cyc && !i_ack;
    i_rdt <= mem[i_adr[10:2]];
    d_ack <= d_cyc && !d_ack;
    d_rdt <= d_adr[31] ? '0 : mem[d_adr[10:2]];
    if (d_cyc && !d_ack && d_we && !d_adr[31])
      for (int b = 0; b < 4; b++)
        if (d_sel[b]) mem[d_adr[10:2]][8*b +: 8] <= d_dat[8*b +: 8];
  end

  logic sim_we, done, pass;
  assign sim_we = d_cyc && !d_ack && d_we && d_adr[31] && d_adr[3:2] == 2'd3;

  cpi_monitor #(.NAME ("serv (RV32E) gl")) u_mon (
    .clk_i (clk), .sim_we_i (sim_we), .sim_data_i (d_dat),
    .retire_i (i_cyc && i_ack), .done_o (done), .pass_o (pass)
  );

  `include "tb_gl_end.svh"

endmodule
