// axil_mem_model.sv
// AXI4-Lite slave memory model for testbenches (byte array, not synthesisable).
//
//   - one outstanding write; MAX_RD outstanding reads (default 1), answered in order
//   - random wait states (MAX_WAIT > 0):
//       ARREADY / AWREADY / WREADY are random each cycle (legal: a slave may drop READY
//       before the handshake), AW and W are accepted independently, and RVALID/BVALID
//       come 0..MAX_WAIT cycles after the request
//     For each new transaction a channel also picks at random whether READY may rise
//     before VALID or only after VALID has been seen. The second mode is legal slave
//     behaviour and deadlocks a master that (illegally) waits for READY before raising
//     VALID -- without it such a master bug passes unnoticed.
//   - MAX_WAIT = 0: READY always high when idle, response in the next cycle
//   - FIXED_WAIT >= 0 (overrides MAX_WAIT): READY always high when idle and every response
//     exactly FIXED_WAIT cycles later than with MAX_WAIT = 0 (deterministic latency, used by
//     the benchmark flow common/tb/bench); with MAX_RD > 1 the reads stay pipelined
//   - MAX_RD > 1 (pipelined reads): a new AR is accepted while up to MAX_RD - 1 reads are
//     waiting or being answered; ARREADY may stay high across handshakes, so with
//     MAX_WAIT = 0 there is one read per cycle (block-RAM slave timing)
//   - SLVERR for addresses outside [BASE, BASE+BYTES) and for writes when READ_ONLY
//   - the address is used word-aligned; WSTRB selects the bytes
//   - DATA_W = 32 or 64 (bus width; a "word" is DATA_W bits), ADDR_W = address width
//
// The array `mem` is meant to be loaded hierarchically ($readmemh) by the testbench.
// wr_* outputs pulse for one cycle when a write is applied (for tohost-style monitors).

module axil_mem_model #(
  parameter int                ADDR_W    = 32,
  parameter int                DATA_W    = 32,     // 32 or 64
  parameter logic [ADDR_W-1:0] BASE      = '0,
  parameter int                BYTES     = 4096,
  parameter bit                READ_ONLY = 1'b0,
  parameter int                MAX_WAIT  = 3,
  parameter int                FIXED_WAIT = -1,    // >= 0: fixed wait states instead of random
  parameter int                MAX_RD    = 1      // reads in flight (accepted, R not yet done)
) (
  input  logic                clk,
  input  logic                rst_n,

  input  logic [ADDR_W-1:0]   s_axi_awaddr,
  input  logic [2:0]          s_axi_awprot,
  input  logic                s_axi_awvalid,
  output logic                s_axi_awready,
  input  logic [DATA_W-1:0]   s_axi_wdata,
  input  logic [DATA_W/8-1:0] s_axi_wstrb,
  input  logic                s_axi_wvalid,
  output logic                s_axi_wready,
  output logic [1:0]          s_axi_bresp,
  output logic                s_axi_bvalid,
  input  logic                s_axi_bready,
  input  logic [ADDR_W-1:0]   s_axi_araddr,
  input  logic [2:0]          s_axi_arprot,
  input  logic                s_axi_arvalid,
  output logic                s_axi_arready,
  output logic [DATA_W-1:0]   s_axi_rdata,
  output logic [1:0]          s_axi_rresp,
  output logic                s_axi_rvalid,
  input  logic                s_axi_rready,

  output logic                wr_o,       // a write was applied this cycle
  output logic [ADDR_W-1:0]   wr_addr_o,  // word address
  output logic [DATA_W-1:0]   wr_data_o,
  output logic [DATA_W/8-1:0] wr_strb_o
);

  localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;
  localparam int NB  = DATA_W / 8;       // bytes per word
  localparam int LSB = $clog2(NB);       // address bits below the word

  logic [7:0] mem [BYTES];

  // word-aligned address
  function automatic logic [ADDR_W-1:0] align(input logic [ADDR_W-1:0] a);
    return {a[ADDR_W-1:LSB], {LSB{1'b0}}};
  endfunction

  function automatic bit in_range(input logic [ADDR_W-1:0] a);
    return (a >= BASE) && (a < BASE + BYTES);
  endfunction

  localparam bit RANDOM = (FIXED_WAIT < 0) && (MAX_WAIT > 0);

  function automatic int unsigned wait_cycles();
    if (FIXED_WAIT >= 0) return FIXED_WAIT;
    return RANDOM ? $urandom_range(MAX_WAIT, 0) : 0;
  endfunction

  function automatic bit rand_ready();
    return RANDOM ? ($urandom_range(1, 0) == 1) : 1'b1;
  endfunction

  // next-cycle READY for one channel: in wait-for-valid mode only once VALID is seen
  function automatic bit next_ready(input bit wait_for_valid, input bit valid);
    return rand_ready() && (!wait_for_valid || valid);
  endfunction

  function automatic bit pick_wait_for_valid();
    return RANDOM ? ($urandom_range(1, 0) == 1) : 1'b0;
  endfunction

  // ---------------------------------------------------------------------------
  // Read: AR -> 0..MAX_WAIT idle cycles -> R
  // With 0 wait cycles RVALID rises in the cycle right after the AR handshake, the
  // earliest AXI allows.
  // ---------------------------------------------------------------------------
  task automatic drive_rdata(input logic [ADDR_W-1:0] a);
    if (in_range(a)) begin
      automatic int unsigned i = a - BASE;
      for (int b = 0; b < NB; b++) s_axi_rdata[8*b +: 8] <= mem[i+b];
      s_axi_rresp <= OKAY;
    end else begin
      s_axi_rdata <= {(DATA_W/32){32'hDEAD_BEEF}};
      s_axi_rresp <= SLVERR;
    end
  endtask

  generate if (MAX_RD <= 1) begin : g_rd1
    logic        rd_busy;
    int unsigned rd_wait;
    logic [ADDR_W-1:0] rd_addr;
    logic        ar_rdy;
    logic        ar_wv;      // this transaction: READY only after VALID

    assign s_axi_arready = !rd_busy && ar_rdy;

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        rd_busy      <= 1'b0;
        ar_rdy       <= 1'b0;
        ar_wv        <= 1'b0;
        s_axi_rvalid <= 1'b0;
        s_axi_rdata  <= '0;
        s_axi_rresp  <= OKAY;
      end else begin
        ar_rdy <= next_ready(ar_wv, s_axi_arvalid);
        if (s_axi_arvalid && s_axi_arready) begin
          automatic logic [ADDR_W-1:0] a = align(s_axi_araddr);
          automatic int unsigned  w = wait_cycles();
          ar_wv  <= pick_wait_for_valid();
          ar_rdy <= 1'b0;
          rd_busy <= 1'b1;
          rd_addr <= a;
          if (w == 0) begin
            s_axi_rvalid <= 1'b1;
            drive_rdata(a);
          end else begin
            rd_wait <= w - 1;
          end
        end else if (rd_busy && !s_axi_rvalid) begin
          if (rd_wait == 0) begin
            s_axi_rvalid <= 1'b1;
            drive_rdata(rd_addr);
          end else begin
            rd_wait <= rd_wait - 1;
          end
        end else if (s_axi_rvalid && s_axi_rready) begin
          s_axi_rvalid <= 1'b0;
          rd_busy      <= 1'b0;
        end
      end
    end
  end else begin : g_rdn
    // Pipelined reads: accepted requests wait in rq (address, earliest cycle for RVALID),
    // the oldest is answered once its wait is over and the previous R has been accepted.
    typedef struct { logic [ADDR_W-1:0] addr; longint unsigned due; } rd_req_t;
    rd_req_t         rq [$];
    longint unsigned now;
    int unsigned     n_rd;     // accepted reads not yet completed (incl. the one on R)
    logic            ar_rdy;
    logic            ar_wv;    // this transaction: READY only after VALID

    assign s_axi_arready = (n_rd < MAX_RD) && ar_rdy;

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        rq.delete();
        now          <= 0;
        n_rd         <= 0;
        ar_rdy       <= 1'b0;
        ar_wv        <= 1'b0;
        s_axi_rvalid <= 1'b0;
        s_axi_rdata  <= '0;
        s_axi_rresp  <= OKAY;
      end else begin
        automatic bit ar_fire = s_axi_arvalid && s_axi_arready;
        automatic bit r_fire  = s_axi_rvalid && s_axi_rready;
        automatic rd_req_t req;
        now    <= now + 1;
        ar_rdy <= next_ready(ar_wv, s_axi_arvalid);
        if (ar_fire) begin
          // with 0 wait cycles RVALID can rise in the next cycle
          req.addr = align(s_axi_araddr);
          req.due  = now + 1 + wait_cycles();
          rq.push_back(req);
          ar_wv <= pick_wait_for_valid();
        end
        n_rd <= n_rd + ar_fire - r_fire;
        if (!s_axi_rvalid || r_fire) begin
          if (rq.size() > 0 && rq[0].due <= now + 1) begin
            s_axi_rvalid <= 1'b1;
            drive_rdata(rq[0].addr);
            void'(rq.pop_front());
          end else begin
            s_axi_rvalid <= 1'b0;
          end
        end
      end
    end
  end endgenerate

  // ---------------------------------------------------------------------------
  // Write: AW and W independently -> apply when the second one arrives
  //        -> 0..MAX_WAIT idle cycles -> B
  // With 0 wait cycles BVALID rises in the cycle right after the last of AW/W.
  // ---------------------------------------------------------------------------
  logic        aw_got, w_got, wr_busy;
  int unsigned wr_wait;
  logic [ADDR_W-1:0]   aw_addr;
  logic [DATA_W-1:0]   w_data;
  logic [DATA_W/8-1:0] w_strb;
  logic        aw_rdy, w_rdy;
  logic        aw_wv, w_wv;   // this transaction: READY only after VALID
  logic        aw_now, w_now;

  assign s_axi_awready = !wr_busy && !aw_got && aw_rdy;
  assign s_axi_wready  = !wr_busy && !w_got  && w_rdy;
  assign aw_now        = s_axi_awvalid && s_axi_awready;
  assign w_now         = s_axi_wvalid  && s_axi_wready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_got       <= 1'b0;
      w_got        <= 1'b0;
      wr_busy      <= 1'b0;
      aw_rdy       <= 1'b0;
      w_rdy        <= 1'b0;
      aw_wv        <= 1'b0;
      w_wv         <= 1'b0;
      s_axi_bvalid <= 1'b0;
      s_axi_bresp  <= OKAY;
      wr_o         <= 1'b0;
    end else begin
      aw_rdy <= next_ready(aw_wv, s_axi_awvalid);
      w_rdy  <= next_ready(w_wv,  s_axi_wvalid);
      if (aw_now) begin aw_wv <= pick_wait_for_valid(); aw_rdy <= 1'b0; end
      if (w_now)  begin w_wv  <= pick_wait_for_valid(); w_rdy  <= 1'b0; end
      wr_o   <= 1'b0;

      if (!wr_busy && (aw_got || aw_now) && (w_got || w_now)) begin
        // the second half arrives now (or both together): apply the write
        automatic logic [ADDR_W-1:0]   a  = aw_got ? aw_addr : align(s_axi_awaddr);
        automatic logic [DATA_W-1:0]   d  = w_got  ? w_data  : s_axi_wdata;
        automatic logic [DATA_W/8-1:0] st = w_got  ? w_strb  : s_axi_wstrb;
        automatic int unsigned w  = wait_cycles();
        aw_got  <= 1'b0;
        w_got   <= 1'b0;
        wr_busy <= 1'b1;
        if (in_range(a) && !READ_ONLY) begin
          automatic int unsigned i = a - BASE;
          for (int b = 0; b < NB; b++)
            if (st[b]) mem[i+b] <= d[8*b +: 8];
          s_axi_bresp <= OKAY;
          wr_o        <= 1'b1;
          wr_addr_o   <= a;
          wr_data_o   <= d;
          wr_strb_o   <= st;
        end else begin
          s_axi_bresp <= SLVERR;
        end
        if (w == 0) s_axi_bvalid <= 1'b1;
        else        wr_wait      <= w - 1;
      end else begin
        if (aw_now) begin aw_got <= 1'b1; aw_addr <= align(s_axi_awaddr); end
        if (w_now)  begin w_got  <= 1'b1; w_data  <= s_axi_wdata; w_strb <= s_axi_wstrb; end
        if (wr_busy && !s_axi_bvalid) begin
          if (wr_wait == 0) s_axi_bvalid <= 1'b1;
          else              wr_wait      <= wr_wait - 1;
        end else if (s_axi_bvalid && s_axi_bready) begin
          s_axi_bvalid <= 1'b0;
          wr_busy      <= 1'b0;
        end
      end
    end
  end

endmodule
