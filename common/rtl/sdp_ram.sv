// sdp_ram.sv
// Simple dual-port RAM, single clock: one write port, one read port.
// Written so synthesis maps it to block RAM (Gowin BSRAM, Xilinx BRAM, ...):
//
//   write port : byte-enabled write on the rising edge
//   read port  : synchronous read, 1-cycle latency, output register held when rd_en_i = 0
//   same word read and written in one cycle: read returns the OLD data (read-first)
//
// Not reset (RAM and read register) so inference is not blocked.
// DATA_W: word width in bits, a multiple of 8 (default 32); one byte enable per byte.
// INIT_FILE (optional): $readmemh image, one DATA_W-bit word per line.

module sdp_ram #(
  parameter int    DEPTH     = 512,    // DATA_W-bit words
  parameter int    DATA_W    = 32,
  parameter string INIT_FILE = ""
) (
  input  logic                     clk,

  // write port
  input  logic                     wr_en_i,
  input  logic [DATA_W/8-1:0]      wr_be_i,
  input  logic [$clog2(DEPTH)-1:0] wr_addr_i,   // word address
  input  logic [DATA_W-1:0]        wr_data_i,

  // read port
  input  logic                     rd_en_i,
  input  logic [$clog2(DEPTH)-1:0] rd_addr_i,   // word address
  output logic [DATA_W-1:0]        rd_data_o
);

  logic [DATA_W-1:0] mem [DEPTH];

  initial begin
    if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
  end

  always_ff @(posedge clk) begin
    if (wr_en_i) begin
      for (int b = 0; b < DATA_W/8; b++)
        if (wr_be_i[b]) mem[wr_addr_i][8*b +: 8] <= wr_data_i[8*b +: 8];
    end
  end

  always_ff @(posedge clk) begin
    if (rd_en_i) rd_data_o <= mem[rd_addr_i];
  end

endmodule
