# lab4_addio (5stage + swc1 io) : CMOD A7 + MEM_QSPI  (from tiny_outer_io_pins_cmod_a7_eth.xdc, init_uart enabled)
# QSPI Pmod pins for CMOD A7
# JA1 ce_n[0]  G17  6
# JA2 sio[0]   G19  1
# JA3 sio[1]   N18  5
# JA4 sck      L18  2
# JA7 sio[2]   H17  3
# JA8 sio[3]   H19  7
# JA9 ce_n[1]  J19
# JA10 ce_n[2] K18
# JA5,11 GND       4
# JA6,12 3.3V      8
# LED_R  C17
# LED_G  B16
# LED_B  B17

# R3  PIO26  Pmod4  sck
# T3  PIO27  Pmod3  sio[1]
# R2  PIO28  Pmod2  sio[0]
# T1  PIO29  Pmod1  ce_n[0]
# T2  PIO30  Pmod10 ce_n[2]
# U1  PIO31  Pmod9  ce_n[1]
# W2  PIO32  Pmod8  sio[3]
# V2  PIO33  Pmod7  sio[2]

# Ether nomal pins version
# Pmod pins JA for SPI ether
# J1 PIO20 cs   M2 out RGB[1]
# J2 PIO21 sck  N1 out RGB[2]
# J3 PIO22 MOSI N2 in init_qspicmd
# J4 PIO23 MISO P1 out RGB[0]
# J7 PIO19 INT  P3 in interrupt_0


set_property OFFCHIP_TERM NONE [get_ports rgb_led[2]]
set_property OFFCHIP_TERM NONE [get_ports rgb_led[1]]
set_property OFFCHIP_TERM NONE [get_ports rgb_led[0]]
set_property IOSTANDARD LVCMOS33 [get_ports {rgb_led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgb_led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {rgb_led[0]}]
set_property DRIVE 12 [get_ports {rgb_led[2]}]
set_property DRIVE 12 [get_ports {rgb_led[1]}]
set_property DRIVE 12 [get_ports {rgb_led[0]}]
set_property SLEW SLOW [get_ports {rgb_led[2]}]
set_property SLEW SLOW [get_ports {rgb_led[1]}]
set_property SLEW SLOW [get_ports {rgb_led[0]}]
set_property PACKAGE_PIN N1 [get_ports {rgb_led[2]}]
#set_property PACKAGE_PIN M2 [get_ports {rgb_led[1]}]
set_property PACKAGE_PIN J1 [get_ports {rgb_led[1]}]
set_property PACKAGE_PIN P1 [get_ports {rgb_led[0]}]

set_property OFFCHIP_TERM NONE [get_ports sck]
set_property OFFCHIP_TERM NONE [get_ports ce_n[0]]
set_property OFFCHIP_TERM NONE [get_ports ce_n[1]]
set_property OFFCHIP_TERM NONE [get_ports ce_n[2]]
set_property IOSTANDARD LVCMOS33 [get_ports {sck}]
set_property IOSTANDARD LVCMOS33 [get_ports {ce_n[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ce_n[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ce_n[2]}]
set_property DRIVE 12 [get_ports {sck}]
set_property DRIVE 12 [get_ports {ce_n[0]}]
set_property DRIVE 12 [get_ports {ce_n[1]}]
set_property DRIVE 12 [get_ports {ce_n[2]}]
set_property SLEW FAST [get_ports {sck}]
set_property SLEW SLOW [get_ports {ce_n[0]}]
set_property SLEW SLOW [get_ports {ce_n[1]}]
set_property SLEW SLOW [get_ports {ce_n[2]}]
set_property PACKAGE_PIN R3 [get_ports {sck}]
set_property PACKAGE_PIN T1 [get_ports {ce_n[0]}]
set_property PACKAGE_PIN U1 [get_ports {ce_n[1]}]
set_property PACKAGE_PIN T2 [get_ports {ce_n[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports clkin]
set_property PACKAGE_PIN L17 [get_ports clkin]
set_property IOSTANDARD LVCMOS33 [get_ports rx]
set_property PACKAGE_PIN J17 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports interrupt_0]
set_property PACKAGE_PIN P3 [get_ports interrupt_0]

set_property OFFCHIP_TERM NONE [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
set_property DRIVE 12 [get_ports tx]
set_property SLEW SLOW [get_ports tx]
set_property PACKAGE_PIN J18 [get_ports tx]

set_property IOSTANDARD LVCMOS33 [get_ports rst_p]
set_property PACKAGE_PIN B18 [get_ports rst_p]
#set_property PULLDOWN   true [get_ports rst_p]

set_property IOSTANDARD LVCMOS33 [get_ports {init_latency[0]}]
set_property PACKAGE_PIN M3 [get_ports {init_latency[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {init_latency[1]}]
set_property PACKAGE_PIN L3 [get_ports {init_latency[1]}]
#(not used in 5stage) set_property IOSTANDARD LVCMOS33 [get_ports init_cpu_start]
#(not used in 5stage) set_property PACKAGE_PIN A18 [get_ports init_cpu_start]

set_property IOSTANDARD LVCMOS33 [get_ports {init_uart[0]}]
set_property PACKAGE_PIN K3 [get_ports {init_uart[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {init_uart[1]}]
set_property PACKAGE_PIN C15 [get_ports {init_uart[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports init_qspicmd]
set_property PACKAGE_PIN N2 [get_ports init_qspicmd]

set_property PULLDOWN true [get_ports {init_latency[0]}]
set_property PULLDOWN true [get_ports {init_latency[1]}]
#set_property PULLDOWN true [get_ports init_cpu_start]
set_property PULLDOWN true [get_ports init_qspicmd]
set_property PULLUP   true [get_ports {init_uart[0]}]
set_property PULLDOWN true [get_ports {init_uart[1]}]

set_property OFFCHIP_TERM NONE [get_ports gpio[3]]
set_property OFFCHIP_TERM NONE [get_ports gpio[2]]
set_property OFFCHIP_TERM NONE [get_ports gpio[1]]
set_property OFFCHIP_TERM NONE [get_ports gpio[0]]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio[0]}]
set_property DRIVE 12 [get_ports {gpio[3]}]
set_property DRIVE 12 [get_ports {gpio[2]}]
set_property DRIVE 12 [get_ports {gpio[1]}]
set_property DRIVE 12 [get_ports {gpio[0]}]
set_property SLEW SLOW [get_ports {gpio[3]}]
set_property SLEW SLOW [get_ports {gpio[2]}]
set_property SLEW SLOW [get_ports {gpio[1]}]
set_property SLEW SLOW [get_ports {gpio[0]}]
set_property PACKAGE_PIN B15 [get_ports {gpio[3]}]
set_property PACKAGE_PIN A14 [get_ports {gpio[2]}]
set_property PACKAGE_PIN J3 [get_ports {gpio[1]}]
#set_property PACKAGE_PIN J1 [get_ports {gpio[0]}]
set_property PACKAGE_PIN M2 [get_ports {gpio[0]}]

set_property OFFCHIP_TERM NONE [get_ports sio[0]]
set_property OFFCHIP_TERM NONE [get_ports sio[1]]
set_property OFFCHIP_TERM NONE [get_ports sio[2]]
set_property OFFCHIP_TERM NONE [get_ports sio[3]]
set_property IOSTANDARD LVCMOS33 [get_ports {sio[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sio[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sio[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sio[3]}]
set_property DRIVE 12 [get_ports {sio[0]}]
set_property DRIVE 12 [get_ports {sio[1]}]
set_property DRIVE 12 [get_ports {sio[2]}]
set_property DRIVE 12 [get_ports {sio[3]}]
set_property SLEW SLOW [get_ports {sio[0]}]
set_property SLEW SLOW [get_ports {sio[1]}]
set_property SLEW SLOW [get_ports {sio[2]}]
set_property SLEW SLOW [get_ports {sio[3]}]
set_property PACKAGE_PIN R2 [get_ports {sio[0]}]
set_property PACKAGE_PIN T3 [get_ports {sio[1]}]
set_property PACKAGE_PIN V2 [get_ports {sio[2]}]
set_property PACKAGE_PIN W2 [get_ports {sio[3]}]

#revert back to original instance
#current_instance -quiet

create_clock -period 83.333 -name clkin -waveform {0.000 41.667} [get_ports clkin]

#create_generated_clock -name clk [get_pins fpga_all_top/clknetwork/clk_out1]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports rst_p]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports rst_p]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports rx]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports rx]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports interrupt_0]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports interrupt_0]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports {init_latency[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports {init_latency[*]}]
#(not used in 5stage) set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports init_cpu_start]
#(not used in 5stage) set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports init_cpu_start]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports {init_uart[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports {init_uart[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports init_qspicmd]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports init_qspicmd]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports {gpio[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports {gpio[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay 1.000 [get_ports {sio[*]}]
set_input_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay 1.000 [get_ports {sio[*]}]

set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay -3.000 [get_ports {rgb_led[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay -3.000 [get_ports {rgb_led[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay -3.000 [get_ports tx]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay -3.000 [get_ports tx]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay -3.000 [get_ports {gpio[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay -3.000 [get_ports {gpio[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay  0.000 [get_ports {sio[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay  0.000 [get_ports {sio[*]}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -min -add_delay  3.000 [get_ports {sck}]
set_output_delay -clock [get_clocks -of_objects [get_nets clk]] -max -add_delay  3.000 [get_ports {sck}]

