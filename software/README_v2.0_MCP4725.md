# v2.0 MCP4725/PAM8302A audio path

- H2-5 SDA -> PMODA physical pin 9 / W18
- H2-6 SCL -> PMODA physical pin 10 / W19
- H2-7 remains unconnected
- H2-8 controls PAM8302A SD (high=enabled)
- MCP4725 OUT/H1-5 -> PAM8302A A+
- PAM8302A A- -> system ground
- Speaker connects only to VO+ and VO-

The v2.0 Overlay contains `axi_iic_audio_0` at `0x41600000` and reports
version `0x00020000`. Start with the silent DAC voltage test, then use
`mcp4725_selftest.py --tone --volume 0.02`. Do not begin at 20 percent volume.
