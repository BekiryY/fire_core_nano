// tb_console.sv -- runs a BSP program (sw/Makefile, TARGET=fpga) on fc32e1s_nano_fpga_top and
// prints what it writes to the console (SIM register 0x80C, one character per write). Stops at
// the core's halt (ECALL in _exit) and reports PASS when the LEDs show 0x01 (exit code 0).

`timescale 1ns/1ps

module tb_console;

  parameter string INIT_FILE = "image_";       // run_sim.sh copies the program image here
  localparam int   TIMEOUT   = 5_000_000;

  logic       clk = 1'b0, rst_n = 1'b0;
  logic [7:0] led;
  logic       halt, err;
  string      line = "";

  always #5 clk = ~clk;

  fc32e1s_nano_fpga_top #(.INIT_FILE (INIT_FILE)) dut (
    .clk_i (clk), .rst_ni (rst_n), .led_o (led), .halt_o (halt), .err_o (err)
  );

  always @(posedge clk) begin
    if (dut.wr && dut.awaddr[3:2] == 2'd3) begin
      if (dut.wdata[7:0] == 8'h0A) begin
        $display("%s", line);
        line = "";
      end else begin
        line = {line, string'(dut.wdata[7:0])};
      end
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    fork
      wait (halt || err);
      begin repeat (TIMEOUT) @(posedge clk); $display("TIMEOUT"); end
    join_any
    repeat (4) @(posedge clk);
    if (line.len() > 0) $display("%s", line);
    $display("  run: %0d cycles, %0d instructions, LED 0x%02h, halt %0b, error %0b",
             dut.cycle_q, dut.instret_q, led, halt, err);
    if (halt && !err && led == 8'h01) $display("PASS");
    else                              $display("FAIL");
    $finish;
  end

endmodule
