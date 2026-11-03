# MCP4725 control bus on PMODA.
# H2-5 SDA -> PMODA physical pin 9 / JA4_P / W18
# H2-6 SCL -> PMODA physical pin 10 / JA4_N / W19
# AXI IIC exposes true open-drain I/O through the generated IOBUFs.
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports audio_iic_sda_io]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports audio_iic_scl_io]

# The external board already provides measured 3.3 V pull-ups.
# Internal weak pull-ups are intentionally not enabled.
