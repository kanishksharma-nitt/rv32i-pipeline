## Starting constraints for the RV32I core (Artix-7 example).
## Adjust the period to your timing target and add real pin assignments.
create_clock -name clk -period 11.000 [get_ports clk]
set_input_delay  -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]
