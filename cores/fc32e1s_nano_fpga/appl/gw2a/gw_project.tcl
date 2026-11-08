# gw_project.tcl -- shared by the GW2A project scripts of fc32e1s_nano_fpga (core/): creates a Gowin
# IDE project (.gprj + impl/<name>_process_config.json) with the strategy below, and builds it
# when asked.
#
#   gw_sh <script>.tcl                  # create <flow>/prj/<name>/<name>.gprj (open it in the IDE)
#   RUN=1 gw_sh <script>.tcl            # create and build (synthesis + place & route)
#   RUN=syn gw_sh <script>.tcl          # create and synthesize only
#   OPT_GOAL=timing ...                 # optimization goal (default area)
#   MAP_OPTION=4 ...                    # map option (default 1)
#   PERIOD=8.0 ...                      # clock period: the project gets its own copy of the .sdc
#   PRJ_DIR=<dir> ...                   # where the project goes (default <flow>/prj)
#
# Strategy: the user's standard fc32 GW2A one (place 2, route 1, clock route order 1, route maxfan
# 12, hold correction, synthesis max fanout 12 -- -maxfan is silently ignored, -max_fanout works)
# with opt_goal area: for the tiny cores timing has no benefit (fc32e1s_tiny, 2026-10-09: timing
# +7 % logic for +0.4 % Fmax). The project folders are generated (not committed): this script is
# the source.

set GW_DEVICE  GW2A-LV18PG256C8/I7
set GW_VERSION C

# name: project name; flow_dir: the calling script's folder; top: top module;
# files: sources / constraints in compile order (absolute paths, package first)
proc fc32e1s_nano_fpga_gw_project {name flow_dir top files} {
  global GW_DEVICE GW_VERSION
  set goal area
  if {[info exists ::env(OPT_GOAL)]} { set goal $::env(OPT_GOAL) }
  set mo 1
  if {[info exists ::env(MAP_OPTION)]} { set mo $::env(MAP_OPTION) }
  set pdir [file normalize $flow_dir/prj]
  if {[info exists ::env(PRJ_DIR)]} { set pdir [file normalize $::env(PRJ_DIR)] }

  create_project -name $name -dir $pdir -pn $GW_DEVICE -device_version $GW_VERSION -force
  set here [file normalize $pdir/$name]

  foreach f $files {
    if {[string match *.sdc $f] && [info exists ::env(PERIOD)]} {
      # own copy of the timing constraint with the requested period
      set p $::env(PERIOD)
      set h [open $f r]; set s [read $h]; close $h
      regsub -all -- {-period [0-9.]+ -waveform \{0 [0-9.]+\}} $s \
        "-period $p -waveform {0 [expr {$p / 2.0}]}" s
      set f $here/[file rootname [file tail $f]]_period.sdc
      set h [open $f w]; puts -nonewline $h $s; close $h
    }
    add_file $f
  }

  set_option -top_module $top
  set_option -verilog_std sysv2017
  set_option -output_base_name $name
  set_option -use_sspi_as_gpio 1
  set_option -use_mspi_as_gpio 1
  set_option -use_ready_as_gpio 1
  set_option -use_done_as_gpio 1
  set_option -use_cpu_as_gpio 1
  set_option -opt_goal $goal
  set_option -map_option $mo
  set_option -place_option 2
  set_option -route_option 1
  set_option -clock_route_order 1
  set_option -route_maxfan 12
  set_option -correct_hold_violation 1
  set_option -max_fanout 12

  puts "project: $here/$name.gprj (opt_goal $goal, map option $mo)"
  if {[info exists ::env(RUN)]} {
    if {$::env(RUN) eq "1"} { run all }
    if {$::env(RUN) eq "syn"} { run syn }
  }
}
