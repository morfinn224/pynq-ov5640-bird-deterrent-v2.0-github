set project_dir {C:/Users/17550/Documents/Codex/2026-09-28/new-chat/bird_det_fpga_camera_mcp4725_v2_0}
set project_file [file join $project_dir bird_det_fpga.xpr]
set bd_file [file join $project_dir bird_det_fpga.srcs sources_1 bd pynq_frame_diff_bd pynq_frame_diff_bd.bd]
set iic_xdc [file join $project_dir mcp4725_iic_v2_0.xdc]

open_project $project_file

# Use the v2.0 register source (VERSION=0x00020000).
set old_ctrl_files [get_files -quiet *frame_diff_ctrl_axi.v]
if {[llength $old_ctrl_files] > 0} {
    remove_files $old_ctrl_files
}
add_files -norecurse [file join $project_dir local_src frame_diff_ctrl_axi.v]

if {[llength [get_files -quiet *mcp4725_iic_v2_0.xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $iic_xdc
}
update_compile_order -fileset sources_1

open_bd_design $bd_file
update_module_reference -verbose [get_ips pynq_frame_diff_bd_frame_diff_ctrl_axi_test_0]
update_module_reference -verbose [get_ips pynq_frame_diff_bd_ov5640_camera_test_1]

# Preserve the validated v1.9 LED/SD GPIO configuration and address.
set gpio [get_bd_cells axi_gpio_status_leds_0]
if {[llength $gpio] != 1} {
    error "Expected existing AXI GPIO axi_gpio_status_leds_0"
}
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH {3} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO2_WIDTH {4} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
    CONFIG.C_DOUT_DEFAULT_2 {0x00000000} \
    CONFIG.C_INTERRUPT_PRESENT {0}] $gpio

assign_bd_address -offset 0x41200000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs $gpio/S_AXI/Reg] -force

# Add an AXI IIC controller on the next SmartConnect master port.
set smc [get_bd_cells axi_smc]
if {[llength $smc] != 1} {
    error "Expected existing SmartConnect axi_smc"
}
set_property CONFIG.NUM_MI {6} $smc

if {[llength [get_bd_cells -quiet axi_iic_audio_0]] == 0} {
    set iic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:2.1 axi_iic_audio_0]
} else {
    set iic [get_bd_cells axi_iic_audio_0]
}

if {[llength [get_bd_intf_nets -quiet axi_smc_M05_AXI]] == 0} {
    connect_bd_intf_net -intf_net axi_smc_M05_AXI \
        [get_bd_intf_pins axi_smc/M05_AXI] [get_bd_intf_pins $iic/S_AXI]
}

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins $iic/s_axi_aclk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] \
    [get_bd_pins $iic/s_axi_aresetn]

if {[llength [get_bd_intf_ports -quiet audio_iic]] == 0} {
    set iic_port [create_bd_intf_port -mode Master \
        -vlnv xilinx.com:interface:iic_rtl:1.0 audio_iic]
} else {
    set iic_port [get_bd_intf_ports audio_iic]
}
if {[llength [get_bd_intf_nets -quiet audio_iic_net]] == 0} {
    connect_bd_intf_net -intf_net audio_iic_net [get_bd_intf_pins $iic/IIC] $iic_port
}

assign_bd_address -offset 0x41600000 -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs $iic/S_AXI/Reg] -force

validate_bd_design
save_bd_design
generate_target all [get_files pynq_frame_diff_bd.bd]

# Regenerate the HDL wrapper because v2.0 adds the external IIC interface.
set wrapper_files [make_wrapper -files [get_files $bd_file] -top -force]
add_files -norecurse $wrapper_files
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "FINAL_IMPL_STATUS=$impl_status"
if {$impl_status ne "write_bitstream Complete!"} {
    error "Implementation did not complete: $impl_status"
}

set output_dir [file join $project_dir output_v2_0]
file mkdir $output_dir
set bit_src [file join $project_dir bird_det_fpga.runs impl_1 pynq_frame_diff_bd_wrapper.bit]
set hwh_src [file join $project_dir bird_det_fpga.gen sources_1 bd pynq_frame_diff_bd hw_handoff pynq_frame_diff_bd.hwh]
file copy -force $bit_src [file join $output_dir pynq_frame_diff_bd_wrapper.bit]
file copy -force $hwh_src [file join $output_dir pynq_frame_diff_bd_wrapper.hwh]
puts "OUTPUT_DIR=$output_dir"

close_project
