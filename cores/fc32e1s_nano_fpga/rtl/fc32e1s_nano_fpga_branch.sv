// fc32e1s_nano_fpga_branch.sv
// Conditional branch comparator. funct3 selects the condition. Gowin builds both compares
// from carry-chain cells (cheaper than comparing in the ALU's adder: +78 logic measured).
//
// Shared hardware: one 33-bit subtraction gives LT (signed, funct3[1] = 0) and LTU
// (funct3[1] = 1) in bit 32; EQ is a separate equality. funct3[0] inverts the result
// (BNE, BGE, BGEU). funct3 = 01x is illegal (decoder) and never taken.

module fc32e1s_nano_fpga_branch
  import fc32e1s_nano_fpga_pkg::*;
(
  input  logic [2:0]  funct3_i,
  input  logic [31:0] rs1_i,
  input  logic [31:0] rs2_i,
  output logic        taken_o
);

  logic        sgn, lt, eq;
  logic [32:0] diff;

  assign sgn  = !funct3_i[1];
  assign diff = {sgn & rs1_i[31], rs1_i} - {sgn & rs2_i[31], rs2_i};
  assign lt   = diff[32];
  assign eq   = (rs1_i == rs2_i);

  assign taken_o = (funct3_i[2:1] == 2'b01) ? 1'b0 : ((funct3_i[2] ? lt : eq) ^ funct3_i[0]);

endmodule
