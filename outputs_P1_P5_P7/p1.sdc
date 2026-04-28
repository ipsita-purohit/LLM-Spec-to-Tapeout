# Auto-generated SDC — clock period: 1.1 ns
create_clock -name clk -period 1.1 [get_ports clk]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]
set_clock_transition   0.05       [get_clocks clk]
set_input_delay  0.33 -clock clk [get_ports {data_in}]
set_output_delay 0.33 -clock clk [get_ports {detected}]
