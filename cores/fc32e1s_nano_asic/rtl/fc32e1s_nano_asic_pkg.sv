// fc32e1s_nano_asic_pkg.sv
// Shared types and constants for fc32e1s_nano_asic (FireCore 32-bit, RV32E subset, single-stage).

package fc32e1s_nano_asic_pkg;

  // ---------------------------------------------------------------------------
  // Register subset
  // ---------------------------------------------------------------------------
  // Only x0, x1 (ra), x2 (sp) and x10..x12 (a0..a2) exist (rev 2; rev 1 also had a3, a4):
  // return address, stack pointer and three argument / return registers, the smallest set C
  // still compiles to (user, 2026-10-30: 6 registers; 4 would leave one register for GCC).
  // Software is built with
  //   -ffixed-gp -ffixed-tp -ffixed-t0 -ffixed-t1 -ffixed-t2 -ffixed-s0 -ffixed-s1
  //   -ffixed-a3 -ffixed-a4 -ffixed-a5
  // and no function takes more than 3 integer arguments or a 64-bit pair beyond a0/a1 (GCC
  // passes a 4th argument word in a3 even with -ffixed-a3). An instruction that names any other register is illegal
  // (fc32e1s_nano_asic_decoder).
  localparam int NUM_PREGS = 5;  // physical registers, x0 not counted

  // Architectural register -> physical index 1..5; 0 for x0 and for registers that do not exist.
  function automatic logic [2:0] reg_phys(input logic [4:0] r);
    unique case (r)
      5'd1:    return 3'd1;  // ra
      5'd2:    return 3'd2;  // sp
      5'd10:   return 3'd3;  // a0
      5'd11:   return 3'd4;  // a1
      5'd12:   return 3'd5;  // a2
      default: return 3'd0;
    endcase
  endfunction

  function automatic logic reg_exists(input logic [4:0] r);
    return (r == 5'd0) || (reg_phys(r) != 3'd0);
  endfunction

  // ---------------------------------------------------------------------------
  // Base opcodes (instr[6:0])
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OPC_LOAD     = 7'b000_0011;
  localparam logic [6:0] OPC_MISC_MEM = 7'b000_1111;
  localparam logic [6:0] OPC_OP_IMM   = 7'b001_0011;
  localparam logic [6:0] OPC_AUIPC    = 7'b001_0111;
  localparam logic [6:0] OPC_STORE    = 7'b010_0011;
  localparam logic [6:0] OPC_OP       = 7'b011_0011;
  localparam logic [6:0] OPC_LUI      = 7'b011_0111;
  localparam logic [6:0] OPC_BRANCH   = 7'b110_0011;
  localparam logic [6:0] OPC_JALR     = 7'b110_0111;
  localparam logic [6:0] OPC_JAL      = 7'b110_1111;
  localparam logic [6:0] OPC_SYSTEM   = 7'b111_0011;

  localparam logic [31:0] INSTR_ECALL  = 32'h0000_0073;
  localparam logic [31:0] INSTR_EBREAK = 32'h0010_0073;

  // ---------------------------------------------------------------------------
  // Datapath control encodings
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND
  } alu_op_e;

  typedef enum logic [1:0] { OPA_RS1, OPA_PC, OPA_ZERO } opa_sel_e;
  typedef enum logic       { OPB_RS2, OPB_IMM }          opb_sel_e;
  typedef enum logic [2:0] { IMM_I, IMM_S, IMM_B, IMM_U, IMM_J } imm_sel_e;
  typedef enum logic [1:0] { WB_ALU, WB_MEM, WB_PC4 }    wb_sel_e;

  // Multi-step shifter (N1, fc32_nano_plan.md A2): the shift distance of one EXEC cycle.
  // A shift by n takes as many cycles as steps: 4 while 4 or more are left, then 1; 31 in one
  // step (sign / top-bit extraction is common). SH_0 is a shift by 0 (one cycle, rd = rs1).
  // Measured on GW2A (fc32e1s_nano_asic N2, 2026-10-27): steps 1/4/16/31 869 logic, 1/4/31 793 at
  // about +0.05 CPI (fc32ec1s_nano without the byte ALU uses 1/31). SH_16 stays in the enum.
  typedef enum logic [1:0] { SH_0, SH_1, SH_4, SH_31 } shift_step_e;

  function automatic shift_step_e shift_step(input logic [4:0] n);
    if (n == 5'd31)      return SH_31;
    else if (n >= 5'd4)  return SH_4;
    else if (n != 5'd0)  return SH_1;
    else                 return SH_0;
  endfunction

  // What is left after the step. Keep the case form with plain subtractions: a bit-field
  // version (clear bit 4, count down 2-bit fields) and a ternary synthesized larger on GW2A.
  function automatic logic [4:0] shift_left_after(input logic [4:0] n, input shift_step_e s);
    unique case (s)
      SH_1:     return n - 5'd1;
      SH_4:     return n - 5'd4;
      SH_31:    return n - 5'd31;
      default: return 5'd0;
    endcase
  endfunction

  // Load/store width = funct3 (instr[14:12])
  localparam logic [2:0] MEM_B  = 3'b000;
  localparam logic [2:0] MEM_H  = 3'b001;
  localparam logic [2:0] MEM_W  = 3'b010;
  localparam logic [2:0] MEM_BU = 3'b100;
  localparam logic [2:0] MEM_HU = 3'b101;

  // Branch condition = funct3 (instr[14:12])
  localparam logic [2:0] BR_EQ  = 3'b000;
  localparam logic [2:0] BR_NE  = 3'b001;
  localparam logic [2:0] BR_LT  = 3'b100;
  localparam logic [2:0] BR_GE  = 3'b101;
  localparam logic [2:0] BR_LTU = 3'b110;
  localparam logic [2:0] BR_GEU = 3'b111;

  // ---------------------------------------------------------------------------
  // AXI4-Lite
  // ---------------------------------------------------------------------------
  // xRESP: OKAY = 2'b00, SLVERR = 2'b10, DECERR = 2'b11 (EXOKAY not used in AXI4-Lite).
  // resp[1] set = error.
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

  // AxPROT = {instruction, non-secure, privileged}
  localparam logic [2:0] AXI_PROT_INSTR = 3'b100;
  localparam logic [2:0] AXI_PROT_DATA  = 3'b000;

  // ---------------------------------------------------------------------------
  // Decoder output bundle
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic     rf_we;    // write rd
    opa_sel_e opa_sel;
    opb_sel_e opb_sel;
    imm_sel_e imm_sel;
    alu_op_e  alu_op;
    wb_sel_e  wb_sel;
    logic     mem_re;   // load
    logic     mem_we;   // store
    logic     branch;   // conditional branch (compare in the ALU, target pc + imm)
    logic     jal;      // target pc + imm
    logic     jalr;     // target rs1 + imm (ALU, into the address register), bit 0 cleared
    logic     halt;     // ECALL / EBREAK: core stops
    logic     illegal;  // unsupported encoding: core stops
  } ctrl_t;

endpackage
