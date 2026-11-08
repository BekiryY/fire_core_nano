// fc32e1s_nano_asic_lsu.sv
// Load/store unit: AXI4-Lite data master, byte lanes and load alignment.
//
// The core holds req_i high (with stable we_i/funct3_i/addr_i/store_data_i) until done_o.
// One transaction at a time:
//
//   load  : ARVALID until ARREADY, then RREADY until RVALID
//   store : AWVALID and WVALID raised together; each is dropped after its own handshake
//           (a slave may accept them in either order or in different cycles), then
//           BREADY until BVALID
//
// done_o is high in the cycle of the R/B handshake; load_data_o is valid in that cycle.
// err_o qualifies done_o: RRESP/BRESP was SLVERR or DECERR.
//
// Bus format: word-aligned address, full 32-bit data.
//   stores -> byte lanes replicated, WSTRB selects the lanes
//   loads  -> full word read, shifted and sign/zero extended here
// Misaligned accesses are not supported (no trap): the result is undefined.
//
// DADDR_W address bits, ports included (default 12: 4 KiB data space, RAM + peripherals; the
// software view of the peripherals is 0xFFFFF800 + offset). The core's Spike testbench uses
// DADDR_W = 32.

module fc32e1s_nano_asic_lsu
  import fc32e1s_nano_asic_pkg::*;
#(
  parameter int DADDR_W = 12
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_i,
  input  logic        we_i,         // 1 = store, 0 = load
  input  logic [2:0]  funct3_i,     // access width / signedness
  input  logic [DADDR_W-1:0] addr_i, // byte address from ALU
  input  logic [31:0] store_data_i, // rs2
  output logic        done_o,
  output logic        err_o,
  output logic [31:0] load_data_o,

  // AXI4-Lite master
  output logic [DADDR_W-1:0] m_axi_awaddr,
  output logic [2:0]  m_axi_awprot,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,
  output logic [31:0] m_axi_wdata,
  output logic [3:0]  m_axi_wstrb,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,
  output logic [DADDR_W-1:0] m_axi_araddr,
  output logic [2:0]  m_axi_arprot,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,
  input  logic [31:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready
);

  logic [1:0]  offset;
  logic [DADDR_W-1:0] word_addr;
  logic        resp_q;        // address/data phase done, waiting for R or B
  logic        aw_done_q;     // store: AW accepted
  logic        w_done_q;      // store: W accepted
  logic        aw_fire, w_fire, ar_fire, addr_complete;
  logic [31:0] rdata_shifted;

  assign offset    = addr_i[1:0];
  assign word_addr = {addr_i[DADDR_W-1:2], 2'b00};

  // ---- address / write data channels ----
  assign m_axi_awaddr  = word_addr;
  assign m_axi_awprot  = AXI_PROT_DATA;
  assign m_axi_awvalid = req_i && we_i && !resp_q && !aw_done_q;
  assign m_axi_wvalid  = req_i && we_i && !resp_q && !w_done_q;
  assign m_axi_araddr  = word_addr;
  assign m_axi_arprot  = AXI_PROT_DATA;
  assign m_axi_arvalid = req_i && !we_i && !resp_q;

  always_comb begin
    unique case (funct3_i[1:0])
      2'b00:   begin m_axi_wstrb = 4'b0001 << offset;            m_axi_wdata = {4{store_data_i[7:0]}};  end
      2'b01:   begin m_axi_wstrb = 4'b0011 << {offset[1], 1'b0}; m_axi_wdata = {2{store_data_i[15:0]}}; end
      default: begin m_axi_wstrb = 4'b1111;                      m_axi_wdata = store_data_i;            end
    endcase
  end

  assign aw_fire = m_axi_awvalid && m_axi_awready;
  assign w_fire  = m_axi_wvalid  && m_axi_wready;
  assign ar_fire = m_axi_arvalid && m_axi_arready;

  // Address phase is complete when AR fired (load), or when both AW and W have fired,
  // in this cycle or an earlier one (store).
  assign addr_complete = we_i ? ((aw_done_q || aw_fire) && (w_done_q || w_fire)) : ar_fire;

  // ---- response channels ----
  assign m_axi_bready = resp_q && we_i;
  assign m_axi_rready = resp_q && !we_i;

  assign done_o = resp_q && (we_i ? m_axi_bvalid : m_axi_rvalid);
  assign err_o  = done_o && (we_i ? m_axi_bresp[1] : m_axi_rresp[1]);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      resp_q    <= 1'b0;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else if (done_o) begin
      resp_q    <= 1'b0;
    end else if (req_i && !resp_q) begin
      if (addr_complete) begin
        resp_q    <= 1'b1;
        aw_done_q <= 1'b0;
        w_done_q  <= 1'b0;
      end else begin
        if (aw_fire) aw_done_q <= 1'b1;
        if (w_fire)  w_done_q  <= 1'b1;
      end
    end
  end

  // ---- load alignment ----
  assign rdata_shifted = m_axi_rdata >> {offset, 3'b000};

  always_comb begin
    unique case (funct3_i)
      MEM_B:   load_data_o = {{24{rdata_shifted[7]}},  rdata_shifted[7:0]};
      MEM_H:   load_data_o = {{16{rdata_shifted[15]}}, rdata_shifted[15:0]};
      MEM_BU:  load_data_o = {24'd0, rdata_shifted[7:0]};
      MEM_HU:  load_data_o = {16'd0, rdata_shifted[15:0]};
      default: load_data_o = m_axi_rdata;
    endcase
  end

endmodule
