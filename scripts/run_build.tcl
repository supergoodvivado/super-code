set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]
source [file join $script_dir create_project.tcl]

launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Synthesis did not complete"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "Implementation or bitstream generation did not complete"
}

puts "Bitstream generated under:"
puts [file join $root_dir vivado_project_hx7a75c vending_machine_hx7a75c.runs impl_1 vending_machine_top.bit]

