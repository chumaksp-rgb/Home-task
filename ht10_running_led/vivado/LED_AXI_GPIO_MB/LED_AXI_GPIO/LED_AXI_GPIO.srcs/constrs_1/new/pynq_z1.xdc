   ## Clock signal 125 MHz

set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sysclk }]; #IO_L13P_T2_MRCC_35 Sch=sysclk
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sysclk }];
   
   
    set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led_tri_io[0]}]
    set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led_tri_io[1]}]
    set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led_tri_io[2]}]
    set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led_tri_io[3]}]

    set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {btn_tri_io[0]}]
    set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {btn_tri_io[1]}]
    set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {btn_tri_io[2]}]
    set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {btn_tri_io[3]}]

    set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw_tri_io[0]}]
    set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw_tri_io[1]}]