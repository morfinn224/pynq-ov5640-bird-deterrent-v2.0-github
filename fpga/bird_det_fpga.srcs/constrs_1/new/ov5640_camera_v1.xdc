# ============================================================
# ATK-OV5640 DVP camera interface - PYNQ-Z2
# First version: 320x240 RGB565, 15 fps
# Target PCLK about 12 MHz
# Input path designed for maximum PCLK 24 MHz
# ============================================================

# ------------------------------------------------------------
# Camera pixel clock
# OV5640 pin 15 -> PMODA physical pin 7 / JA3_P / FPGA U18
# ------------------------------------------------------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports cam_pclk]

# ------------------------------------------------------------
# Camera parallel data D0-D7
# ------------------------------------------------------------

# OV5640 pin 7, D0 -> Arduino AR0
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {cam_d[0]}]

# OV5640 pin 9, D1 -> Arduino AR1
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {cam_d[1]}]

# OV5640 pin 10, D2 -> Arduino AR2
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {cam_d[2]}]

# OV5640 pin 11, D3 -> Arduino AR3
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {cam_d[3]}]

# OV5640 pin 12, D4 -> Arduino AR4
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {cam_d[4]}]

# OV5640 pin 13, D5 -> Arduino AR5
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {cam_d[5]}]

# OV5640 pin 14, D6 -> Arduino AR6
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {cam_d[6]}]

# OV5640 pin 16, D7 -> Arduino AR7
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {cam_d[7]}]

# ------------------------------------------------------------
# Camera synchronization signals
# ------------------------------------------------------------

# OV5640 pin 4, VSYNC -> Arduino AR8
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports cam_vsync]

# OV5640 pin 6, HREF -> Arduino AR9
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports cam_href]

# ------------------------------------------------------------
# Camera reset and power-down control
# ------------------------------------------------------------

# OV5640 pin 8, RESET, active low -> Arduino AR10
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports cam_reset_n]

# OV5640 pin 17, PWDN, active high -> Arduino AR13
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports cam_pwdn]

# Use slow slew rate for low-speed control outputs
set_property SLEW SLOW [get_ports cam_reset_n]
set_property SLEW SLOW [get_ports cam_pwdn]

# ------------------------------------------------------------
# SCCB control interface
# External 4.7 kOhm pull-ups to the camera 3.3 V supply
# Both signals must only pull low or release to high impedance
# ------------------------------------------------------------

# OV5640 pin 3, SCL -> Arduino AR11
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports cam_scl]

# OV5640 pin 5, SDA -> Arduino AR12
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports cam_sda]

# ------------------------------------------------------------
# PCLK timing constraint
# Actual first-version PCLK target is approximately 12 MHz.
# Use 24 MHz as the conservative maximum design frequency.
# 1 / 24 MHz = 41.667 ns
# ------------------------------------------------------------
create_clock -period 41.667 -name cam_pclk [get_ports cam_pclk]

# ------------------------------------------------------------
# Important:
# Input delay constraints for cam_d, cam_href and cam_vsync
# will be added after confirming the OV5640 output timing
# relative to PCLK.
#
# OV5640 connector pin 18 is NC and has no FPGA port.
# ------------------------------------------------------------
# Camera PCLK and PS fabric clock are asynchronous
#set_clock_groups -asynchronous #    -group [get_clocks cam_pclk] #
# Ignore only the asynchronous assertion path into the PCLK reset synchronizer.
set_false_path -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ *pclk_reset_sync_reg*}] -filter {REF_PIN_NAME == CLR}]

set_clock_groups -asynchronous -group [get_clocks cam_pclk] -group [get_clocks clk_fpga_0]
set_property PULLUP true [get_ports cam_scl]
set_property PULLUP true [get_ports cam_sda]

# ------------------------------------------------------------
# Software-controlled status LEDs (AXI GPIO bits 2:0)
# bit 0 / LD0: BLUE logical state   - monitor/cooldown
# bit 1 / LD1: RED logical state    - bird/recheck
# bit 2 / LD2: YELLOW logical state - audio playback
# All LEDs are active high. Reset/default output is 3'b000.
# ------------------------------------------------------------
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {status_led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {status_led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {status_led[2]}]

# ------------------------------------------------------------
# External controller board on PMODA (AXI GPIO channel 2)
# bit 0: BLUE_CTL   -> H2-2, active high
# bit 1: RED_CTL    -> H2-3, active high
# bit 2: YELLOW_CTL -> H2-4, active high
# bit 3: AMP_SD     -> H2-8, high=amplifier enabled
# PMODA physical pin 5 GND -> H2-1 GND
# Reset/default output is 4'b0000.
# ------------------------------------------------------------
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {external_ctl[0]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {external_ctl[1]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {external_ctl[2]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports {external_ctl[3]}]
