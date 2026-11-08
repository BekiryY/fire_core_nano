// fc32e1s_nano_subsystem.sv
// fc32e1s_nano CPU subsystem in RTL: the frozen core with its fetch port and boot ROM
// (fc32e1s_nano_sram2k_v2_cpu.sv) on a 2 KiB RAM (fc32e1s_nano_ram.sv). It is the function
// of the sky130 hard macro sky130_sram_2kbyte_1rw1r_32x512_8_fc32e1s_nano_v2 (the same logic
// half on the OpenRAM SRAM, appl/sky130_sram_macro_v2) with a generic RAM, for simulation
// and FPGA builds. Same pins as the macro, without its power pins and its port-1 stubs.
//
//   +------------------------------------------------------------------+
//   |  fc32e1s_nano_sram2k_v2_cpu                                      |
//   |    core m_axi_i --> fetch port --+--> boot ROM   0x000 - 0x07F   |
//   |                                  +--> RAM port 1 0x080 - 0x7FF   |
//   |    core m_axi_d ---------------------------------------------------> m_axi_d_* (12-bit)
//   +------------------------------------------------------------------+
//      fc32e1s_nano_ram port 0 (read / write) <------------------------- clk0 csb0 web0
//                                                                        wmask0 addr0 din0 dout0
//
// Unlike fc32ec3fs_subsystem, the data-side memory controller is not in here: the MCU
// (../mcu/tiny_soc.sv) puts a register slice on m_axi_d, decodes it in its interconnect and
// drives RAM port 0 through axil_mem_ctrl (CPU data and the SPI flash's memory master). On
// the chip the hard macro's boundary is the SRAM's pins, and this module keeps it.
//
// tiny_soc uses this module unless FC32E1S_NANO_HARD_MACRO is defined (the sky130 chip
// configs define it; same instance name u_macro; inside: u_cpu, u_sram as in the macro model).

module fc32e1s_nano_subsystem (
  // RAM port 0 (read / write), driven by the MCU's memory controller
  input  logic        clk0,
  input  logic        csb0,               // active low
  input  logic        web0,               // active low
  input  logic [3:0]  wmask0,
  input  logic [8:0]  addr0,              // word address
  input  logic [31:0] din0,
  output logic [31:0] dout0,
  // CPU
  input  logic        clk_i,
  input  logic        rst_ni,             // asynchronous, active low
  output logic [11:0] m_axi_d_addr,       // AW and AR address (the same word address)
  output logic        m_axi_d_awvalid,
  input  logic        m_axi_d_awready,
  output logic [31:0] m_axi_d_wdata,
  output logic [3:0]  m_axi_d_wstrb,
  output logic        m_axi_d_wvalid,
  input  logic        m_axi_d_wready,
  input  logic [1:0]  m_axi_d_bresp,
  input  logic        m_axi_d_bvalid,
  output logic        m_axi_d_bready,
  output logic        m_axi_d_arvalid,
  input  logic        m_axi_d_arready,
  input  logic [31:0] m_axi_d_rdata,
  input  logic [1:0]  m_axi_d_rresp,
  input  logic        m_axi_d_rvalid,
  output logic        m_axi_d_rready,
  output logic        halt_o,
  output logic        illegal_o,
  output logic        bus_err_o
);

  logic        ram1_clk, ram1_csb;
  logic [8:0]  ram1_addr;
  logic [31:0] ram1_dout;

  fc32e1s_nano_ram u_sram (
    .clk0 (clk0), .csb0 (csb0), .web0 (web0), .wmask0 (wmask0), .addr0 (addr0),
    .din0 (din0), .dout0 (dout0),
    .clk1 (ram1_clk), .csb1 (ram1_csb), .addr1 (ram1_addr), .dout1 (ram1_dout)
  );

  fc32e1s_nano_sram2k_v2_cpu u_cpu (
    .clk_i (clk_i), .rst_ni (rst_ni),
    .m_axi_d_addr (m_axi_d_addr), .m_axi_d_awvalid (m_axi_d_awvalid),
    .m_axi_d_awready (m_axi_d_awready), .m_axi_d_wdata (m_axi_d_wdata),
    .m_axi_d_wstrb (m_axi_d_wstrb), .m_axi_d_wvalid (m_axi_d_wvalid),
    .m_axi_d_wready (m_axi_d_wready), .m_axi_d_bresp (m_axi_d_bresp),
    .m_axi_d_bvalid (m_axi_d_bvalid), .m_axi_d_bready (m_axi_d_bready),
    .m_axi_d_arvalid (m_axi_d_arvalid),
    .m_axi_d_arready (m_axi_d_arready), .m_axi_d_rdata (m_axi_d_rdata),
    .m_axi_d_rresp (m_axi_d_rresp), .m_axi_d_rvalid (m_axi_d_rvalid),
    .m_axi_d_rready (m_axi_d_rready),
    .halt_o (halt_o), .illegal_o (illegal_o), .bus_err_o (bus_err_o),
    .ram1_clk (ram1_clk), .ram1_csb (ram1_csb), .ram1_addr (ram1_addr), .ram1_dout (ram1_dout)
  );

endmodule
