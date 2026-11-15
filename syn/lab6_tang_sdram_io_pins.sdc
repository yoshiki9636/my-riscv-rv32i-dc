//Part Number: GW5A-LV25MG121NC2/I1
//Device: GW5A-25

create_clock -name clk50m -period 20 -waveform {0 10} [get_ports {clkin}]

// mclk : SDRAM controller clock (PLL clkout0, 50MHz). sdram_clk pin = mclk_pll (0deg)
create_generated_clock -name mclk_pll -source [get_ports {clkin}] -master_clock clk50m -divide_by 1 -multiply_by 1 -duty_cycle 50 [get_pins {clknetwork/u_pll/PLLA_inst/CLKOUT0}]
// clk : CPU / bus clock (PLL clkout1, 33.333MHz = 50MHz x 2 / 3, fpga_config.vh TANG_PLL_33M)
//   TANG_PLL_50M : -divide_by 1 -multiply_by 1
create_generated_clock -name clk -source [get_ports {clkin}] -master_clock clk50m -divide_by 3 -multiply_by 2 -duty_cycle 50 [get_pins {clknetwork/u_pll/PLLA_inst/CLKOUT1}]

set_false_path -from [get_clocks {clk}] -to [get_clocks {mclk_pll}]
set_false_path -from [get_clocks {mclk_pll}] -to [get_clocks {clk}]
