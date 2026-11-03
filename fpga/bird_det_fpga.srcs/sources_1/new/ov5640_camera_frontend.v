`timescale 1ns / 1ps

module ov5640_camera_frontend (
    // Asynchronous system reset from the existing BD.
    input  wire        sys_reset_n,
    // Stable 100 MHz PS fabric clock for camera power-up and SCCB.
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 sys_clk CLK" *)
    (* X_INTERFACE_PARAMETER =
        "XIL_INTERFACENAME sys_clk, ASSOCIATED_RESET sys_reset_n, FREQ_HZ 100000000, PHASE 0.000" *)
    input  wire        sys_clk,

    // Software-selectable OV5640 test pattern. Defaults low (real scene).
    input  wire        camera_test_pattern_enable,

    // Physical OV5640 DVP inputs.
    input  wire        cam_pclk,
    input  wire [7:0]  cam_d,
    input  wire        cam_vsync,
    input  wire        cam_href,

    // Physical OV5640 SCCB pins.
    inout  wire        cam_scl,
    inout  wire        cam_sda,

    // Physical OV5640 control outputs.
    output wire        cam_reset_n,
    output wire        cam_pwdn,

    // Buffered camera clock and RGB565 pixel stream.
    
    (* X_INTERFACE_INFO =
       "xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME pixel_clk, ASSOCIATED_RESET pixel_reset_n, FREQ_HZ 12000000, PHASE 0.000" *)
    output wire        pixel_clk,

    (* X_INTERFACE_INFO =
       "xilinx.com:signal:reset:1.0 pixel_reset_n RST" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME pixel_reset_n, POLARITY ACTIVE_LOW" *)
    output wire        pixel_reset_n,

    output wire [15:0] pixel_rgb565,
    output wire        pixel_valid,
    output wire [15:0] pixel_x,
    output wire [15:0] pixel_y,

    output wire        frame_active,
    output wire        frame_start,
    output wire        frame_end,
    output wire        line_start,
    output wire        line_end,

    output wire        last_frame_good,
    output wire        last_odd_byte_error,
    output wire        last_dimension_error,
    output wire [15:0] last_frame_width,
    output wire [15:0] last_frame_height,
    output wire [31:0] last_frame_pixel_count,

    // Camera bring-up status for the PS/AXI status register block.
    output wire        camera_init_done,
    output wire        camera_init_error,
    output wire [15:0] camera_chip_id,
    output wire        camera_chip_id_valid,
    output wire        camera_frame_done,
    output wire [31:0] camera_frame_counter,
    output wire        camera_test_pattern_active,
    output wire        camera_test_pattern_busy
);

    // --------------------------------------------------------
    // Camera PCLK input clock buffer
    // U18 is an MRCC-capable FPGA pin.
    // --------------------------------------------------------

    wire cam_pclk_ibuf;
    wire cam_pclk_bufg;

    IBUF u_cam_pclk_ibuf (
        .I (cam_pclk),
        .O (cam_pclk_ibuf)
    );

    BUFG u_cam_pclk_bufg (
        .I (cam_pclk_ibuf),
        .O (cam_pclk_bufg)
    );

    assign pixel_clk = cam_pclk_bufg;

    // --------------------------------------------------------
    // Reset synchronization into the camera PCLK domain.
    // Reset assertion is asynchronous; release is synchronized.
    // --------------------------------------------------------

    (* ASYNC_REG = "TRUE" *) reg [1:0] pclk_reset_sync;

    always @(posedge cam_pclk_bufg or negedge sys_reset_n) begin
        if (!sys_reset_n)
            pclk_reset_sync <= 2'b00;
        else
            pclk_reset_sync <= {pclk_reset_sync[0], 1'b1};
    end

    wire pclk_reset_n = pclk_reset_sync[1];
    assign pixel_reset_n = pclk_reset_n;

    // --------------------------------------------------------
    // Safe temporary camera control state.
    //
    // The camera remains reset and powered down until the SCCB
    // initialization controller is added in the next stage.
    // --------------------------------------------------------

ov5640_sccb_init u_ov5640_sccb_init (
    .clk         (sys_clk),
    .reset_n     (sys_reset_n),
    .test_pattern_enable (camera_test_pattern_enable),

    .cam_reset_n (cam_reset_n),
    .cam_pwdn    (cam_pwdn),
    .cam_scl     (cam_scl),
    .cam_sda     (cam_sda),

    .init_done     (camera_init_done),
    .init_error    (camera_init_error),
    .chip_id       (camera_chip_id),
    .chip_id_valid (camera_chip_id_valid),
    .test_pattern_active (camera_test_pattern_active),
    .test_pattern_busy   (camera_test_pattern_busy)
);

    // --------------------------------------------------------
    // OV5640 8-bit DVP to RGB565 receiver
    // --------------------------------------------------------

    ov5640_dvp_capture #(
        .FRAME_WIDTH        (320),
        .FRAME_HEIGHT       (240),
        .VSYNC_ACTIVE_LEVEL (1'b1),
        // OV5640 register 0x4300 = 0x6F emits RGB565 low byte first:
        // {G[2:0], B[4:0]} followed by {R[4:0], G[5:3]}.
        .FIRST_BYTE_IS_MSB  (1'b0)
    ) u_ov5640_dvp_capture (
        .pclk                   (cam_pclk_bufg),
        .rst_n                  (pclk_reset_n),
        .cam_vsync              (cam_vsync),
        .cam_href               (cam_href),
        .cam_data               (cam_d),

        .frame_active           (frame_active),
        .frame_start            (frame_start),
        .frame_end              (frame_end),
        .line_start             (line_start),
        .line_end               (line_end),

        .pixel_valid            (pixel_valid),
        .pixel_rgb565           (pixel_rgb565),
        .pixel_x                (pixel_x),
        .pixel_y                (pixel_y),

        .last_frame_good        (last_frame_good),
        .last_odd_byte_error    (last_odd_byte_error),
        .last_dimension_error   (last_dimension_error),
        .last_frame_width       (last_frame_width),
        .last_frame_height      (last_frame_height),
        .last_frame_pixel_count (last_frame_pixel_count)
    );

    // --------------------------------------------------------
    // Frame completion crossing: PCLK-domain toggle -> sys_clk pulse.
    // Software should normally poll camera_frame_counter; the pulse is also
    // exported so the AXI register block can maintain a sticky frame_done bit.
    // --------------------------------------------------------
    reg frame_end_toggle_pclk;
    (* ASYNC_REG = "TRUE" *) reg [1:0] frame_end_toggle_sync;
    reg frame_end_toggle_seen;
    reg [31:0] frame_counter_sys;

    always @(posedge cam_pclk_bufg or negedge pclk_reset_n) begin
        if (!pclk_reset_n)
            frame_end_toggle_pclk <= 1'b0;
        else if (frame_end)
            frame_end_toggle_pclk <= ~frame_end_toggle_pclk;
    end

    always @(posedge sys_clk or negedge sys_reset_n) begin
        if (!sys_reset_n) begin
            frame_end_toggle_sync <= 2'b00;
            frame_end_toggle_seen <= 1'b0;
            frame_counter_sys     <= 32'd0;
        end else begin
            frame_end_toggle_sync <= {frame_end_toggle_sync[0],
                                      frame_end_toggle_pclk};
            frame_end_toggle_seen <= frame_end_toggle_sync[1];
            if (frame_end_toggle_sync[1] != frame_end_toggle_seen)
                frame_counter_sys <= frame_counter_sys + 1'b1;
        end
    end

    assign camera_frame_done    = frame_end_toggle_sync[1] ^
                                  frame_end_toggle_seen;
    assign camera_frame_counter = frame_counter_sys;

endmodule
