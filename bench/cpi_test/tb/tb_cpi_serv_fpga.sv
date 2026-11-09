// tb_cpi_serv_fpga.sv -- the CPI test on the SERV FPGA board top (cores/serv/example/subsystem:
// serv_rf_top, the nano subsystem's block RAM, LED / counter peripheral), its RAM loaded with
// image_{0..3}.hex (../build.sh). Passes when the program found every result correct and the
// LEDs show 0x01.

`timescale 1ns/1ps

module tb_cpi_serv_fpga;

  logic       clk = 1'b0, rst_n = 1'b0;
  logic [7:0] led;

  always #5 clk = ~clk;

  serv_fpga_top #(.INIT_FILE ("image_")) dut (.clk_i (clk), .rst_ni (rst_n), .led_o (led));

  logic done, pass;
  cpi_monitor #(.NAME ("serv fpga top")) u_mon (
    .clk_i (clk), .sim_we_i (dut.wr && dut.d_adr[3:2] == 2'd3), .sim_data_i (dut.d_dat),
    .retire_i (dut.retire), .done_o (done), .pass_o (pass)
  );

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    fork
      wait (done);
      begin repeat (5_000_000) @(posedge clk); $display("  TIMEOUT"); end
    join_any
    repeat (2) @(posedge clk);
    if (pass && led == 8'h01) $display("PASS");
    else                      $display("FAIL (LED 0x%02h)", led);
    $finish;
  end

endmodule
