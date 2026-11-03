set project_dir {C:/Users/17550/Documents/Codex/2026-09-28/new-chat/bird_det_fpga_camera_realscene_v2}
set project_file [file join $project_dir bird_det_fpga.xpr]
set bd_file [file join $project_dir bird_det_fpga.srcs sources_1 bd pynq_frame_diff_bd pynq_frame_diff_bd.bd]

open_project $project_file

# Ensure the updated control-register source (VERSION=0x00010400) is used.
set old_ctrl_files [get_files -quiet *frame_diff_ctrl_axi.v]
if {[llength $old_ctrl_files] > 0} {
    remove_files $old_ctrl_files
}
add_files -norecurse [file join $project_dir local_src frame_diff_ctrl_axi.v]
update_compile_order -fileset sources_1

open_bd_design $bd_file
update_module_reference -verbose [get_ips pynq_frame_diff_bd_frame_diff_ctrl_axi_test_0]

# Add a 3-bit, output-only AXI GPIO. The AXI GPIO reset value is zero.
if {[llength [get_bd_cells -quiet axi_gpio_status_leds_0]] == 0} {
    set_property CONFIG.NUM_MI {5} [get_bd_cells axi_smc]
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_status_leds_0
    set_property -dict [list \
        CONFIG.C_GPIO_WIDTH {3} \
        CONFIG.C_ALL_OUTPUTS {1} \
        CONFIG.C_DOUT_DEFAULT {0x00000000} \
        CONFIG.C_IS_DUAL {0} \
        CONFIG.C_INTERRUPT_PRESENT {0}] [get_bd_cells axi_gpio_status_leds_0]

    connect_bd_intf_net [get_bd_intf_pins axi_smc/M04_AXI] [get_bd_intf_pins axi_gpio_status_leds_0/S_AXI]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_gpio_status_leds_0/s_axi_aclk]
    connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins axi_gpio_status_leds_0/s_axi_aresetn]

    set led_port [create_bd_port -dir O -from 2 -to 0 status_led]
    connect_bd_net [get_bd_pins axi_gpio_status_leds_0/gpio_io_o] $led_port
}

assign_bd_address -offset 0x41200000 -range 4K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs axi_gpio_status_leds_0/S_AXI/Reg] -force

validate_bd_design
save_bd_design
generate_target all [get_files pynq_frame_diff_bd.bd]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "FINAL_IMPL_STATUS=$impl_status"
if {$impl_status ne "write_bitstream Complete!"} {
    error "Implementation did not complete: $impl_status"
}

close_project
