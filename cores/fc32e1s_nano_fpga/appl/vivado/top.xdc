# fc32e1s_nano_fpga board top, Vivado: 100 MHz reference clock (Fmax from the timing report).
# Pins are not constrained: add PACKAGE_PIN / IOSTANDARD for your board before writing a bitstream.
create_clock -name clk_i -period 10.000 [get_ports clk_i]
