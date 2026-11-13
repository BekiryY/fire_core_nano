# fc32e1s_nano_fpga_core.tcl -- Vivado out-of-context synthesis of the core alone (rtl/fc32e1s_nano_fpga_core.sv as top),
# core.xdc 10 ns. No Artix-7 part is installed with Vivado 2025.2 here: xc7z020clg400-1, whose
# programmable logic is Artix-7 fabric (LUT6 / CARRY4 / LUTRAM; -1 timing only approximate).
#   vivado -mode batch -nojournal -nolog -source fc32e1s_nano_fpga_core.tcl [-tclargs <directive>]
#   directive: AreaOptimized_high (default, the comparison's) or Default; reports in build/vivado/<directive>/
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../..]
set name fc32e1s_nano_fpga
set directive [expr {[llength $argv] ? [lindex $argv 0] : "AreaOptimized_high"}]
set out $core/build/vivado/$directive
file mkdir $out
set files [list $core/rtl/${name}_pkg.sv]
foreach f [lsort [glob $core/rtl/${name}_*.sv]] {
  if {![string match *_pkg.sv $f]} { lappend files $f }
}
read_verilog -sv $files
read_xdc -mode out_of_context $here/core.xdc
synth_design -top ${name}_core -part xc7z020clg400-1 -mode out_of_context -directive $directive
report_utilization -file $out/util.rpt
report_utilization -hierarchical -file $out/util_hier.rpt
report_timing_summary -file $out/timing.rpt
set_units -power uW
report_power -file $out/power.rpt                ;# vectorless (default toggle rates), at the 10 ns constraint
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "RESULT $name $directive WNS $wns est_MHz [format %.1f [expr {1000.0 / (10.0 - $wns)}]]"
