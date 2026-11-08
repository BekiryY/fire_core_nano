// axil_master_checker.sv
// Passive AXI4-Lite protocol checker for the MASTER side of one interface (testbench only).
//
// Checks, per address/write-data channel (AW, W, AR):
//   - xVALID is low while ARESETn is low
//   - xVALID is never X/Z after reset
//   - once xVALID is high it stays high until the handshake (no withdrawal)
//   - the payload is stable while xVALID is high and xREADY is low
// and for the response channels (B, R): xREADY is never X/Z after reset.
//
// ADDR_W / DATA_W: address and data widths of the interface (default 32 / 32).
//
// Violations are reported with $error and counted in errors_o; the testbench decides
// what to do with a non-zero count.

module axil_master_checker #(
  parameter string NAME   = "axil",
  parameter int    ADDR_W = 32,
  parameter int    DATA_W = 32
) (
  input  logic                clk,
  input  logic                rst_n,

  input  logic [ADDR_W-1:0]   awaddr,
  input  logic [2:0]          awprot,
  input  logic                awvalid,
  input  logic                awready,
  input  logic [DATA_W-1:0]   wdata,
  input  logic [DATA_W/8-1:0] wstrb,
  input  logic                wvalid,
  input  logic                wready,
  input  logic                bvalid,
  input  logic                bready,
  input  logic [ADDR_W-1:0]   araddr,
  input  logic [2:0]          arprot,
  input  logic                arvalid,
  input  logic                arready,
  input  logic                rvalid,
  input  logic                rready,

  output int unsigned errors_o
);

  int unsigned errors = 0;
  assign errors_o = errors;

  logic        aw_wait, w_wait, ar_wait;     // previous cycle: VALID && !READY
  logic [ADDR_W+2:0]          aw_pl;
  logic [DATA_W+DATA_W/8-1:0] w_pl;
  logic [ADDR_W+2:0]          ar_pl;

  task automatic fail(input string msg);
    errors++;
    $error("[%s] AXI4-Lite master violation: %s (t=%0t)", NAME, msg, $time);
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      if (awvalid !== 1'b0) fail("AWVALID not low during reset");
      if (wvalid  !== 1'b0) fail("WVALID not low during reset");
      if (arvalid !== 1'b0) fail("ARVALID not low during reset");
      aw_wait <= 1'b0;
      w_wait  <= 1'b0;
      ar_wait <= 1'b0;
    end else begin
      if ($isunknown({awvalid, wvalid, arvalid})) fail("X/Z on a VALID");
      if ($isunknown({bready, rready}))           fail("X/Z on BREADY/RREADY");

      if (aw_wait && !awvalid)                    fail("AWVALID withdrawn before AWREADY");
      if (aw_wait && {awaddr, awprot} !== aw_pl)  fail("AW payload changed while waiting");
      if (w_wait  && !wvalid)                     fail("WVALID withdrawn before WREADY");
      if (w_wait  && {wdata, wstrb} !== w_pl)     fail("W payload changed while waiting");
      if (ar_wait && !arvalid)                    fail("ARVALID withdrawn before ARREADY");
      if (ar_wait && {araddr, arprot} !== ar_pl)  fail("AR payload changed while waiting");

      if (awvalid && $isunknown({awaddr, awprot})) fail("X/Z on AW payload");
      if (wvalid  && $isunknown({wdata, wstrb}))   fail("X/Z on W payload");
      if (arvalid && $isunknown({araddr, arprot})) fail("X/Z on AR payload");

      aw_wait <= awvalid && !awready;
      w_wait  <= wvalid  && !wready;
      ar_wait <= arvalid && !arready;
      aw_pl   <= {awaddr, awprot};
      w_pl    <= {wdata, wstrb};
      ar_pl   <= {araddr, arprot};
    end
  end

endmodule
