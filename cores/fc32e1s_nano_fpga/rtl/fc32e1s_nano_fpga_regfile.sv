// fc32e1s_nano_fpga_regfile.sv
// General-purpose registers x1, x2, x10..x12 (5 words, fc32e1s_nano_fpga_pkg::reg_phys); x0 and
// the registers that do not exist read as zero. The decoder makes any instruction naming a
// missing register illegal, so such an address never reaches the write port.
// 2 asynchronous read ports, 1 write port with a byte enable per lane (all four lanes are
// written together here; the byte enables are kept for the shared interface).
//
// 4 byte-wide 8 x 8 LUTRAMs (Gowin SSRAM), synchronous write at the write
// edge, asynchronous reads. Entry 0 is x0 (and the missing registers, whose instructions
// are illegal): it is never written and holds 0 from configuration (initial value, = the
// SSRAM default), so the read ports need no zero mux. syn_ramstyle is required: without it
// Gowin builds a small array from BSRAM or flip-flops.
//
// Registers are intentionally NOT reset: reading an unwritten register yields X in
// 4-state simulation, which exposes software/RTL bugs instead of hiding them behind 0.

module fc32e1s_nano_fpga_regfile
  import fc32e1s_nano_fpga_pkg::*;
(
  input  logic        clk_i,

  input  logic [4:0]  rs1_addr_i,
  output logic [31:0] rs1_data_o,
  input  logic [4:0]  rs2_addr_i,
  output logic [31:0] rs2_data_o,

  input  logic [3:0]  be_i,          // write byte enables (0: no write)
  input  logic [4:0]  rd_addr_i,
  input  logic [31:0] rd_data_i
);

  logic [2:0]  p1, p2, pd;

  assign p1 = reg_phys(rs1_addr_i);
  assign p2 = reg_phys(rs2_addr_i);
  assign pd = reg_phys(rd_addr_i);

  for (genvar b = 0; b < 4; b++) begin : g_lane
    (* syn_ramstyle = "distributed_ram" *) logic [7:0] mem [0:NUM_PREGS];

    initial mem[0] = '0;    // x0; words 1..7 stay X until written (see above)

    always_ff @(posedge clk_i) begin
      if (be_i[b] && pd != '0) mem[pd] <= rd_data_i[8*b +: 8];
    end

    assign rs1_data_o[8*b +: 8] = mem[p1];
    assign rs2_data_o[8*b +: 8] = mem[p2];
  end

endmodule
