create_clock -name FPGA_CLK1_50 -period 20.000 [get_ports {FPGA_CLK1_50}]
derive_pll_clocks
derive_clock_uncertainty
set_false_path -from [get_ports {KEY[0]}]
set_false_path -to [get_ports {LED[*]}]
