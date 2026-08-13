# Vivado batch regression for the 8-lane weight-stationary Conv datapath.
set project_file [file normalize "./cnn_pe_ver1.xpr"]

open_project $project_file
set_property top tb_ws_dataflow [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project

