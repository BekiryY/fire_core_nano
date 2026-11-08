// fc32e1s_nano_asic core alone on GW2A: 100 MHz reference clock (Fmax from the timing report)
create_clock -name clk_i -period 10 -waveform {0 5} [get_ports {clk_i}]
