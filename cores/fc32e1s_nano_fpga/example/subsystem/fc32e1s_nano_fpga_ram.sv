// fc32e1s_nano_fpga_ram.sv
// 512 x 32 RAM (2 KiB): port 0 read / write with a byte write mask, port 1 read only, both
// synchronous (the word is there after the rising edge that takes the address, held until
// the port's next read). Port 1 reading the word port 0 writes in the same cycle returns the
// old word.
//
// One 512 x 8 array per byte lane, each enabled only when it reads or writes: Gowin then
// infers a dual-port block RAM in normal write mode per lane (4 BSRAM on GW2A). A single
// 32-bit array with byte-masked writes made it infer read-before-write on port 0, which GW2A
// place and route rejects (PA2122).
//
// INIT_FILE: the program image, one $readmemh file per byte lane, <INIT_FILE>0.hex ..
// <INIT_FILE>3.hex (one byte per line, word address order; sw/build.sh writes them). Empty:
// no initial contents.

module fc32e1s_nano_fpga_ram #(
  parameter string INIT_FILE = ""
) (
  input  logic        clk_i,
  // port 0: read / write
  input  logic        en0_i,
  input  logic        we0_i,
  input  logic [3:0]  wmask0_i,
  input  logic [8:0]  addr0_i,
  input  logic [31:0] din0_i,
  output logic [31:0] dout0_o,
  // port 1: read only
  input  logic        en1_i,
  input  logic [8:0]  addr1_i,
  output logic [31:0] dout1_o
);

  for (genvar b = 0; b < 4; b++) begin : g_lane
    logic [7:0] mem [0:511];

    if (INIT_FILE != "") begin : g_init
      initial begin
        case (b)
          0: $readmemh({INIT_FILE, "0.hex"}, mem);
          1: $readmemh({INIT_FILE, "1.hex"}, mem);
          2: $readmemh({INIT_FILE, "2.hex"}, mem);
          3: $readmemh({INIT_FILE, "3.hex"}, mem);
        endcase
      end
    end

    always_ff @(posedge clk_i) begin
      if (en0_i && (!we0_i || wmask0_i[b])) begin
        if (we0_i) mem[addr0_i]        <= din0_i[8*b +: 8];
        else       dout0_o[8*b +: 8]   <= mem[addr0_i];
      end
    end

    always_ff @(posedge clk_i) begin
      if (en1_i) dout1_o[8*b +: 8] <= mem[addr1_i];
    end
  end

endmodule
