// fc32e1s_nano_asic_alu8.sv
// Byte-serial ALU (N2, fc32_nano_plan.md B1): one byte of each operand
// per cycle, low byte first; the core keeps the carry between the cycles and writes the result
// byte into rd's byte lane, so a 32-bit operation takes 4 cycles and needs no result register.
//
//   ADD / SUB          : 8-bit adder with carry in / out (SUB: b inverted, carry in 1 on byte 0)
//   SLT / SLTU         : a - b; on the top byte lt_o is the signed / unsigned "a < b"; the
//                        result byte is 0 (the core writes lt into byte 0 afterwards)
//   XOR / OR / AND     : bytewise
// Branches use the same subtraction: SUB for BEQ / BNE (zero_o of every byte), SLT / SLTU for
// BLT / BGE / BLTU / BGEU (lt_o). Loads, stores and JALR add rs1 + imm for as many bytes as
// the address has. Shifts are not here (fc32e1s_nano_asic_shift).
// (fc32e1s_tiny: one 32-bit ALU with a 33-bit adder and a barrel shifter, 1 cycle.)

module fc32e1s_nano_asic_alu8
  import fc32e1s_nano_asic_pkg::*;
(
  input  alu_op_e     op_i,
  input  logic [7:0]  a_i,
  input  logic [7:0]  b_i,
  input  logic        first_i,      // byte 0: carry in = SUB
  input  logic        carry_i,      // carry out of the byte before
  output logic [7:0]  result_o,
  output logic        carry_o,
  output logic        lt_o,         // valid on the top byte
  output logic        zero_o        // a + / - b of this byte is 0
);

  logic       sub, cin;
  logic [8:0] sum;

  assign sub = (op_i != ALU_ADD);
  assign cin = first_i ? sub : carry_i;
  assign sum = {1'b0, a_i} + {1'b0, sub ? ~b_i : b_i} + 9'(cin);

  assign carry_o = sum[8];
  assign zero_o  = (sum[7:0] == 8'd0);
  // signed: operand signs differ -> a's sign, else the difference's sign; unsigned: borrow
  assign lt_o    = (op_i == ALU_SLTU) ? ~sum[8] : ((a_i[7] ^ b_i[7]) ? a_i[7] : sum[7]);

  always_comb begin
    unique case (op_i)
      ALU_ADD, ALU_SUB: result_o = sum[7:0];
      ALU_XOR:          result_o = a_i ^ b_i;
      ALU_OR:           result_o = a_i | b_i;
      ALU_AND:          result_o = a_i & b_i;
      default:          result_o = 8'd0;   // SLT / SLTU (and the shift ops, not used here)
    endcase
  end

endmodule
