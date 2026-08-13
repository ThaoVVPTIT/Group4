# Same-part synthesis baseline for a relative cnn_ver3_1/cnn_ver5 comparison.
# The XC7A100T result is not a target-device utilization sign-off.

set script_dir [file normalize [file dirname [info script]]]
set workspace_dir [file normalize [file join $script_dir .. .. ..]]
set rtl_dir [file join $workspace_dir cnn_ver3_1 cnn_ver3 cnn_pe_ver1 \
    cnn_pe_ver1.srcs sources_1 new]
set report_dir [file join $script_dir ver5_reports]
set sanity_part xc7a100tcsg324-1
file mkdir $report_dir

create_project -in_memory -part $sanity_part
set_property target_language Verilog [current_project]
set rtl_files [lsort [glob -nocomplain [file join $rtl_dir *.v]]]
if {[llength $rtl_files] == 0} {
    error "No cnn_ver3_1 Verilog sources found in $rtl_dir"
}
read_verilog $rtl_files
synth_design -top cnn_accelerator_top -part $sanity_part \
    -mode out_of_context -flatten_hierarchy rebuilt
report_utilization -hierarchical -file [file join $report_dir \
    utilization_cnn_ver3_1_xc7a100t.rpt]

puts "cnn_ver3_1 synthesis baseline PASS on $sanity_part"
exit
