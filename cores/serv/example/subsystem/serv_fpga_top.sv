// serv_fpga_top.sv
// SERV on the same FPGA board top as fc32e1s_nano_fpga_top (cores/fc32e1s_nano_fpga/example/
// subsystem), for comparing the two cores on an FPGA: the same 2 KiB block RAM module
// (fc32e1s_nano_fpga_ram) holding code, data and stack, the same reset synchronizer and the same
// LED / counter peripheral. SERV is upstream serv_rf_top (register file in block RAM) with
// WITH_CSR = 0 (no CSRs, as the nano has none).
//
//   SERV ibus --> RAM port 1                    0x00000000 - 0x000007FF
//   SERV dbus --+--> RAM port 0 (load / store)  0x00000000 - 0x000007FF
//               +--> peripheral                 address bit 31 set (software: 0xFFFFF800 + offset)
//
// Wishbone: each bus is acknowledged one cycle after CYC, with the RAM word (the RAM is
// synchronous); a write is done in the CYC cycle. Peripheral (address bits 3:2): 0x800 LED (R/W,
// bits 7:0 drive led_o), 0x804 CYCLE (R), 0x808 INSTRET (R), 0x80C SIM (W, testbench only).
// An instruction retires at its fetch acknowledge: SERV fetches the next instruction only when
// the current one is done.

module serv_fpga_top #(
  parameter string INIT_FILE = "cpi_test_"   // RAM image prefix (bench/cpi_test/build.sh)
) (
  input  logic       clk_i,
  input  logic       rst_ni,          // asynchronous, active low (button)
  output logic [7:0] led_o
);

  // ---------------------------------------------------------------------------
  // Reset: asserted asynchronously, released synchronously
  // ---------------------------------------------------------------------------
  logic [1:0] rst_q;
  logic       rst_n;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rst_q <= 2'b00;
    else         rst_q <= {rst_q[0], 1'b1};
  end
  assign rst_n = rst_q[1];

  // ---------------------------------------------------------------------------
  // SERV
  // ---------------------------------------------------------------------------
  logic [31:0] i_adr, i_rdt, d_adr, d_dat, d_rdt;
  logic [3:0]  d_sel;
  logic        i_cyc, i_ack, d_we, d_cyc, d_ack;

  serv_rf_top #(
    .RESET_PC (32'h0),
    .WITH_CSR (0)
  ) u_serv (
    .clk          (clk_i),
    .i_rst        (!rst_n),
    .i_timer_irq  (1'b0),
    .o_ibus_adr   (i_adr),
    .o_ibus_cyc   (i_cyc),
    .i_ibus_rdt   (i_rdt),
    .i_ibus_ack   (i_ack),
    .o_dbus_adr   (d_adr),
    .o_dbus_dat   (d_dat),
    .o_dbus_sel   (d_sel),
    .o_dbus_we    (d_we),
    .o_dbus_cyc   (d_cyc),
    .i_dbus_rdt   (d_rdt),
    .i_dbus_ack   (d_ack),
    .o_ext_rs1    (),
    .o_ext_rs2    (),
    .o_ext_funct3 (),
    .i_ext_rd     (32'd0),
    .i_ext_ready  (1'b0),
    .o_mdu_valid  ()
  );

  // ---------------------------------------------------------------------------
  // RAM: dbus on port 0, ibus on port 1
  // ---------------------------------------------------------------------------
  logic        d_req, d_io, wr, rd;
  logic [31:0] ram_dout0, io_rdata;

  assign d_req = d_cyc && !d_ack;
  assign d_io  = d_adr[31];
  assign wr    = d_req && d_io && d_we;
  assign rd    = d_req && d_io && !d_we;

  fc32e1s_nano_fpga_ram #(.INIT_FILE (INIT_FILE)) u_ram (
    .clk_i    (clk_i),
    .en0_i    (d_req && !d_io),
    .we0_i    (d_we),
    .wmask0_i (d_sel),
    .addr0_i  (d_adr[10:2]),
    .din0_i   (d_dat),
    .dout0_o  (ram_dout0),
    .en1_i    (i_cyc && !i_ack),
    .addr1_i  (i_adr[10:2]),
    .dout1_o  (i_rdt)
  );

  logic io_q;

  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) begin
      i_ack <= 1'b0;
      d_ack <= 1'b0;
      io_q  <= 1'b0;
    end else begin
      i_ack <= i_cyc && !i_ack;
      d_ack <= d_req;
      if (d_req) io_q <= d_io;
    end
  end

  assign d_rdt = io_q ? io_rdata : ram_dout0;

  // ---------------------------------------------------------------------------
  // Peripheral: LED, cycle and instruction counters
  // ---------------------------------------------------------------------------
  logic [31:0] cycle_q, instret_q;
  logic [7:0]  led_q;
  logic        retire;

  assign retire = i_cyc && i_ack;

  always_ff @(posedge clk_i or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q   <= '0;
      instret_q <= '0;
      led_q     <= '0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (retire) instret_q <= instret_q + 1'b1;
      if (wr && d_adr[3:2] == 2'd0 && d_sel[0]) led_q <= d_dat[7:0];
    end
  end

  always_ff @(posedge clk_i) begin
    if (rd) begin
      case (d_adr[3:2])
        2'd0:    io_rdata <= {24'd0, led_q};
        2'd1:    io_rdata <= cycle_q;
        2'd2:    io_rdata <= instret_q;
        default: io_rdata <= '0;
      endcase
    end
  end

  assign led_o = led_q;

endmodule
