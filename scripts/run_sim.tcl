set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_project.tcl]

launch_simulation
run all
close_sim
set_property top tb_selection_full [get_filesets sim_1]
launch_simulation
run all
close_sim
set_property top tb_vending_machine_core [get_filesets sim_1]

