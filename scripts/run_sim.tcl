set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_project.tcl]

launch_simulation
run all

