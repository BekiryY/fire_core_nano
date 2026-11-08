// tb_fc32e1s_nano_fpga_top.sv -- runs a program on fc32e1s_nano_fpga_top (run_sim.sh).
// Prints the words the program writes to the SIM register, four per line (cpi_test: kernel,
// cycles, instructions, result, plus CPI), stops at the core's halt (ECALL) and reports
// PASS when the LEDs show 0x01 and no error flag is set.

`timescale 1ns/1ps

module tb_fc32e1s_nano_fpga_top;

  parameter string INIT_FILE = "image_";       // run_sim.sh copies the program image here
  localparam int   TIMEOUT   = 2_000_000;

  logic       clk = 1'b0, rst_n = 1'b0;
  logic [7:0] led;
  logic       halt, err;

  always #5 clk = ~clk;

  fc32e1s_nano_fpga_top #(.INIT_FILE (INIT_FILE)) dut (
    .clk_i (clk), .rst_ni (rst_n), .led_o (led), .halt_o (halt), .err_o (err)
  );

  // SIM register writes (0x80C)
  logic [31:0] w [4];
  int          n = 0;
  longint      cyc_sum = 0, ins_sum = 0;

  always @(posedge clk) begin
    if (dut.wr && dut.awaddr[3:2] == 2'd3) begin
      w[n % 4] = dut.wdata;
      n++;
      if (n % 4 == 0) begin
        $display("  kernel %0d  cycles %6d  instr %6d  CPI %5.2f  result 0x%08h",
                 w[0], w[1], w[2], real'(w[1]) / real'(w[2]), w[3]);
        cyc_sum += w[1];
        ins_sum += w[2];
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
    if (ins_sum > 0)
      $display("  all        cycles %6d  instr %6d  CPI %5.2f", cyc_sum, ins_sum,
               real'(cyc_sum) / real'(ins_sum));
    $display("  run: %0d cycles, %0d instructions, LED 0x%02h, halt %0b, error %0b",
             dut.cycle_q, dut.instret_q, led, halt, err);
    if (halt && !err && led == 8'h01) $display("PASS");
    else                              $display("FAIL");
    $finish;
  end

endmodule
