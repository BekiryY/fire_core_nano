# serv_core.tcl -- Vivado out-of-context synthesis of SERV alone: serv_rf_top (core + its register
# file RAM) with RESET_PC = 0, WITH_CSR = 0, the configuration of the FPGA board top
# (example/subsystem/serv_fpga_top.sv) and of the comparison. Same set-up as
# cores/fc32e1s_nano_fpga/appl/vivado/fc32e1s_nano_fpga_core.tcl: core.xdc 10 ns,
# xc7z020clg400-1 (Artix-7 fabric).
#   vivado -mode batch -nojournal -nolog -source serv_core.tcl [-tclargs <directive>]
#   directive: AreaOptimized_high (default, the comparison's) or Default; reports in ../../build/vivado/<directive>/
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../..]
set directive [expr {[llength $argv] ? [lindex $argv 0] : "AreaOptimized_high"}]
set out $core/build/vivado/$directive
file mkdir $out
set files {}
foreach f {alu bufreg bufreg2 csr ctrl decode immdec mem_if rf_if rf_ram_if rf_ram state aligner
           compdec top rf_top} { lappend files $core/rtl/serv_$f.v }
read_verilog $files
read_xdc -mode out_of_context $here/core.xdc
synth_design -top serv_rf_top -part xc7z020clg400-1 -mode out_of_context -directive $directive \
  -generic RESET_PC=0 -generic WITH_CSR=0
report_utilization -file $out/util.rpt
report_utilization -hierarchical -file $out/util_hier.rpt
report_timing_summary -file $out/timing.rpt
set_units -power uW
report_power -file $out/power.rpt                ;# vectorless (default toggle rates), at the 10 ns constraint
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "RESULT serv $directive WNS $wns est_MHz [format %.1f [expr {1000.0 / (10.0 - $wns)}]]"
