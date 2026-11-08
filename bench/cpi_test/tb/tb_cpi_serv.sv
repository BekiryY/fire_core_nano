// tb_cpi_serv.sv -- the CPI test on SERV: serv_rf_top_latch with RV32E = 1 (the latch register
// file of the sky130 layout, cores/serv/appl/sky130_latch_rf) and a 2 KiB memory model on both
// Wishbone buses, loaded with image.hex (../build.sh). Ack and data one cycle after CYC. The SIM
// register is at 0xFFFFF80C (address bit 31 selects I/O). An instruction retires at its fetch
// acknowledge: SERV fetches the next instruction only when the current one is done.

`timescale 1ns/1ps

module tb_cpi_serv;

  logic clk = 1'b0, rst = 1'b1;
  always #5 clk = ~clk;

  logic [31:0] mem [0:511];
  initial $readmemh("image.hex", mem);

  logic [31:0] i_adr, i_rdt, d_adr, d_dat, d_rdt;
  logic [3:0]  d_sel;
  logic        i_cyc, i_ack = 1'b0, d_we, d_cyc, d_ack = 1'b0;

  serv_rf_top_latch #(.RESET_PC (32'h0), .RV32E (1'b1)) u_dut (
    .clk (clk), .i_rst (rst),
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

  cpi_monitor #(.NAME ("serv (RV32E)")) u_mon (
    .clk_i (clk), .sim_we_i (sim_we), .sim_data_i (d_dat),
    .retire_i (i_cyc && i_ack), .done_o (done), .pass_o (pass)
  );

  initial begin
    repeat (4) @(posedge clk);
    rst <= 1'b0;
    fork
      wait (done);
      begin repeat (5_000_000) @(posedge clk); $display("  TIMEOUT"); end
    join_any
    if (pass) $display("PASS");
    else      $display("FAIL");
    $finish;
  end

endmodule
