# fc32e1s_nano_asic_core.tcl -- Gowin project: the core alone (rtl/fc32e1s_nano_asic_core.sv as top, its
# two AXI4-Lite masters on pins; core.sdc 10 ns). Same set-up as fc32e1s_nano_fpga (core as
# top, opt_goal area) to compare the two on GW2A (prj/impl/, where the IDE keeps them, is not
# committed).
#   gw_sh fc32e1s_nano_asic_core.tcl          # -> core/prj/fc32e1s_nano_asic/fc32e1s_nano_asic.gprj
#   RUN=syn gw_sh fc32e1s_nano_asic_core.tcl  # and synthesize it (more ports than the 202 I/Os of the
#                                         # GW2A-18: no place & route); options:
#                                         # ../gw_project.tcl
set here [file dirname [file normalize [info script]]]
set core [file normalize $here/../../..]
source $here/../gw_project.tcl
set files [list $core/rtl/fc32e1s_nano_asic_pkg.sv]
foreach f [lsort [glob $core/rtl/fc32e1s_nano_asic_*.sv]] {
  if {![string match *_pkg.sv $f]} { lappend files $f }
}
lappend files $here/core.sdc
fc32e1s_nano_asic_gw_project fc32e1s_nano_asic $here fc32e1s_nano_asic_core $files
