// fc32e1s_nano_fpga_core.sv
// FireCore 32-bit RV32E-subset single-stage core — top level, AXI4-Lite native.
// fc32e1s with a 6-register file: only x0, x1 (ra), x2 (sp), x10..x12 (a0..a2) exist; any
// instruction that names another register is illegal (fc32e1s_nano_fpga_pkg::reg_exists,
// fc32e1s_nano_fpga_decoder).
// FPGA build (split from fc32e1s_nano rev 2, PLATFORM = PLAT_FPGA): 32-bit ALU, carry-chain branch
// comparator, register file in LUTRAM (fc32e1s_nano_fpga_regfile).
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
//   S_FETCH : fc32e1s_nano_fpga_fetch reads the instruction at PC into the instruction register.
//   S_EXEC  : decode + execute from the instruction register, one or more cycles:
//             ALU ops, LUI, AUIPC     1
//             branches                1
//             loads / stores          0 + bus
//             JALR                    1
//             shifts                  1 per step (N1)
//             JAL, FENCE              1
//   commit  : last register write + PC update, both in one clock edge.
//
// Not implemented: CSRs, interrupts, exceptions/traps, misaligned access, FENCE.I.
// ECALL/EBREAK -> halt_o, unsupported encoding -> illegal_o, SLVERR/DECERR on either bus ->
// bus_err_o. All three are sticky and stop the core (S_HALT) until reset.

module fc32e1s_nano_fpga_core
  import fc32e1s_nano_fpga_pkg::*;
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
  logic [31:0] rs1_data, rs2_data;
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
  assign in_exec  = (state_q == S_EXEC);
  assign mem_op   = ctrl.mem_re | ctrl.mem_we;
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
  assign sh_rem  = sh_cont_q ? sh_left_q : ((ctrl.opb_sel == OPB_IMM) ? imm[4:0] : rs2_data[4:0]);
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

  always_ff @(posedge clk_i) begin
    if (in_exec && is_shift) sh_left_q <= sh_next;
  end

  // ---------------------------------------------------------------------------
  // Fetch
  // ---------------------------------------------------------------------------
  fc32e1s_nano_fpga_pc #(.RESET_PC(RESET_PC), .PC_W(PC_W)) u_pc (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .en_i       (commit),
    .redirect_i (redirect),
    .target_i   (target),
    .pc_o       (pc),
    .pc_plus4_o (pc_plus4)
  );

  fc32e1s_nano_fpga_fetch #(.IADDR_W(PC_W)) u_fetch (
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
  fc32e1s_nano_fpga_decoder u_decoder (
    .instr_i (instr),
    .ctrl_o  (ctrl)
  );

  fc32e1s_nano_fpga_immgen u_immgen (
    .instr_i   (instr),
    .imm_sel_i (ctrl.imm_sel),
    .imm_o     (imm)
  );

  fc32e1s_nano_fpga_regfile u_regfile (
    .clk_i      (clk_i),
    .rs1_addr_i (sh_cont_q ? instr[11:7] : instr[19:15]),
    .rs1_data_o (rs1_data),
    .rs2_addr_i (instr[24:20]),
    .rs2_data_o (rs2_data),
    .be_i       (rf_be),
    .rd_addr_i  (instr[11:7]),
    .rd_data_i  (rd_data)
  );

  // ---------------------------------------------------------------------------
  // Execute
  // ---------------------------------------------------------------------------
  // ---- 32-bit ALU, one EXEC cycle (shifts: one per step), carry-chain comparator for
  // branches (cheaper on GW2A than comparing in the ALU's adder: +78 logic measured) ----
  logic [31:0] alu_a, alu_b, alu_result;
  logic        br_taken;

  always_comb begin
    unique case (ctrl.opa_sel)
      OPA_PC:   alu_a = 32'(pc);
      OPA_ZERO: alu_a = '0;
      default:  alu_a = rs1_data;
    endcase
  end

  assign alu_b = (ctrl.opb_sel == OPB_IMM) ? imm : rs2_data;

  fc32e1s_nano_fpga_alu u_alu (
    .op_i     (ctrl.alu_op),
    .a_i      (alu_a),
    .b_i      (alu_b),
    .step_i   (sh_step),
    .result_o (alu_result)
  );

  fc32e1s_nano_fpga_branch u_branch (
    .funct3_i (instr[14:12]),
    .rs1_i    (rs1_data),
    .rs2_i    (rs2_data),
    .taken_o  (br_taken)
  );

  assign redirect = ctrl.jal | ctrl.jalr | (ctrl.branch & br_taken);
  assign target   = ctrl.jalr ? {alu_result[PC_W-1:1], 1'b0} : alu_result[PC_W-1:0];

  // An instruction commits when it finished without halting: ALU ops in their EXEC cycle
  // (shifts in their last one), loads/stores in the cycle their OKAY response arrives.
  assign commit = in_exec & ~stop &
                  (mem_op ? (lsu_done & ~lsu_err) : (is_shift ? sh_last : 1'b1));

  // register write: at commit, and in every cycle of a shift (its partial results)
  assign rf_be = {4{ctrl.rf_we & in_exec & ~stop & (is_shift | commit)}};

  assign lsu_req  = in_exec & mem_op;
  assign lsu_addr = alu_result[DADDR_W-1:0];

  always_comb begin
    unique case (ctrl.wb_sel)
      WB_MEM:  rd_data = load_data;
      WB_PC4:  rd_data = 32'(pc_plus4);
      default: rd_data = alu_result;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Memory
  // ---------------------------------------------------------------------------
  fc32e1s_nano_fpga_lsu #(.DADDR_W(DADDR_W)) u_lsu (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .req_i         (lsu_req),
    .we_i          (ctrl.mem_we),
    .funct3_i      (instr[14:12]),
    .addr_i        (lsu_addr),
    .store_data_i  (rs2_data),
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
