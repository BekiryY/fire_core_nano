# vivado_project.tcl -- creates a Vivado project of fc32e1s_nano_fpga (open the .xpr in the IDE),
# and builds it when asked. The project folders are generated (not committed): this script is
# the source.
#
#   vivado -mode batch -source vivado_project.tcl -tclargs core   # the core alone, out of context
#   vivado -mode batch -source vivado_project.tcl -tclargs top    # the board top (default)
#     -> prj/fc32e1s_nano_fpga_<core|top>/fc32e1s_nano_fpga_<core|top>.xpr
#
#   RUN=syn ...          # and synthesize
#   RUN=1 ...            # and synthesize + implement (top; the core alone: synthesis only)
#   PART=<part> ...      # default xc7z020clg400-1 (Artix-7 fabric); e.g. xc7a35tcpg236-1
#   PERIOD=8.0 ...       # clock period in ns (default 10)
#   PRJ_DIR=<dir> ...    # where the project goes (default appl/vivado/prj)
#
# core: rtl/ with core.xdc, top fc32e1s_nano_fpga_core, synthesized -mode out_of_context (its
#   AXI4-Lite ports are not pins).
# top: rtl/ + example/subsystem/ (core + 2 KiB block RAM + LED / counter peripheral) with
#   top.xdc, top fc32e1s_nano_fpga_top. The RAM starts with the program image of
#   bench/cpi_test/build/nano/cpi_test_{0..3}.hex (build it first: bench/cpi_test/build.sh nano),
#   copied into the project. Pins are not constrained (no bitstream until you add them).
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../..]
set name fc32e1s_nano_fpga
proc env_or {var default} { expr {[info exists ::env($var)] ? $::env($var) : $default} }

set target [expr {[llength $argv] ? [lindex $argv 0] : "top"}]
if {$target ni {core top}} { error "target $target: core or top" }
set part   [env_or PART xc7z020clg400-1]
set period [env_or PERIOD 10.000]
set run    [env_or RUN 0]
set prj    ${name}_$target
set pdir   [file normalize [env_or PRJ_DIR $here/prj]/$prj]

set files [list $core/rtl/${name}_pkg.sv]
foreach f [lsort [glob $core/rtl/${name}_*.sv]] {
  if {![string match *_pkg.sv $f]} { lappend files $f }
}
if {$target eq "top"} {
  foreach f {ram subsystem top} { lappend files $core/example/subsystem/${name}_$f.sv }
}

create_project $prj $pdir -part $part -force
add_files -norecurse $files
set_property file_type SystemVerilog [get_files *.sv]
set_property top ${name}_$target [current_fileset]

# own copy of the constraint with the requested period
set h [open $here/$target.xdc r]; set xdc [read $h]; close $h
regsub {\-period [0-9.]+} $xdc "-period $period" xdc
set h [open $pdir/$target.xdc w]; puts -nonewline $h $xdc; close $h
add_files -fileset constrs_1 -norecurse $pdir/$target.xdc

if {$target eq "core"} {
  set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} \
    -objects [get_runs synth_1]
} else {
  set hex {}
  foreach i {0 1 2 3} {
    set f [file normalize $core/../../bench/cpi_test/build/nano/cpi_test_$i.hex]
    if {![file exists $f]} { error "$f not found: run bench/cpi_test/build.sh nano first" }
    file copy -force $f $pdir/
    lappend hex $pdir/cpi_test_$i.hex
  }
  add_files -norecurse $hex
  set_property file_type {Memory Initialization Files} [get_files *.hex]
}
puts "PROJECT $pdir/$prj.xpr ($part, $period ns)"

if {$run eq "0"} { close_project; return }
launch_runs synth_1; wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
set step synth_1
if {$run eq "1" && $target eq "top"} {
  launch_runs impl_1 -to_step route_design; wait_on_run impl_1
  if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }
  set step impl_1
}
open_run $step
report_utilization -file $pdir/util_$step.rpt
report_timing_summary -file $pdir/timing_$step.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "RESULT $prj $step WNS $wns est_MHz [format %.1f [expr {1000.0 / ($period - $wns)}]]"
close_project
