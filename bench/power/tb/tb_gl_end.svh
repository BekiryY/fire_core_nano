// tb_gl_end.svh -- shared end of tb_gl_nano.sv / tb_gl_serv.sv: reset for 4 cycles (saif.tcl
// starts the SAIF window right after the release), run to the program's KDONE write, print the
// window (cycles, instructions retired, time), $stop (saif.tcl closes the SAIF there).

  realtime t0;
  longint  c0, i0, cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  initial begin
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    t0 = $realtime;
    c0 = cyc;
    i0 = u_mon.ins;
    fork
      wait (done);
      begin repeat (1_000_000) @(posedge clk); $display("  TIMEOUT"); end
    join_any
    $display("WINDOW cycles %0d instr %0d time_ns %.3f period_ns %.4f", cyc - c0, u_mon.ins - i0,
             $realtime - t0, PERIOD);
    if (pass) $display("PASS");
    else      $display("FAIL");
    $stop;
  end
