## =============================================================================
## FILE: nexys_a7.xdc
## PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
## Board: Digilent Nexys A7-100T (XC7A100TCSG324-1)
## =============================================================================

## 100 MHz clock
set_property PACKAGE_PIN E3       [get_ports clk_i]
set_property IOSTANDARD  LVCMOS33 [get_ports clk_i]
create_clock -add -name sys_clk_pin -period 10.000 [get_ports clk_i]

## Reset (CPU_RESETN active-low)
set_property PACKAGE_PIN C12      [get_ports rst_ni]
set_property IOSTANDARD  LVCMOS33 [get_ports rst_ni]

## UART (USB bridge — note pin name inversion is intentional)
set_property PACKAGE_PIN B11      [get_ports uart_rx_i]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_rx_i]
set_property PACKAGE_PIN A11      [get_ports uart_tx_o]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx_o]

## LEDs
set_property PACKAGE_PIN H17      [get_ports {led_o[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[0]}]
set_property PACKAGE_PIN K15      [get_ports {led_o[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[1]}]
set_property PACKAGE_PIN J13      [get_ports {led_o[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[2]}]
set_property PACKAGE_PIN N14      [get_ports {led_o[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[3]}]
set_property PACKAGE_PIN R18      [get_ports {led_o[4]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[4]}]
set_property PACKAGE_PIN V17      [get_ports {led_o[5]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[5]}]
set_property PACKAGE_PIN U17      [get_ports {led_o[6]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[6]}]
set_property PACKAGE_PIN U16      [get_ports {led_o[7]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {led_o[7]}]

## PWM output → Pmod JA pin 1 (for ESC signal or oscilloscope)
## Real car: connect this to ESC white signal wire (with logic-level shifter if needed)
set_property PACKAGE_PIN C17      [get_ports pwm_o]
set_property IOSTANDARD  LVCMOS33 [get_ports pwm_o]

## Brake output → Pmod JA pin 2 (drives relay or transistor for motor cut)
## Real car: connect to NPN transistor base → relay cuts ESC power on emergency
set_property PACKAGE_PIN D18      [get_ports brake_o]
set_property IOSTANDARD  LVCMOS33 [get_ports brake_o]

## Timing
set_input_delay  -clock sys_clk_pin -max 5.0 [get_ports uart_rx_i]
set_input_delay  -clock sys_clk_pin -min 1.0 [get_ports uart_rx_i]
set_output_delay -clock sys_clk_pin -max 5.0 [get_ports uart_tx_o]
set_output_delay -clock sys_clk_pin -min 1.0 [get_ports uart_tx_o]
