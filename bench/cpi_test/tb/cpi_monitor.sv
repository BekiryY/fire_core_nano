// cpi_monitor.sv -- decodes the CPI test's SIM writes (../cpi_test.c) for every testbench:
// counts clock cycles and retired instructions between a kernel's start and end writes, prints
// one line per kernel and the total, and raises done at the KDONE write (pass: all kernels
// ran and the program found every result correct).

module cpi_monitor #(
  parameter string NAME = "core"
) (
  input  logic        clk_i,
  input  logic        sim_we_i,      // a write to the SIM register
  input  logic [31:0] sim_data_i,
  input  logic        retire_i,      // one instruction retired
  output logic        done_o,
  output logic        pass_o
);

  localparam logic [7:0] KSTART = 8'h5A;
  localparam logic [3:0] KDONE  = 4'hD;

  longint cyc = 0, ins = 0, c0, i0, cyc_sum = 0, ins_sum = 0;
  int     k, nk = 0;
  bit     in_kernel = 0;

  initial begin
    done_o = 1'b0;
    pass_o = 1'b0;
  end

  always @(posedge clk_i) begin
    cyc <= cyc + 1;
    if (retire_i) ins <= ins + 1;
    if (sim_we_i) begin
      if (in_kernel) begin
        $display("  %-18s kernel %0d  cycles %6d  instr %5d  CPI %6.2f  result 0x%08h",
                 NAME, k, cyc - c0, ins - i0, real'(cyc - c0) / real'(ins - i0), sim_data_i);
        cyc_sum  += cyc - c0;
        ins_sum  += ins - i0;
        nk++;
        in_kernel = 0;
      end else if (sim_data_i[31:24] == KSTART) begin
        k  = sim_data_i[7:0];
        c0 = cyc;
        i0 = ins;
        in_kernel = 1;
      end else if (sim_data_i[31:28] == KDONE) begin
        $display("  %-18s all       cycles %6d  instr %5d  CPI %6.2f  fail code 0x%02h", NAME,
                 cyc_sum, ins_sum, real'(cyc_sum) / real'(ins_sum), sim_data_i[7:0]);
        pass_o <= (sim_data_i[7:0] == 0) && nk == 6;
        done_o <= 1'b1;
      end
    end
  end

endmodule
