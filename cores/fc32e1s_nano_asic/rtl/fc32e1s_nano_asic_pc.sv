// fc32e1s_nano_asic_pc.sv
// Program counter register and next-PC selection. The PC advances only when an
// instruction commits.
//
// PC_W bits wide, ports included (default 11: the CPU fetches from 2 KiB at most); jump /
// branch targets and PC + 4 wrap at 2^PC_W. The core's Spike testbench uses PC_W = 32 (tests
// run at 0x8000_0000).

module fc32e1s_nano_asic_pc #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter int          PC_W     = 11
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        en_i,        // instruction commits: load next PC
  input  logic        redirect_i,  // take jump/branch target
  input  logic [PC_W-1:0] target_i,

  output logic [PC_W-1:0] pc_o,
  output logic [PC_W-1:0] pc_plus4_o
);

  logic [PC_W-1:0] pc_q;

  assign pc_plus4_o = pc_q + PC_W'(4);
  assign pc_o       = pc_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)   pc_q <= RESET_PC[PC_W-1:0];
    else if (en_i) pc_q <= redirect_i ? target_i : pc_plus4_o;
  end

endmodule
