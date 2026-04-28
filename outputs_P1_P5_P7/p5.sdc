# Auto-generated SDC — clock period: 4.5 ns
create_clock -name clk -period 4.5 [get_ports clk]
set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]
set_clock_transition   0.05       [get_clocks clk]
set_input_delay  1.35 -clock clk [get_ports {A B}]
set_output_delay 1.35 -clock clk [get_ports {dot_out valid}]
