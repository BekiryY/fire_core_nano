# SERV core alone, Vivado out-of-context: 100 MHz reference clock (estimated Fmax from WNS)
create_clock -name clk -period 10.000 [get_ports clk]
