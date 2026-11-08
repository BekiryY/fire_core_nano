// fc32e1s_nano_asic_shift.sv
// Step shifter (N1, fc32_nano_plan.md A2): shifts a_i by step_i only (0, 1, 4, 31).
// The core repeats it until the whole distance is done, rd holding the partial result between the
// cycles (fc32e1s_nano_asic_pkg::shift_step / shift_left_after). The fill bit is a_i[31] for SRA,
// else 0.
// Instantiated by fc32e1s_nano_asic_core. (fc32e1s_tiny: a 32-bit barrel shifter with bit
// reversal for SLL.)

module fc32e1s_nano_asic_shift
  import fc32e1s_nano_asic_pkg::*;
(
  input  alu_op_e     op_i,         // ALU_SLL / ALU_SRL / ALU_SRA
  input  logic [31:0] a_i,
  input  shift_step_e step_i,
  output logic [31:0] result_o
);

  logic fill;

  assign fill = (op_i == ALU_SRA) & a_i[31];

  always_comb begin
    if (op_i == ALU_SLL) begin
      unique case (step_i)
        SH_1:    result_o = {a_i[30:0], 1'b0};
        SH_4:    result_o = {a_i[27:0], 4'b0};
        SH_31:   result_o = {a_i[0], 31'b0};
        default: result_o = a_i;
      endcase
    end else begin
      unique case (step_i)
        SH_1:    result_o = {fill, a_i[31:1]};
        SH_4:    result_o = {{4{fill}}, a_i[31:4]};
        SH_31:   result_o = {{31{fill}}, a_i[31]};
        default: result_o = a_i;
      endcase
    end
  end

endmodule
