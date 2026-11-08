// fc32e1s_nano_ram.sv
// 512 x 32 RAM: port 0 read / write with a byte write mask, port 1 read only. The generic
// stand-in for the OpenRAM macro sky130_sram_2kbyte_1rw1r_32x512_8 inside
// fc32e1s_nano_subsystem (same port names and polarities: csb / web active low).
//
// Timing: each port captures its controls and address at the rising edge and shows the word
// after that edge, held until the port's next read (the macro: valid from the falling edge,
// X after the next rising edge). The subsystem's users register the word at the next rising
// edge (the fetch port's instruction register, axil_mem_ctrl), so they see the macro's
// timing. A write cycle leaves dout0 unchanged (the macro: X). Port 1 reading the word port 0
// writes in the same cycle returns the old word (the macro: undefined).
//
// One 512 x 8 array per byte lane (g_lane[b].mem), each enabled only when it reads or writes:
// Gowin then infers a dual-port block RAM in normal write mode per lane (4 BSRAM on GW2A).
// A single 32-bit array with byte-masked writes made it infer read-before-write on port 0
// (DPB WRITE_MODE 2'b10), which GW2A place and route rejects (PA2122).

module fc32e1s_nano_ram (
  // port 0: read / write
  input  logic        clk0,
  input  logic        csb0,
  input  logic        web0,
  input  logic [3:0]  wmask0,
  input  logic [8:0]  addr0,
  input  logic [31:0] din0,
  output logic [31:0] dout0,
  // port 1: read only
  input  logic        clk1,
  input  logic        csb1,
  input  logic [8:0]  addr1,
  output logic [31:0] dout1
);

  for (genvar b = 0; b < 4; b++) begin : g_lane
    logic [7:0] mem [0:511];

    always_ff @(posedge clk0) begin
      if (!csb0 && (web0 || wmask0[b])) begin
        if (!web0) mem[addr0]      <= din0[8*b +: 8];
        else       dout0[8*b +: 8] <= mem[addr0];
      end
    end

    always_ff @(posedge clk1) begin
      if (!csb1) dout1[8*b +: 8] <= mem[addr1];
    end
  end

endmodule
