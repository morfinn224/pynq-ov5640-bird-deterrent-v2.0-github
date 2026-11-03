set project_dir {C:/Users/17550/Documents/Codex/2026-09-28/new-chat/bird_det_fpga_camera_realscene_v2}
set project_file [file join $project_dir bird_det_fpga.xpr]

open_project $project_file
set old_ctrl_files [get_files -quiet *frame_diff_ctrl_axi.v]
if {[llength $old_ctrl_files] > 0} {
    remove_files $old_ctrl_files
}
add_files -norecurse [file join $project_dir local_src frame_diff_ctrl_axi.v]
update_compile_order -fileset sources_1

open_bd_design [file join $project_dir bird_det_fpga.srcs sources_1 bd pynq_frame_diff_bd pynq_frame_diff_bd.bd]
update_module_reference -verbose [get_ips pynq_frame_diff_bd_frame_diff_ctrl_axi_test_0]
update_module_reference -verbose [get_ips pynq_frame_diff_bd_ov5640_camera_test_1]

set ctrl_pin [get_bd_pins frame_diff_ctrl_axi_0/camera_test_pattern_enable]
set cam_req_pin [get_bd_pins ov5640_camera_fronte_0/camera_test_pattern_enable]
set cam_active_pin [get_bd_pins ov5640_camera_fronte_0/camera_test_pattern_active]
set ctrl_active_pin [get_bd_pins frame_diff_ctrl_axi_0/camera_test_pattern_active]
set cam_busy_pin [get_bd_pins ov5640_camera_fronte_0/camera_test_pattern_busy]
set ctrl_busy_pin [get_bd_pins frame_diff_ctrl_axi_0/camera_test_pattern_busy]

connect_bd_net $ctrl_pin $cam_req_pin
connect_bd_net $cam_active_pin $ctrl_active_pin
connect_bd_net $cam_busy_pin $ctrl_busy_pin

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
