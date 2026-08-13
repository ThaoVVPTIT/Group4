# Batch regression for the scheduler-integrated Group-1 design.
set project_file [file normalize "./cnn_pe_ver1.xpr"]

open_project $project_file
set_property top cnn_accelerator_top [get_filesets sources_1]
set_property top tb_axis_cnn [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation
run all
close_sim
close_project
exit
