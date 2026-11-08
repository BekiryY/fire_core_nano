// fc32e1s_nano_asic_core.sv
// FireCore 32-bit RV32E-subset single-stage core — top level, AXI4-Lite native.
// fc32e1s with a 6-register file: only x0, x1 (ra), x2 (sp), x10..x12 (a0..a2) exist; any
// instruction that names another register is illegal (fc32e1s_nano_asic_pkg::reg_exists,
// fc32e1s_nano_asic_decoder).
// ASIC build (split from fc32e1s_nano rev 2, PLATFORM = PLAT_ASIC): byte-serial ALU, register file
// in latches behind clock gates (fc32e1s_nano_asic_regfile).
//
// The core contains NO memory. It has two AXI4-Lite masters:
//   m_axi_i_* : instruction fetch (read channels only; write channels tied off)
//   m_axi_d_* : loads and stores
// Every handshake may stall for any number of cycles.
//
// Single-stage: one instruction at a time, no overlap.
//
//   S_RESET --> S_FETCH --(R handshake)--> S_EXEC --(commit)--> S_FETCH
//                  |                          |
//                  +--(RRESP error)--+        +--(halt / illegal / bus error)--+
//                                    v                                         v
//                                  S_HALT  <-----------------------------------+
//
//   S_FETCH : fc32e1s_nano_asic_fetch reads the instruction at PC into the instruction register.
//   S_EXEC  : decode + execute from the instruction register, one or more cycles:
//             ALU ops, LUI, AUIPC     4 (byte-serial ALU, rd one byte lane per cycle;
//                                       SLT / SLTU 5; register-register ops 8 / 9)
//             branches                8 (compare in the byte ALU; target pc + imm)
//             loads / stores          2 address bytes (DADDR_W = 12) + bus
//             JALR                    2 target bytes (PC_W = 11) + 1
//             shifts                  1 per step (N1); by a register + 1
//             JAL, FENCE              1
//   commit  : last register write + PC update, both in one clock edge.
//   The register file has one read port (rev 3). Register-register ALU ops and branches
//   take two cycles per byte: rs2's byte k into b_q, then rs1 and the byte ALU. A store reads
//   rs2 (its data) in its bus phase, after the address bytes; a shift by a register reads
//   the distance into sh_left_q in an extra first cycle.
//
// Not implemented: CSRs, interrupts, exceptions/traps, misaligned access, FENCE.I.
// ECALL/EBREAK -> halt_o, unsupported encoding -> illegal_o, SLVERR/DECERR on either bus ->
// bus_err_o. All three are sticky and stop the core (S_HALT) until reset.

module fc32e1s_nano_asic_core
  import fc32e1s_nano_asic_pkg::*;
#(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter int          PC_W     = 11,           // instruction address width (2 KiB); 32: Spike TB
  parameter int          DADDR_W  = 12            // data address width (4 KiB); 32: Spike TB
) (
  input  logic        clk_i,          // AXI ACLK
  input  logic        rst_ni,         // AXI ARESETn

  // ---- AXI4-Lite master: instruction ----
  output logic [PC_W-1:0] m_axi_i_awaddr,
  output logic [2:0]  m_axi_i_awprot,
  output logic        m_axi_i_awvalid,
  input  logic        m_axi_i_awready,
  output logic [31:0] m_axi_i_wdata,
  output logic [3:0]  m_axi_i_wstrb,
  output logic        m_axi_i_wvalid,
  input  logic        m_axi_i_wready,
  input  logic [1:0]  m_axi_i_bresp,
  input  logic        m_axi_i_bvalid,
  output logic        m_axi_i_bready,
  output logic [PC_W-1:0] m_axi_i_araddr,
  output logic [2:0]  m_axi_i_arprot,
  output logic        m_axi_i_arvalid,
  input  logic        m_axi_i_arready,
  input  logic [31:0] m_axi_i_rdata,
  input  logic [1:0]  m_axi_i_rresp,
  input  logic        m_axi_i_rvalid,
  output logic        m_axi_i_rready,

  // ---- AXI4-Lite master: data ----
  output logic [DADDR_W-1:0] m_axi_d_awaddr,
  output logic [2:0]  m_axi_d_awprot,
  output logic        m_axi_d_awvalid,
  input  logic        m_axi_d_awready,
  output logic [31:0] m_axi_d_wdata,
  output logic [3:0]  m_axi_d_wstrb,
  output logic        m_axi_d_wvalid,
  input  logic        m_axi_d_wready,
  input  logic [1:0]  m_axi_d_bresp,
  input  logic        m_axi_d_bvalid,
  output logic        m_axi_d_bready,
  output logic [DADDR_W-1:0] m_axi_d_araddr,
  output logic [2:0]  m_axi_d_arprot,
  output logic        m_axi_d_arvalid,
  input  logic        m_axi_d_arready,
  input  logic [31:0] m_axi_d_rdata,
  input  logic [1:0]  m_axi_d_rresp,
  input  logic        m_axi_d_rvalid,
  output logic        m_axi_d_rready,

  // ---- status (sticky until reset) ----
  output logic        halt_o,
  output logic        illegal_o,
  output logic        bus_err_o
);

  // ---------------------------------------------------------------------------
  // Signals
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] { S_RESET, S_FETCH, S_EXEC, S_HALT } state_e;

  state_e      state_q, state_d;
  logic        halt_q, illegal_q, bus_err_q;

  logic [PC_W-1:0] pc, pc_plus4;
  logic [31:0] instr;
  ctrl_t       ctrl;
  logic [31:0] imm;
  logic [31:0] rf_rdata;              // the register file's one read port
  logic [4:0]  rf_raddr;
  logic        rs2_rd, rs2_ok_q;     // shift by a register: distance read (extra first cycle)
  logic        redirect;
  logic [PC_W-1:0] target;
  logic [31:0] load_data;
  logic [31:0] rd_data;
  logic [3:0]  rf_be;

  logic        in_exec;
  logic        mem_op;
  logic        stop;
  logic        fetch_done, fetch_err;
  logic        lsu_req, lsu_done, lsu_err;
  logic [DADDR_W-1:0] lsu_addr;
  logic        commit;

  // multi-step shifter (N1): a shift runs for as many EXEC cycles as it has steps; rd holds
  // the partial result, read back through rs1's port (its address switched to rd)
  logic        is_shift, sh_cont_q, sh_last;
  logic [4:0]  sh_left_q, sh_rem, sh_next;
  shift_step_e sh_step;

  // ---------------------------------------------------------------------------
  // Control state machine
  // ---------------------------------------------------------------------------
  assign mem_op   = ctrl.mem_re | ctrl.mem_we;
  assign rs2_rd   = (state_q == S_EXEC) & is_shift & (ctrl.opb_sel == OPB_RS2) & ~rs2_ok_q;
  assign in_exec  = (state_q == S_EXEC) & ~rs2_rd;
  assign stop     = in_exec & (ctrl.halt | ctrl.illegal);
  assign is_shift = ctrl.alu_op inside {ALU_SLL, ALU_SRL, ALU_SRA};

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_RESET: state_d = S_FETCH;
      S_FETCH: if (fetch_done) state_d = fetch_err ? S_HALT : S_EXEC;
      S_EXEC:  if (stop || (lsu_done && lsu_err)) state_d = S_HALT;
               else if (commit)                   state_d = S_FETCH;
      default: state_d = S_HALT;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= S_RESET;
      halt_q    <= 1'b0;
      illegal_q <= 1'b0;
      bus_err_q <= 1'b0;
    end else begin
      state_q <= state_d;
      if (stop && ctrl.halt)              halt_q    <= 1'b1;
      if (stop && ctrl.illegal)           illegal_q <= 1'b1;
      if (fetch_err || (in_exec && lsu_err)) bus_err_q <= 1'b1;
    end
  end

  assign halt_o    = halt_q;
  assign illegal_o = illegal_q;
  assign bus_err_o = bus_err_q;

  // ---- shift steps ----
  // first cycle: the distance comes from the instruction (imm) or rs2[4:0]; later cycles: what
  // is left of it. rd may be rs2: the distance is latched in the first cycle.
  assign sh_rem  = (sh_cont_q || rs2_ok_q) ? sh_left_q : imm[4:0];
  assign sh_step = shift_step(sh_rem);
  assign sh_next = shift_left_after(sh_rem, sh_step);
  assign sh_last = (sh_next == 5'd0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sh_cont_q <= 1'b0;
    end else if (in_exec && is_shift && !stop) begin
      sh_cont_q <= !sh_last;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                 rs2_ok_q <= 1'b0;
    else if (state_q != S_EXEC)  rs2_ok_q <= 1'b0;
    else if (rs2_rd)             rs2_ok_q <= 1'b1;
  end

  always_ff @(posedge clk_i) begin
    if (rs2_rd)                       sh_left_q <= rf_rdata[4:0];
    else if (in_exec && is_shift)     sh_left_q <= sh_next;
  end

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------
  fc32e1s_nano_asic_pc #(.RESET_PC(RESET_PC), .PC_W(PC_W)) u_pc (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .en_i       (commit),
    .redirect_i (redirect),
    .target_i   (target),
    .pc_o       (pc),
    .pc_plus4_o (pc_plus4)
  );

  fc32e1s_nano_asic_fetch #(.IADDR_W(PC_W)) u_fetch (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .req_i         (state_q == S_FETCH),
    .pc_i          (pc),
    .done_o        (fetch_done),
    .err_o         (fetch_err),
    .instr_o       (instr),
    .m_axi_araddr  (m_axi_i_araddr),
    .m_axi_arprot  (m_axi_i_arprot),
    .m_axi_arvalid (m_axi_i_arvalid),
    .m_axi_arready (m_axi_i_arready),
    .m_axi_rdata   (m_axi_i_rdata),
    .m_axi_rresp   (m_axi_i_rresp),
    .m_axi_rvalid  (m_axi_i_rvalid),
    .m_axi_rready  (m_axi_i_rready)
  );

  // The instruction master never writes.
  assign m_axi_i_awaddr  = '0;
  assign m_axi_i_awprot  = AXI_PROT_INSTR;
  assign m_axi_i_awvalid = 1'b0;
  assign m_axi_i_wdata   = '0;
  assign m_axi_i_wstrb   = '0;
  assign m_axi_i_wvalid  = 1'b0;
  assign m_axi_i_bready  = 1'b1;

  // ---------------------------------------------------------------------------
  // Decode
  // ---------------------------------------------------------------------------
  fc32e1s_nano_asic_decoder u_decoder (
    .instr_i (instr),
    .ctrl_o  (ctrl)
  );

  fc32e1s_nano_asic_immgen u_immgen (
    .instr_i   (instr),
    .imm_sel_i (ctrl.imm_sel),
    .imm_o     (imm)
  );

  fc32e1s_nano_asic_regfile u_regfile (
    .clk_i      (clk_i),
    .raddr_i    (rf_raddr),
    .rdata_o    (rf_rdata),
    .be_i       (rf_be),
    .rd_addr_i  (instr[11:7]),
    .rd_data_i  (rd_data)
  );

  // ---------------------------------------------------------------------------
  // Execute
  // ---------------------------------------------------------------------------
  // ---- byte-serial ALU (N2): byte k = bc_q of the operands per cycle, rd written one
  // byte lane per cycle; branches compare in it; loads / stores / JALR build their address
  // in addr_q ----
  localparam int AQ_W = (PC_W > DADDR_W) ? PC_W : DADDR_W;
  localparam int AB   = (DADDR_W + 7) / 8;     // byte cycles of a load / store address
  localparam int PB   = (PC_W + 7) / 8;        // byte cycles of a JALR target

  logic        is_ag, is_alu, is_slt, is_ser, is_rr;
  logic        b_half_q;               // register-register: 0 = read rs2's byte, 1 = rs1 + ALU
  logic [7:0]  b_q;
  logic [1:0]  bc_q;
  logic        ph2_q;                  // after the byte cycles: address ready / SLT write
  logic        byte_cyc, last_byte;
  logic [7:0]  a_byte, b_byte, alu_byte;
  logic        alu_carry, alu_lt, alu_zero;
  logic        carry_q, zero_q, lt_q, zero_all, br_taken;
  logic [AQ_W-1:0] addr_q;
  logic [PC_W-1:0] pc_target;
  logic [31:0] sh_result;

  // classes: shifts (step shifter); loads / stores / JALR (address into addr_q, then use
  // it); the other register-writing ALU ops incl. LUI / AUIPC (byte ALU into rd; SLT / SLTU
  // write their result bit in one more cycle); branches (byte ALU compare). JAL, FENCE: one
  // cycle.
  assign is_ag  = mem_op | ctrl.jalr;
  assign is_alu = ctrl.rf_we & ~mem_op & ~ctrl.jal & ~ctrl.jalr & ~is_shift;
  assign is_slt = is_alu & (ctrl.alu_op inside {ALU_SLT, ALU_SLTU});
  assign is_ser = is_alu | ctrl.branch | is_ag;
  assign is_rr  = (is_alu | ctrl.branch) & (ctrl.opb_sel == OPB_RS2);

  assign byte_cyc  = in_exec & ~stop & is_ser & ~ph2_q & (~is_rr | b_half_q);
  assign last_byte = (bc_q == 2'(is_ag ? (ctrl.jalr ? PB - 1 : AB - 1) : 3));

  always_comb begin
    if (!in_exec || stop)  commit = 1'b0;
    else if (mem_op)       commit = ph2_q & lsu_done & ~lsu_err;
    else if (is_shift)     commit = sh_last;
    else if (ctrl.jalr)    commit = ph2_q;
    else if (is_slt)       commit = ph2_q;
    else if (is_ser)       commit = last_byte & byte_cyc; // ALU ops, branches
    else                   commit = 1'b1;                 // JAL, FENCE
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bc_q  <= '0;
      ph2_q <= 1'b0;
    end else if (!in_exec || commit) begin
      bc_q  <= '0;
      ph2_q <= 1'b0;
    end else if (byte_cyc) begin
      bc_q <= bc_q + 2'd1;
      if (last_byte) ph2_q <= 1'b1;
    end
  end

  // register-register: the cycles alternate between rs2's byte bc_q (into b_q) and the ALU
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                             b_half_q <= 1'b0;
    else if (!in_exec || commit)             b_half_q <= 1'b0;
    else if (is_rr && !stop && !ph2_q)       b_half_q <= !b_half_q;
  end

  always_ff @(posedge clk_i) begin
    if (in_exec && is_rr && !b_half_q) b_q <= 8'(rf_rdata >> (8 * bc_q));
  end

  // read port: rs2 for its byte (register-register), its data (store bus phase) or the shift
  // distance; rd while a shift continues; else rs1
  always_comb begin
    if (rs2_rd || (is_rr && !b_half_q) || (ctrl.mem_we && ph2_q)) rf_raddr = instr[24:20];
    else if (sh_cont_q)                                             rf_raddr = instr[11:7];
    else                                                            rf_raddr = instr[19:15];
  end

  // byte bc_q of the operands
  always_comb begin
    unique case (ctrl.opa_sel)
      OPA_PC:   a_byte = 8'(32'(pc) >> (8 * bc_q));
      OPA_ZERO: a_byte = 8'd0;
      default:  a_byte = 8'(rf_rdata >> (8 * bc_q));
    endcase
  end

  assign b_byte = (ctrl.opb_sel == OPB_IMM) ? 8'(imm >> (8 * bc_q)) : b_q;

  fc32e1s_nano_asic_alu8 u_alu8 (
    .op_i     (ctrl.alu_op),
    .a_i      (a_byte),
    .b_i      (b_byte),
    .first_i  (bc_q == 2'd0),
    .carry_i  (carry_q),
    .result_o (alu_byte),
    .carry_o  (alu_carry),
    .lt_o     (alu_lt),
    .zero_o   (alu_zero)
  );

  assign zero_all = alu_zero & ((bc_q == 2'd0) | zero_q);

  always_ff @(posedge clk_i) begin
    if (byte_cyc) begin
      carry_q <= alu_carry;
      zero_q  <= zero_all;
      lt_q    <= alu_lt;
    end
  end

  // loads / stores / JALR: the sum goes into the address register, one byte per cycle
  for (genvar k = 0; k < (AQ_W + 7) / 8; k++) begin : g_addr
    localparam int HI = (8 * k + 7 < AQ_W) ? 8 * k + 7 : AQ_W - 1;
    always_ff @(posedge clk_i) begin
      if (byte_cyc && is_ag && bc_q == 2'(k)) addr_q[HI:8*k] <= alu_byte[HI-8*k:0];
    end
  end

  fc32e1s_nano_asic_shift u_shift (
    .op_i     (ctrl.alu_op),
    .a_i      (rf_rdata),
    .step_i   (sh_step),
    .result_o (sh_result)
  );

  // branches decide on the top byte: BEQ / BNE on zero, the others on lt; funct3[0] inverts
  assign br_taken  = (instr[14] ? alu_lt : zero_all) ^ instr[12];
  assign pc_target = pc + imm[PC_W-1:0];                 // branch / JAL target
  assign redirect  = ctrl.jal | ctrl.jalr | (ctrl.branch & br_taken);
  assign target    = ctrl.jalr ? {addr_q[PC_W-1:1], 1'b0} : pc_target;

  assign lsu_req  = in_exec & mem_op & ph2_q;
  assign lsu_addr = addr_q[DADDR_W-1:0];

  // Byte ALU ops write rd's lane bc_q every byte cycle (SLT / SLTU: lanes 1..3 with 0
  // there, lane 0 with lt in the cycle after); shifts write all lanes every cycle; loads and
  // links all lanes at commit. rd's old bytes are read before they are overwritten (lane k
  // is read and written in the same cycle), so rd may be rs1 / rs2.
  always_comb begin
    rf_be = 4'b0000;
    if (in_exec && !stop && ctrl.rf_we) begin
      if (is_shift)                rf_be = 4'b1111;
      else if (is_alu && ph2_q)    rf_be = 4'b0001;                 // SLT / SLTU result bit
      else if (is_alu && byte_cyc) rf_be = (is_slt && bc_q == 2'd0) ? 4'b0000 : 4'(1 << bc_q);
      else if (commit)             rf_be = 4'b1111;                 // loads, JAL / JALR link
    end
  end

  always_comb begin
    if (is_shift)          rd_data = sh_result;
    else if (ctrl.mem_re)  rd_data = load_data;
    else if (ctrl.jal || ctrl.jalr) rd_data = 32'(pc_plus4);
    else                   rd_data = {4{ph2_q ? {7'd0, lt_q} : alu_byte}};
  end

  // ---------------------------------------------------------------------------
  // Memory
  // ---------------------------------------------------------------------------
  fc32e1s_nano_asic_lsu #(.DADDR_W(DADDR_W)) u_lsu (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .req_i         (lsu_req),
    .we_i          (ctrl.mem_we),
    .funct3_i      (instr[14:12]),
    .addr_i        (lsu_addr),
    .store_data_i  (rf_rdata),               // rs2 in the store's bus phase
    .done_o        (lsu_done),
    .err_o         (lsu_err),
    .load_data_o   (load_data),
    .m_axi_awaddr  (m_axi_d_awaddr),
    .m_axi_awprot  (m_axi_d_awprot),
    .m_axi_awvalid (m_axi_d_awvalid),
    .m_axi_awready (m_axi_d_awready),
    .m_axi_wdata   (m_axi_d_wdata),
    .m_axi_wstrb   (m_axi_d_wstrb),
    .m_axi_wvalid  (m_axi_d_wvalid),
    .m_axi_wready  (m_axi_d_wready),
    .m_axi_bresp   (m_axi_d_bresp),
    .m_axi_bvalid  (m_axi_d_bvalid),
    .m_axi_bready  (m_axi_d_bready),
    .m_axi_araddr  (m_axi_d_araddr),
    .m_axi_arprot  (m_axi_d_arprot),
    .m_axi_arvalid (m_axi_d_arvalid),
    .m_axi_arready (m_axi_d_arready),
    .m_axi_rdata   (m_axi_d_rdata),
    .m_axi_rresp   (m_axi_d_rresp),
    .m_axi_rvalid  (m_axi_d_rvalid),
    .m_axi_rready  (m_axi_d_rready)
  );

endmodule
