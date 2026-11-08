// fc32e1s_nano_asic_decoder.sv
// Instruction -> control bundle. Purely combinational.
// Any unsupported encoding raises `illegal` with all side effects (rf_we, mem_we) cleared.
// Register subset: an instruction that reads or writes a register other than x0, x1, x2,
// x10..x12 is illegal (fc32e1s_nano_asic_pkg::reg_exists).

module fc32e1s_nano_asic_decoder
  import fc32e1s_nano_asic_pkg::*;
(
  input  logic [31:0] instr_i,
  output ctrl_t       ctrl_o
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];

  // funct3 -> ALU op for OP / OP-IMM. `alt` = funct7[5] (SUB / SRA).
  function automatic alu_op_e alu_op_from_funct(input logic [2:0] f3, input logic alt);
    unique case (f3)
      3'b000:  return alt ? ALU_SUB : ALU_ADD;
      3'b001:  return ALU_SLL;
      3'b010:  return ALU_SLT;
      3'b011:  return ALU_SLTU;
      3'b100:  return ALU_XOR;
      3'b101:  return alt ? ALU_SRA : ALU_SRL;
      3'b110:  return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  ctrl_t c;

  always_comb begin
    c         = '0;
    c.opa_sel = OPA_RS1;
    c.opb_sel = OPB_RS2;
    c.imm_sel = IMM_I;
    c.alu_op  = ALU_ADD;
    c.wb_sel  = WB_ALU;

    unique case (opcode)
      OPC_LUI: begin
        c.rf_we   = 1'b1;
        c.opa_sel = OPA_ZERO;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_U;
      end

      OPC_AUIPC: begin
        c.rf_we   = 1'b1;
        c.opa_sel = OPA_PC;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_U;
      end

      OPC_JAL: begin
        // target pc + imm in the core's PC_W-bit adder
        c.rf_we   = 1'b1;
        c.jal     = 1'b1;
        c.imm_sel = IMM_J;
        c.wb_sel  = WB_PC4;
      end

      OPC_JALR: begin
        c.rf_we   = 1'b1;
        c.jalr    = 1'b1;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_I;
        c.wb_sel  = WB_PC4;
        c.illegal = (funct3 != 3'b000);
      end

      OPC_BRANCH: begin
        // rs1 - rs2 in the byte ALU (SUB for BEQ / BNE: zero, SLT / SLTU for the others: lt),
        // target pc + imm in the core's PC_W-bit adder
        c.branch  = 1'b1;
        c.alu_op  = funct3[2] ? (funct3[1] ? ALU_SLTU : ALU_SLT) : ALU_SUB;
        c.imm_sel = IMM_B;
        c.illegal = (funct3 == 3'b010) || (funct3 == 3'b011);
      end

      OPC_LOAD: begin
        c.rf_we   = 1'b1;
        c.mem_re  = 1'b1;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_I;
        c.wb_sel  = WB_MEM;
        c.illegal = !(funct3 inside {MEM_B, MEM_H, MEM_W, MEM_BU, MEM_HU});
      end

      OPC_STORE: begin
        c.mem_we  = 1'b1;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_S;
        c.illegal = !(funct3 inside {MEM_B, MEM_H, MEM_W});
      end

      OPC_OP_IMM: begin
        c.rf_we   = 1'b1;
        c.opb_sel = OPB_IMM;
        c.imm_sel = IMM_I;
        c.alu_op  = alu_op_from_funct(funct3, (funct3 == 3'b101) && funct7[5]);
        // Shift-immediates constrain funct7: SLLI = 0000000, SRLI/SRAI = 0?00000
        if (funct3 == 3'b001) c.illegal = (funct7 != 7'b000_0000);
        if (funct3 == 3'b101) c.illegal = (funct7 != 7'b000_0000) && (funct7 != 7'b010_0000);
      end

      OPC_OP: begin
        c.rf_we   = 1'b1;
        c.alu_op  = alu_op_from_funct(funct3, funct7[5]);
        // funct7 = 0100000 is only valid for SUB and SRA
        c.illegal = !((funct7 == 7'b000_0000) ||
                      (funct7 == 7'b010_0000 && (funct3 == 3'b000 || funct3 == 3'b101)));
      end

      OPC_MISC_MEM: begin
        // FENCE: single-stage, in-order, no caches -> NOP. FENCE.I (Zifencei) not supported.
        c.illegal = (funct3 != 3'b000);
      end

      OPC_SYSTEM: begin
        // No CSRs / traps in this core: ECALL and EBREAK simply halt it.
        if (instr_i == INSTR_ECALL || instr_i == INSTR_EBREAK) c.halt    = 1'b1;
        else                                                   c.illegal = 1'b1;
      end

      default: c.illegal = 1'b1;
    endcase

    // Register subset: only x0, x1, x2, x10..x12 exist. Check just the register fields the
    // format actually uses -- in other formats those bits are immediate bits and may be anything.
    begin
      logic uses_rs1, uses_rs2;
      uses_rs1 = opcode inside {OPC_JALR, OPC_BRANCH, OPC_LOAD, OPC_STORE, OPC_OP_IMM, OPC_OP};
      uses_rs2 = opcode inside {OPC_BRANCH, OPC_STORE, OPC_OP};
      if ((uses_rs1 && !reg_exists(instr_i[19:15])) ||
          (uses_rs2 && !reg_exists(instr_i[24:20])) ||
          (c.rf_we  && !reg_exists(instr_i[11:7])))
        c.illegal = 1'b1;
    end

    if (c.illegal) begin
      c.rf_we  = 1'b0;
      c.mem_re = 1'b0;
      c.mem_we = 1'b0;
      c.branch = 1'b0;
      c.jal    = 1'b0;
      c.jalr   = 1'b0;
    end
  end

  assign ctrl_o = c;

endmodule
