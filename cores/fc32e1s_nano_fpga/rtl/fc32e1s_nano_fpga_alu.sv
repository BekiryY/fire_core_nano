// fc32e1s_nano_fpga_alu.sv
// 32-bit ALU. Also computes jump / branch targets and load / store
// addresses (ADD); branches compare in fc32e1s_nano_fpga_branch.
//
// Written as shared hardware (synthesis does not merge operators across case branches):
//   - one 33-bit adder/subtractor for ADD, SUB, SLT, SLTU: the operands are extended by one
//     bit (sign for SUB/SLT, zero for SLTU), so bit 32 of a - b is the "less than" result.
//   - the step shifter (fc32e1s_nano_fpga_shift): the core repeats a shift step until the distance is
//     done.

module fc32e1s_nano_fpga_alu
  import fc32e1s_nano_fpga_pkg::*;
(
  input  alu_op_e     op_i,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  input  shift_step_e step_i,       // shifts: distance of this cycle
  output logic [31:0] result_o
);

  // ---- adder / subtractor ----
  logic        sub, sgn;
  logic [32:0] ax, bx, sum;

  assign sub = (op_i != ALU_ADD);
  assign sgn = (op_i != ALU_SLTU);
  assign ax  = {sgn & a_i[31], a_i};
  assign bx  = {sgn & b_i[31], b_i};
  assign sum = ax + (sub ? ~bx : bx) + 33'(sub);

  // ---- step shifter ----
  logic [31:0] sres;

  fc32e1s_nano_fpga_shift u_shift (
    .op_i     (op_i),
    .a_i      (a_i),
    .step_i   (step_i),
    .result_o (sres)
  );

  // ---- result ----
  always_comb begin
    unique case (op_i)
      ALU_ADD, ALU_SUB:          result_o = sum[31:0];
      ALU_SLT, ALU_SLTU:         result_o = {31'd0, sum[32]};
      ALU_SLL, ALU_SRL, ALU_SRA: result_o = sres;
      ALU_XOR:                   result_o = a_i ^ b_i;
      ALU_OR:                    result_o = a_i | b_i;
      ALU_AND:                   result_o = a_i & b_i;
      default:                   result_o = '0;
    endcase
  end

endmodule
