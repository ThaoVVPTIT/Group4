# License-free synthesis sanity check for cnn_ver5.
#
# This validates Vivado elaboration, procedural ownership and Xilinx RAM/DSP
# inference on a WebPACK-supported 7-series part.  It is NOT a substitute for
# timing/resource implementation on the target XCZU9EG.

set script_dir [file normalize [file dirname [info script]]]
set rtl_dir [file join $script_dir cnn_pe_ver1.srcs sources_1 new]
set report_dir [file join $script_dir ver5_reports]
set sanity_part xc7a100tcsg324-1
file mkdir $report_dir

create_project -in_memory -part $sanity_part
set_property target_language Verilog [current_project]

set rtl_files [lsort [glob -nocomplain [file join $rtl_dir *.v]]]
if {[llength $rtl_files] == 0} {
    error "No Verilog sources found in $rtl_dir"
}
read_verilog $rtl_files
synth_design -top cnn_accelerator_top -part $sanity_part \
    -mode out_of_context -flatten_hierarchy rebuilt

report_utilization -hierarchical -file [file join $report_dir \
    utilization_synth_sanity_xc7a100t.rpt]

puts "cnn_ver5 Vivado synthesis sanity PASS on $sanity_part"
puts "This result does not certify XCZU9EG utilization, WNS or power."
exit
