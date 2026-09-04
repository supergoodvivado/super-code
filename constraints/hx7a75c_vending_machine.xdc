## HX7A75A / Artix-7 XC7A75T-2FGG484 basic constraints.
## Verify these pins against your own HX7A75C board manual before downloading.

set_property PACKAGE_PIN Y18 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

set_property PACKAGE_PIN N14 [get_ports {sw[0]}]
set_property PACKAGE_PIN P16 [get_ports {sw[1]}]
set_property PACKAGE_PIN R17 [get_ports {sw[2]}]
set_property PACKAGE_PIN N15 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

set_property PACKAGE_PIN E3 [get_ports {key_n[0]}]
set_property PACKAGE_PIN G4 [get_ports {key_n[1]}]
set_property PACKAGE_PIN P19 [get_ports {key_n[2]}]
set_property PACKAGE_PIN R19 [get_ports {key_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_n[*]}]

set_property PACKAGE_PIN AA6 [get_ports {led[0]}]
set_property PACKAGE_PIN V7 [get_ports {led[1]}]
set_property PACKAGE_PIN W7 [get_ports {led[2]}]
set_property PACKAGE_PIN AB7 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property PACKAGE_PIN AB18 [get_ports {seg[0]}]
set_property PACKAGE_PIN U17 [get_ports {seg[1]}]
set_property PACKAGE_PIN U18 [get_ports {seg[2]}]
set_property PACKAGE_PIN P14 [get_ports {seg[3]}]
set_property PACKAGE_PIN R14 [get_ports {seg[4]}]
set_property PACKAGE_PIN R18 [get_ports {seg[5]}]
set_property PACKAGE_PIN T18 [get_ports {seg[6]}]
set_property PACKAGE_PIN N17 [get_ports {seg[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

set_property PACKAGE_PIN Y19 [get_ports {sel[0]}]
set_property PACKAGE_PIN V18 [get_ports {sel[1]}]
set_property PACKAGE_PIN V19 [get_ports {sel[2]}]
set_property PACKAGE_PIN AA19 [get_ports {sel[3]}]
set_property PACKAGE_PIN AB20 [get_ports {sel[4]}]
set_property PACKAGE_PIN V17 [get_ports {sel[5]}]
set_property PACKAGE_PIN W17 [get_ports {sel[6]}]
set_property PACKAGE_PIN AA18 [get_ports {sel[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sel[*]}]

set_property PACKAGE_PIN P20 [get_ports buzzer]
set_property IOSTANDARD LVCMOS33 [get_ports buzzer]
