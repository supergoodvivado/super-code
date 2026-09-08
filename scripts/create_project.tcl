set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]
set project_name "vending_machine_hx7a75c"
set project_dir [file join $root_dir "vivado_project_hx7a75c"]

create_project $project_name $project_dir -part xc7a75tfgg484-2 -force

add_files -fileset sources_1 [list \
    [file join $root_dir src button_conditioner.v] \
    [file join $root_dir src seven_segment_scan.v] \
    [file join $root_dir src vending_machine_core.v] \
    [file join $root_dir src vending_machine_top.v] \
]

add_files -fileset sim_1 [list \
    [file join $root_dir sim tb_vending_machine_core.v] \
    [file join $root_dir sim tb_selection_full.v] \
]

add_files -fileset constrs_1 [list \
    [file join $root_dir constraints hx7a75c_vending_machine.xdc] \
]

set_property top vending_machine_top [current_fileset]
set_property top tb_vending_machine_core [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created Vivado project at $project_dir"

