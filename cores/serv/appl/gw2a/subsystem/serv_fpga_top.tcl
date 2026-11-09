# serv_fpga_top.tcl -- Gowin project: SERV on the nano subsystem's board top
# (example/subsystem/serv_fpga_top.sv: serv_rf_top + the 2 KiB block RAM of fc32e1s_nano_fpga +
# LED / counter peripheral; subsystem.sdc 10 ns), built with the same strategy as the nano
# (cores/fc32e1s_nano_fpga/appl/gw2a/gw_project.tcl) for comparing the two. The RAM starts with
# bench/cpi_test/build/rv32e/cpi_test_{0..3}.hex (build it first: bench/cpi_test/build.sh rv32e),
# copied into the project folder. Pins are not constrained.
#   gw_sh serv_fpga_top.tcl          # -> subsystem/prj/serv_fpga_top/
#   RUN=1 gw_sh serv_fpga_top.tcl    # and build it (synthesis + place & route)
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../../..]
set repo [file normalize $core/../..]
source $repo/cores/fc32e1s_nano_fpga/appl/gw2a/gw_project.tcl
set files {}
foreach f {aligner alu bufreg bufreg2 compdec csr ctrl decode immdec mem_if rf_if rf_ram rf_ram_if
           state top rf_top} { lappend files $core/rtl/serv_$f.v }
lappend files $repo/cores/fc32e1s_nano_fpga/example/subsystem/fc32e1s_nano_fpga_ram.sv
lappend files $core/example/subsystem/serv_fpga_top.sv
lappend files $here/subsystem.sdc

set name serv_fpga_top
set pdir [file normalize $here/prj]
if {[info exists ::env(PRJ_DIR)]} { set pdir [file normalize $::env(PRJ_DIR)] }
file mkdir $pdir/$name
foreach i {0 1 2 3} {
  set hex [file normalize $repo/bench/cpi_test/build/rv32e/cpi_test_$i.hex]
  if {![file exists $hex]} { error "$hex not found: run bench/cpi_test/build.sh rv32e first" }
  file copy -force $hex $pdir/$name/
}
fc32e1s_nano_fpga_gw_project $name $here serv_fpga_top $files
