// ============================================================================
//  fc32e1s_nano_asic_tracer.sv -- retired-instruction trace for Spike ISS comparison
//
//  Writes one line per retired instruction in the same layout as
//  cv32e40p_tracer, so spike_iss/checker.py and coverage.py parse it unchanged:
//
//    <time> <cycle> <pc> <instr> <mnemonic> [xN=<rd value>] [PA:<addr>] [WD:<wdata> BE:<be>]
//
//    xN=      register write (x0 writes omitted, as spike does)
//    PA:      byte address of a load/store (NOT the word-aligned bus address)
//    WD:/BE:  store bus data and byte enables; checker.py normalises them back
//             to the architectural store value
//
//  fc32e1s_nano_asic is single-stage: everything sampled at a rising edge belongs to the
//  instruction that retires at that edge, so no pipeline bookkeeping is needed.
//  The mnemonic is decoded here from the instruction word, independently of
//  fc32e1s_nano_asic_decoder, so a decoder bug cannot hide itself in the trace.
// ============================================================================

module fc32e1s_nano_asic_tracer #(
  parameter string FILE = "trace_fc32e1s_nano_asic.log"
) (
  input logic        clk_i,
  input logic        rst_ni,
  input logic        valid_i,      // instruction retires this cycle

  input logic [31:0] pc_i,
  input logic [31:0] instr_i,

  input logic        rf_we_i,
  input logic [4:0]  rd_addr_i,
  input logic [31:0] rd_wdata_i,

  input logic        mem_re_i,
  input logic        mem_we_i,
  input logic [31:0] mem_addr_i,   // byte address
  input logic [31:0] mem_wdata_i,  // bus data (lane-replicated)
  input logic [3:0]  mem_be_i
);

  function automatic string mnemonic(input logic [31:0] i);
    logic [2:0] f3 = i[14:12];
    logic [6:0] f7 = i[31:25];
    case (i[6:0])
      7'b0110111: return "lui";
      7'b0010111: return "auipc";
      7'b1101111: return "jal";
      7'b1100111: return "jalr";
      7'b1100011: case (f3)
                    3'b000: return "beq";  3'b001: return "bne";
                    3'b100: return "blt";  3'b101: return "bge";
                    3'b110: return "bltu"; 3'b111: return "bgeu";
                    default: return "unknown";
                  endcase
      7'b0000011: case (f3)
                    3'b000: return "lb";  3'b001: return "lh";  3'b010: return "lw";
                    3'b100: return "lbu"; 3'b101: return "lhu";
                    default: return "unknown";
                  endcase
      7'b0100011: case (f3)
                    3'b000: return "sb"; 3'b001: return "sh"; 3'b010: return "sw";
                    default: return "unknown";
                  endcase
      7'b0010011: case (f3)
                    3'b000: return "addi";  3'b010: return "slti"; 3'b011: return "sltiu";
                    3'b100: return "xori";  3'b110: return "ori";  3'b111: return "andi";
                    3'b001: return "slli";
                    3'b101: return f7[5] ? "srai" : "srli";
                    default: return "unknown";
                  endcase
      7'b0110011: case (f3)
                    3'b000: return f7[5] ? "sub" : "add";
                    3'b001: return "sll";  3'b010: return "slt"; 3'b011: return "sltu";
                    3'b100: return "xor";
                    3'b101: return f7[5] ? "sra" : "srl";
                    3'b110: return "or";   3'b111: return "and";
                    default: return "unknown";
                  endcase
      7'b0001111: return "fence";
      7'b1110011: return (i == 32'h0010_0073) ? "ebreak" : (i == 32'h0000_0073) ? "ecall" : "unknown";
      default:    return "unknown";
    endcase
  endfunction

  int          fd;
  int unsigned cycle;

  initial begin
    fd = $fopen(FILE, "w");
    if (fd == 0) $fatal(1, "fc32e1s_nano_asic_tracer: cannot open %s", FILE);
    $fwrite(fd, "Time Cycle PC Instr Mnemonic Effects\n");
  end

  final begin
    if (fd != 0) $fclose(fd);
  end

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      cycle <= 0;
    end else begin
      cycle <= cycle + 1;
      if (valid_i) begin
        $fwrite(fd, "%0d %0d %08x %08x %-7s", $time, cycle, pc_i, instr_i, mnemonic(instr_i));
        if (rf_we_i && rd_addr_i != 5'd0) $fwrite(fd, " x%0d=%08x", rd_addr_i, rd_wdata_i);
        if (mem_re_i || mem_we_i)         $fwrite(fd, " PA:%08x", mem_addr_i);
        if (mem_we_i)                     $fwrite(fd, " WD:%08x BE:%1x", mem_wdata_i, mem_be_i);
        $fwrite(fd, "\n");
        $fflush(fd);
      end
    end
  end

endmodule
