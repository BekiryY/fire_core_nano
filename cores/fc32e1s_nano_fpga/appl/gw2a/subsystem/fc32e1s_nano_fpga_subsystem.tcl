# fc32e1s_nano_fpga_subsystem.tcl -- Gowin project: the CPU subsystem's board top
# (example/subsystem/fc32e1s_nano_fpga_top.sv: core + 2 KiB block RAM + LED / counter
# peripheral; subsystem.sdc 10 ns). The RAM starts with the program image of
# example/subsystem/sw/build/cpi_test_{0..3}.hex (build it first: sw/build.sh), copied into the
# project folder, where the top's INIT_FILE "cpi_test_" finds it. Pins are not constrained.
#   gw_sh fc32e1s_nano_fpga_subsystem.tcl          # -> subsystem/prj/fc32e1s_nano_fpga_subsystem/
#   RUN=1 gw_sh fc32e1s_nano_fpga_subsystem.tcl    # and build it (synthesis + place & route);
#                                                  # options: ../gw_project.tcl
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../../..]
set sub  $core/example/subsystem
source $here/../gw_project.tcl
set files [list $core/rtl/fc32e1s_nano_fpga_pkg.sv]
foreach f [lsort [glob $core/rtl/fc32e1s_nano_fpga_*.sv]] {
  if {![string match *_pkg.sv $f]} { lappend files $f }
}
foreach f {ram subsystem top} { lappend files $sub/fc32e1s_nano_fpga_$f.sv }
lappend files $here/subsystem.sdc

set name fc32e1s_nano_fpga_subsystem
set pdir [file normalize $here/prj]
if {[info exists ::env(PRJ_DIR)]} { set pdir [file normalize $::env(PRJ_DIR)] }
file mkdir $pdir/$name
foreach i {0 1 2 3} {
  set hex $sub/sw/build/cpi_test_$i.hex
  if {![file exists $hex]} { error "$hex not found: run example/subsystem/sw/build.sh first" }
  file copy -force $hex $pdir/$name/
}
fc32e1s_nano_fpga_gw_project $name $here fc32e1s_nano_fpga_top $files
