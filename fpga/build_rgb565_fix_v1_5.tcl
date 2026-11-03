set project_dir {C:/Users/17550/Documents/Codex/2026-09-28/new-chat/bird_det_fpga_camera_realscene_v2}
set project_file [file join $project_dir bird_det_fpga.xpr]
set bd_file [file join $project_dir bird_det_fpga.srcs sources_1 bd pynq_frame_diff_bd pynq_frame_diff_bd.bd]

open_project $project_file

# Use the updated AXI control source so VERSION reports 0x00010500.
set old_ctrl_files [get_files -quiet *frame_diff_ctrl_axi.v]
if {[llength $old_ctrl_files] > 0} {
    remove_files $old_ctrl_files
}
add_files -norecurse [file join $project_dir local_src frame_diff_ctrl_axi.v]
update_compile_order -fileset sources_1

open_bd_design $bd_file
update_module_reference -verbose [get_ips pynq_frame_diff_bd_frame_diff_ctrl_axi_test_0]
update_module_reference -verbose [get_ips pynq_frame_diff_bd_ov5640_camera_test_1]

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

set bit_src [file join $project_dir bird_det_fpga.runs impl_1 pynq_frame_diff_bd_wrapper.bit]
set hwh_src [file join $project_dir bird_det_fpga.gen sources_1 bd pynq_frame_diff_bd hw_handoff pynq_frame_diff_bd.hwh]
set out_dir [file join $project_dir pynq_overlay_camera_v1_5_rgb565_fix]
file mkdir $out_dir
file copy -force $bit_src [file join $out_dir pynq_frame_diff_bd_wrapper.bit]
file copy -force $hwh_src [file join $out_dir pynq_frame_diff_bd_wrapper.hwh]

puts "BIT_OUTPUT=[file join $out_dir pynq_frame_diff_bd_wrapper.bit]"
puts "HWH_OUTPUT=[file join $out_dir pynq_frame_diff_bd_wrapper.hwh]"

close_project
