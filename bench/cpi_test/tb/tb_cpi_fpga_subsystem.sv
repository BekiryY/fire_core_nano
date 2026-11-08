// tb_cpi_fpga_subsystem.sv -- the CPI test on the fc32e1s_nano_fpga board top
// (cores/fc32e1s_nano_fpga/example/subsystem: subsystem, block RAM, LED / counter peripheral),
// its RAM loaded with image_{0..3}.hex (../build.sh). Passes when the program found every
// result correct and the LEDs show 0x01.

`timescale 1ns/1ps

module tb_cpi_fpga_subsystem;

  logic       clk = 1'b0, rst_n = 1'b0;
  logic [7:0] led;
  logic       halt, err;

  always #5 clk = ~clk;

  fc32e1s_nano_fpga_top #(.INIT_FILE ("image_")) dut (
    .clk_i (clk), .rst_ni (rst_n), .led_o (led), .halt_o (halt), .err_o (err)
  );

  logic done, pass;
  cpi_monitor #(.NAME ("fc32e1s_nano_fpga sub")) u_mon (
    .clk_i (clk), .sim_we_i (dut.wr && dut.awaddr[3:2] == 2'd3), .sim_data_i (dut.wdata),
    .retire_i (dut.retire), .done_o (done), .pass_o (pass)
  );

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    fork
      wait (done);
      wait (err);
      begin repeat (500_000) @(posedge clk); $display("  TIMEOUT"); end
    join_any
    repeat (2) @(posedge clk);
    if (pass && !err && led == 8'h01) $display("PASS");
    else                              $display("FAIL (LED 0x%02h, error %0b)", led, err);
    $finish;
  end

endmodule
