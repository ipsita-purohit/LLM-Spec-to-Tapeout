# Auto-generated SDC — clock period: 8.0 ns
create_clock -name clk -period 8.0 [get_ports clk]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]
set_clock_transition   0.05       [get_clocks clk]
set_input_delay  2.4 -clock clk [get_ports {x_in h}]
set_output_delay 2.4 -clock clk [get_ports {y_out}]
