// ============================================================================
//  tb_fc32e1s_nano_fpga_spike.sv -- fc32e1s_nano_fpga (AXI4-Lite) core-level testbench, Spike comparison
//
//  Runs the same ELF image that spike_iss/run_spike.sh runs on Spike and writes an
//  instruction trace (fc32e1s_nano_fpga_tracer) that spike_iss/checker.py compares line by line
//  against the Spike golden trace.
//
//  STRUCTURE
//    fc32e1s_nano_fpga_core
//      m_axi_i --> IMEM (read-only)    + axil_master_checker
//      m_axi_d --> DMEM                 + axil_master_checker
//
//    Memories: by default common/tb/axil_mem_model (random wait states, below).
//    Compile with -d USE_RTL_MEM to use the synthesisable common/rtl/axil_imem and
//    axil_dmem instead (fixed 1-cycle read latency, AW+W accepted together).
//
//  WAIT STATES
//    Default: random READY on AR/AW/W and 0..3 cycles before RVALID/BVALID, so every
//    stall path in the core is exercised. The pattern follows the simulator seed
//    (xsim --sv_seed, set by run_core_rtl.sh). Compile with -d AXI_NO_WAIT for a
//    zero-wait-state slave (fastest legal timing).
//
//  MEMORY MAP -- identical to spike_iss/env/core_test.ld and core.cfg
//    0x8000_0000 .. 0x8000_0FFF   IMEM 4 KB  (.text) -- not 0x0: spike's debug module is there
//    0x2000_0000 .. 0x2000_1FFF   DMEM 8 KB  (.rodata/.data/.bss/stack)
//    0x2000_1FC0                  tohost
//
//  END OF TEST
//    tohost = 1          -> "[TB] SONUC: GECTI"
//    tohost = (N<<1)|1   -> "[TB] SONUC: HATA blok x30=N"
//  Also fails on: halt (ECALL/EBREAK), illegal instruction, bus error (SLVERR/DECERR,
//  e.g. fetch outside IMEM), any AXI protocol violation, deadlock (no commit for
//  STALL_LIMIT cycles), timeout.
//
//  INPUT FILES (fixed names in CWD -- the Windows xsim wrapper splits
//  "+IMEM=path" at '=', see run_core_rtl.sh)
//    imem.hex   required, objcopy -O verilog of .text, rebased to 0
//    dmem.hex   optional, initialised data rebased to 0
// ============================================================================

  `define DUT u_dut

module tb_fc32e1s_nano_fpga_spike;

  localparam logic [31:0] IMEM_BASE   = 32'h8000_0000;
  localparam int          IMEM_BYTES  = 4096;
  localparam logic [31:0] DMEM_BASE   = 32'h2000_0000;
  localparam int          DMEM_BYTES  = 8192;
  localparam logic [31:0] TOHOST_ADDR = 32'h2000_1FC0;
  localparam int          TIMEOUT     = 10_000_000;  // c_tests bench_Os: 375k instructions, CPI 3-4 + random waits
  // No instruction committed for this many cycles = deadlock (e.g. a master waiting for
  // READY before raising VALID). Longest legal stall here is a few wait states.
  localparam int          STALL_LIMIT = 1000;

`ifdef AXI_NO_WAIT
  localparam int          MAX_WAIT    = 0;
`else
  localparam int          MAX_WAIT    = 3;
`endif

  logic clk = 1'b0;
  logic rst_n = 1'b0;

  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // AXI4-Lite wires
  // ---------------------------------------------------------------------------
  logic [31:0] i_awaddr, i_wdata, i_araddr, i_rdata;
  logic [2:0]  i_awprot, i_arprot;
  logic [3:0]  i_wstrb;
  logic [1:0]  i_bresp, i_rresp;
  logic        i_awvalid, i_awready, i_wvalid, i_wready, i_bvalid, i_bready;
  logic        i_arvalid, i_arready, i_rvalid, i_rready;

  logic [31:0] d_awaddr, d_wdata, d_araddr, d_rdata;
  logic [2:0]  d_awprot, d_arprot;
  logic [3:0]  d_wstrb;
  logic [1:0]  d_bresp, d_rresp;
  logic        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  logic        d_arvalid, d_arready, d_rvalid, d_rready;

  logic        halt, illegal, bus_err;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  fc32e1s_nano_fpga_core #(.RESET_PC(IMEM_BASE), .PC_W(32), .DADDR_W(32)) u_dut (   // tests run at 0x8000_0000
    .clk_i (clk), .rst_ni (rst_n),

    .m_axi_i_awaddr (i_awaddr),  .m_axi_i_awprot (i_awprot),  .m_axi_i_awvalid (i_awvalid),
    .m_axi_i_awready(i_awready), .m_axi_i_wdata  (i_wdata),   .m_axi_i_wstrb   (i_wstrb),
    .m_axi_i_wvalid (i_wvalid),  .m_axi_i_wready (i_wready),  .m_axi_i_bresp   (i_bresp),
    .m_axi_i_bvalid (i_bvalid),  .m_axi_i_bready (i_bready),  .m_axi_i_araddr  (i_araddr),
    .m_axi_i_arprot (i_arprot),  .m_axi_i_arvalid(i_arvalid), .m_axi_i_arready (i_arready),
    .m_axi_i_rdata  (i_rdata),   .m_axi_i_rresp  (i_rresp),   .m_axi_i_rvalid  (i_rvalid),
    .m_axi_i_rready (i_rready),

    .m_axi_d_awaddr (d_awaddr),  .m_axi_d_awprot (d_awprot),  .m_axi_d_awvalid (d_awvalid),
    .m_axi_d_awready(d_awready), .m_axi_d_wdata  (d_wdata),   .m_axi_d_wstrb   (d_wstrb),
    .m_axi_d_wvalid (d_wvalid),  .m_axi_d_wready (d_wready),  .m_axi_d_bresp   (d_bresp),
    .m_axi_d_bvalid (d_bvalid),  .m_axi_d_bready (d_bready),  .m_axi_d_araddr  (d_araddr),
    .m_axi_d_arprot (d_arprot),  .m_axi_d_arvalid(d_arvalid), .m_axi_d_arready (d_arready),
    .m_axi_d_rdata  (d_rdata),   .m_axi_d_rresp  (d_rresp),   .m_axi_d_rvalid  (d_rvalid),
    .m_axi_d_rready (d_rready),

    .halt_o (halt), .illegal_o (illegal), .bus_err_o (bus_err)
  );


  // ---------------------------------------------------------------------------
  // Memories (AXI4-Lite slave models; fc32e1s_nano_fpga itself contains no memory)
  // ---------------------------------------------------------------------------
`ifdef USE_RTL_MEM
  axil_imem #(.DEPTH(IMEM_BYTES / 4)) u_imem (
    .clk (clk), .rst_n (rst_n),
    .s_axi_awaddr (i_awaddr),  .s_axi_awprot (i_awprot),  .s_axi_awvalid (i_awvalid),
    .s_axi_awready(i_awready), .s_axi_wdata  (i_wdata),   .s_axi_wstrb   (i_wstrb),
    .s_axi_wvalid (i_wvalid),  .s_axi_wready (i_wready),  .s_axi_bresp   (i_bresp),
    .s_axi_bvalid (i_bvalid),  .s_axi_bready (i_bready),  .s_axi_araddr  (i_araddr),
    .s_axi_arprot (i_arprot),  .s_axi_arvalid(i_arvalid), .s_axi_arready (i_arready),
    .s_axi_rdata  (i_rdata),   .s_axi_rresp  (i_rresp),   .s_axi_rvalid  (i_rvalid),
    .s_axi_rready (i_rready),
    // write port: no loader yet -- the TB fills the RAM hierarchically instead
    .wr_en_i (1'b0), .wr_be_i ('0), .wr_addr_i ('0), .wr_data_i ('0)
  );

`endif

`ifdef USE_RTL_MEM
  // The RTL memories wrap addresses beyond their depth instead of returning SLVERR,
  // so out-of-range accesses are flagged here.
  axil_dmem #(.DEPTH(DMEM_BYTES / 4)) u_dmem (
    .clk (clk), .rst_n (rst_n),
    .s_axi_awaddr (d_awaddr),  .s_axi_awprot (d_awprot),  .s_axi_awvalid (d_awvalid),
    .s_axi_awready(d_awready), .s_axi_wdata  (d_wdata),   .s_axi_wstrb   (d_wstrb),
    .s_axi_wvalid (d_wvalid),  .s_axi_wready (d_wready),  .s_axi_bresp   (d_bresp),
    .s_axi_bvalid (d_bvalid),  .s_axi_bready (d_bready),  .s_axi_araddr  (d_araddr),
    .s_axi_arprot (d_arprot),  .s_axi_arvalid(d_arvalid), .s_axi_arready (d_arready),
    .s_axi_rdata  (d_rdata),   .s_axi_rresp  (d_rresp),   .s_axi_rvalid  (d_rvalid),
    .s_axi_rready (d_rready)
  );

  logic map_err;
  assign map_err = (i_arvalid && i_arready && !(i_araddr >= IMEM_BASE && i_araddr < IMEM_BASE + IMEM_BYTES))
                || (d_arvalid && d_arready && !(d_araddr >= DMEM_BASE && d_araddr < DMEM_BASE + DMEM_BYTES))
                || (d_awvalid && d_awready && !(d_awaddr >= DMEM_BASE && d_awaddr < DMEM_BASE + DMEM_BYTES));
`else
  axil_mem_model #(.BASE(IMEM_BASE), .BYTES(IMEM_BYTES), .READ_ONLY(1'b1), .MAX_WAIT(MAX_WAIT)) u_imem (
    .clk (clk), .rst_n (rst_n),
    .s_axi_awaddr (i_awaddr),  .s_axi_awprot (i_awprot),  .s_axi_awvalid (i_awvalid),
    .s_axi_awready(i_awready), .s_axi_wdata  (i_wdata),   .s_axi_wstrb   (i_wstrb),
    .s_axi_wvalid (i_wvalid),  .s_axi_wready (i_wready),  .s_axi_bresp   (i_bresp),
    .s_axi_bvalid (i_bvalid),  .s_axi_bready (i_bready),  .s_axi_araddr  (i_araddr),
    .s_axi_arprot (i_arprot),  .s_axi_arvalid(i_arvalid), .s_axi_arready (i_arready),
    .s_axi_rdata  (i_rdata),   .s_axi_rresp  (i_rresp),   .s_axi_rvalid  (i_rvalid),
    .s_axi_rready (i_rready),
    .wr_o (), .wr_addr_o (), .wr_data_o (), .wr_strb_o ()
  );

  axil_mem_model #(.BASE(DMEM_BASE), .BYTES(DMEM_BYTES), .READ_ONLY(1'b0), .MAX_WAIT(MAX_WAIT)) u_dmem (
    .clk (clk), .rst_n (rst_n),
    .s_axi_awaddr (d_awaddr),  .s_axi_awprot (d_awprot),  .s_axi_awvalid (d_awvalid),
    .s_axi_awready(d_awready), .s_axi_wdata  (d_wdata),   .s_axi_wstrb   (d_wstrb),
    .s_axi_wvalid (d_wvalid),  .s_axi_wready (d_wready),  .s_axi_bresp   (d_bresp),
    .s_axi_bvalid (d_bvalid),  .s_axi_bready (d_bready),  .s_axi_araddr  (d_araddr),
    .s_axi_arprot (d_arprot),  .s_axi_arvalid(d_arvalid), .s_axi_arready (d_arready),
    .s_axi_rdata  (d_rdata),   .s_axi_rresp  (d_rresp),   .s_axi_rvalid  (d_rvalid),
    .s_axi_rready (d_rready),
    .wr_o (), .wr_addr_o (), .wr_data_o (), .wr_strb_o ()
  );

  logic map_err;
  assign map_err = 1'b0;   // the models answer out-of-range accesses with SLVERR
`endif

  // ---------------------------------------------------------------------------
  // Data-bus write monitor (works for any slave): AW and W may complete in different
  // cycles; dmem_wr is high in the cycle the second of the two handshakes happens.
  // ---------------------------------------------------------------------------
  logic        dw_aw_got, dw_w_got, dw_aw_fire, dw_w_fire;
  logic [31:0] dw_addr_q, dw_data_q;
  logic [3:0]  dw_strb_q;
  logic        dmem_wr;
  logic [31:0] dmem_wr_addr, dmem_wr_data;
  logic [3:0]  dmem_wr_strb;

  assign dw_aw_fire   = d_awvalid && d_awready;
  assign dw_w_fire    = d_wvalid  && d_wready;
  assign dmem_wr      = (dw_aw_got || dw_aw_fire) && (dw_w_got || dw_w_fire);
  assign dmem_wr_addr = dw_aw_got ? dw_addr_q : {d_awaddr[31:2], 2'b00};
  assign dmem_wr_data = dw_w_got  ? dw_data_q : d_wdata;
  assign dmem_wr_strb = dw_w_got  ? dw_strb_q : d_wstrb;

  always_ff @(posedge clk) begin
    if (!rst_n || dmem_wr) begin
      dw_aw_got <= 1'b0;
      dw_w_got  <= 1'b0;
    end else begin
      if (dw_aw_fire) begin dw_aw_got <= 1'b1; dw_addr_q <= {d_awaddr[31:2], 2'b00}; end
      if (dw_w_fire)  begin dw_w_got  <= 1'b1; dw_data_q <= d_wdata; dw_strb_q <= d_wstrb; end
    end
  end

  // ---------------------------------------------------------------------------
  // Protocol checkers
  // ---------------------------------------------------------------------------
  int unsigned i_proto_err, d_proto_err;

  axil_master_checker #(.NAME("m_axi_i")) u_chk_i (
    .clk (clk), .rst_n (rst_n),
    .awaddr (i_awaddr), .awprot (i_awprot), .awvalid (i_awvalid), .awready (i_awready),
    .wdata  (i_wdata),  .wstrb  (i_wstrb),  .wvalid  (i_wvalid),  .wready  (i_wready),
    .bvalid (i_bvalid), .bready (i_bready),
    .araddr (i_araddr), .arprot (i_arprot), .arvalid (i_arvalid), .arready (i_arready),
    .rvalid (i_rvalid), .rready (i_rready),
    .errors_o (i_proto_err)
  );

  axil_master_checker #(.NAME("m_axi_d")) u_chk_d (
    .clk (clk), .rst_n (rst_n),
    .awaddr (d_awaddr), .awprot (d_awprot), .awvalid (d_awvalid), .awready (d_awready),
    .wdata  (d_wdata),  .wstrb  (d_wstrb),  .wvalid  (d_wvalid),  .wready  (d_wready),
    .bvalid (d_bvalid), .bready (d_bready),
    .araddr (d_araddr), .arprot (d_arprot), .arvalid (d_arvalid), .arready (d_arready),
    .rvalid (d_rvalid), .rready (d_rready),
    .errors_o (d_proto_err)
  );

  // ---------------------------------------------------------------------------
  // rd's value for the tracer: the byte-serial ALU writes rd one byte lane per cycle
  // (`DUT.rf_be), so the value is collected over the instruction's cycles
  // ---------------------------------------------------------------------------
  logic [31:0] rd_acc_q, rd_trace;

  always_comb begin
    rd_trace = rd_acc_q;
    for (int b = 0; b < 4; b++) if (`DUT.rf_be[b]) rd_trace[8*b +: 8] = `DUT.rd_data[8*b +: 8];
  end

  always @(posedge clk) rd_acc_q <= rd_trace;

  // ---------------------------------------------------------------------------
  // Tracer: one line per committed instruction
  // ---------------------------------------------------------------------------
  fc32e1s_nano_fpga_tracer u_tracer (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .valid_i     (`DUT.commit),
    .pc_i        (`DUT.pc),
    .instr_i     (`DUT.instr),
    .rf_we_i     (`DUT.ctrl.rf_we),
    .rd_addr_i   (`DUT.instr[11:7]),
    .rd_wdata_i  (rd_trace),
    .mem_re_i    (`DUT.ctrl.mem_re),
    .mem_we_i    (`DUT.ctrl.mem_we),
    .mem_addr_i  (32'(`DUT.lsu_addr)),
    .mem_wdata_i (d_wdata),
    .mem_be_i    (d_wstrb)
  );

  // ---------------------------------------------------------------------------
  // Result reporting
  // ---------------------------------------------------------------------------
  bit          done = 1'b0;
  bit          tohost_seen = 1'b0;
  logic [31:0] tohost_word;
  int unsigned cyc = 0, instret = 0, since_commit = 0;
  logic        tohost_now;
  logic [31:0] tohost_value;

  assign tohost_now   = dmem_wr && dmem_wr_addr == TOHOST_ADDR && dmem_wr_strb == 4'hF;
  assign tohost_value = tohost_now ? dmem_wr_data : tohost_word;

  task automatic finish_tb(input string verdict);
    if (done) return;
    done = 1'b1;
    $display("[TB] SONUC: %s", verdict);
    $display("[TB] cevrim=%0d buyruk=%0d CPI=%0.2f bekleme=%0d", cyc, instret,
             instret ? real'(cyc) / instret : 0.0, MAX_WAIT);
    // let the tracer write this edge's line before ending
    @(negedge clk);
    $finish;
  endtask

  always @(posedge clk) begin
    if (rst_n && !done) begin
      cyc <= cyc + 1;
      if (`DUT.commit) begin instret <= instret + 1; since_commit <= 0; end
      else              since_commit <= since_commit + 1;

      // The tohost write may be reported in the same cycle as the store's commit
      // (zero-wait slave), so look at the current write as well as a remembered one.
      if (tohost_now) begin
        tohost_seen <= 1'b1;
        tohost_word <= dmem_wr_data;
      end

      if (map_err)
        finish_tb($sformatf("HATA haritalanmamis erisim (RTL bellek) pc=%08x", `DUT.pc));
      else if (i_proto_err || d_proto_err)
        finish_tb($sformatf("HATA AXI protokol ihlali (i=%0d d=%0d)", i_proto_err, d_proto_err));
      else if (bus_err)
        finish_tb($sformatf("HATA bus hatasi (SLVERR/DECERR) pc=%08x", `DUT.pc));
      else if (illegal)
        finish_tb($sformatf("HATA illegal buyruk %08x pc=%08x", `DUT.instr, `DUT.pc));
      else if (halt)
        finish_tb($sformatf("HATA ECALL/EBREAK pc=%08x (fc32e1s_nano_fpga tuzak desteklemiyor)", `DUT.pc));
      // The tohost store commits when its B response arrives, after the write itself.
      // Finish on that commit so the trace contains the store line.
      else if ((tohost_seen || tohost_now) && `DUT.commit) begin
        if (tohost_value == 32'h1) finish_tb("GECTI (tohost=0x00000001)");
        else finish_tb($sformatf("HATA blok x30=%0d (tohost=0x%08x)", tohost_value >> 1, tohost_value));
      end
      else if (since_commit >= STALL_LIMIT)
        finish_tb($sformatf("HATA kilitlenme: %0d cevrim commit yok, pc=%08x (AXI deadlock?)",
                            STALL_LIMIT, `DUT.pc));
      else if (cyc >= TIMEOUT)
        finish_tb($sformatf("TIMEOUT (%0d cevrim, tohost'a hic yazilmadi)", TIMEOUT));
    end
  end

  // ---------------------------------------------------------------------------
  // Load + reset
  // ---------------------------------------------------------------------------
  logic [7:0] ibytes [IMEM_BYTES];
  logic [7:0] dbytes [DMEM_BYTES];

  initial begin
    int fd;
`ifdef USE_RTL_MEM
    $display("[TB] cekirdek: fc32e1s_nano_fpga AXI4-Lite, RTL bellekler");
`else
    $display("[TB] cekirdek: fc32e1s_nano_fpga AXI4-Lite, bekleme durumu MAX_WAIT=%0d", MAX_WAIT);
`endif
    // The hex files are byte-addressed (objcopy -O verilog): load into byte arrays,
    // then copy into whichever memory is instantiated.
    foreach (ibytes[i]) ibytes[i] = 8'h00;
    foreach (dbytes[i]) dbytes[i] = 8'h00;
    $readmemh("imem.hex", ibytes);
    $display("[TB] IMEM yuklendi: imem.hex");
    fd = $fopen("dmem.hex", "r");
    if (fd != 0) begin
      $fclose(fd);
      $readmemh("dmem.hex", dbytes);
      $display("[TB] DMEM yuklendi: dmem.hex");
    end
`ifdef USE_RTL_MEM
    $display("[TB] bellek: common/rtl axil_imem + axil_dmem (1 cevrim okuma)");
    foreach (u_imem.u_ram.mem[w]) u_imem.u_ram.mem[w] = {ibytes[4*w+3], ibytes[4*w+2], ibytes[4*w+1], ibytes[4*w]};
    foreach (u_dmem.u_ram.mem[w]) u_dmem.u_ram.mem[w] = {dbytes[4*w+3], dbytes[4*w+2], dbytes[4*w+1], dbytes[4*w]};
`else
    foreach (u_imem.mem[i]) u_imem.mem[i] = ibytes[i];
    foreach (u_dmem.mem[i]) u_dmem.mem[i] = dbytes[i];
`endif

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

endmodule
