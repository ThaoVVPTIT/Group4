# Vivado batch implementation and evidence report for cnn_ver5.
# Usage from this directory:
#   vivado -mode batch -source run_ver5_implementation.tcl

set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $script_dir cnn_pe_ver1.srcs sources_1 new]
set xdc_file [file join $script_dir cnn_pe_ver1.srcs constrs_1 new \
    cnn_ver5_timing.xdc]
set report_dir [file join $script_dir ver5_reports]
file mkdir $report_dir

create_project -in_memory -part xczu9eg-ffvb1156-2-e
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [lsort [glob -nocomplain [file join $rtl_dir *.v]]]
if {[llength $rtl_files] == 0} {
    error "No Verilog sources found in $rtl_dir"
}
read_verilog $rtl_files
read_xdc [list $xdc_file]

synth_design -top cnn_accelerator_top -part xczu9eg-ffvb1156-2-e \
    -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force [file join $report_dir cnn_ver5_post_synth.dcp]
report_utilization -hierarchical -file \
    [file join $report_dir utilization_post_synth.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_post_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $report_dir cnn_ver5_post_route.dcp]

report_utilization -hierarchical -file \
    [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type min_max -max_paths 50 -report_unconstrained \
    -file [file join $report_dir timing_post_route.rpt]
report_clock_utilization -file \
    [file join $report_dir clock_utilization.rpt]
report_clocks -file [file join $report_dir clocks_post_route.rpt]
check_timing -verbose -file [file join $report_dir check_timing_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]
report_power -file [file join $report_dir power_post_route.rpt]

set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
    error "No setup/hold timed path was produced; inspect constraints"
}
set setup_slack [get_property SLACK [lindex $setup_paths 0]]
set hold_slack [get_property SLACK [lindex $hold_paths 0]]
puts "cnn_ver5 routed worst setup slack: $setup_slack ns"
puts "cnn_ver5 routed worst hold slack:  $hold_slack ns"
if {$setup_slack < 0.0} {
    error "cnn_ver5 does not close the 100 MHz timing target"
}
if {$hold_slack < 0.0} {
    error "cnn_ver5 has a routed hold violation"
}

set drc_errors [get_drc_violations -quiet -filter {SEVERITY == "Error"}]
if {[llength $drc_errors] != 0} {
    error "cnn_ver5 has [llength $drc_errors] routed DRC error(s)"
}

puts "cnn_ver5 implementation PASS; reports are in $report_dir"
exit
