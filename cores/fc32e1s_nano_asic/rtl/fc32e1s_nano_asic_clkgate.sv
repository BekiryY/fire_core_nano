// fc32e1s_nano_asic_clkgate.sv
// Glitch-free clock gate for the latch register file: the enable is latched while the clock
// is low and ANDed with the clock, so gclk_o is either a full high phase or stays low.
//
// For sky130 synthesis, also define FC32E1S_NANO_ASIC_SKY130_ICG to use the library cell
// (sky130_fd_sc_hd__dlclkp_1); STA and CTS then see a real integrated clock gate. RTL
// simulation keeps the behavioural model (no cell library needed).

module fc32e1s_nano_asic_clkgate (
  input  logic clk_i,
  input  logic en_i,
  output logic gclk_o
);

`ifdef FC32E1S_NANO_ASIC_SKY130_ICG
  sky130_fd_sc_hd__dlclkp_1 u_icg (
    .CLK  (clk_i),
    .GATE (en_i),
    .GCLK (gclk_o)
  );
`else
  logic en_l;

  always_latch begin
    if (!clk_i) en_l <= en_i;
  end

  assign gclk_o = clk_i & en_l;
`endif

endmodule
