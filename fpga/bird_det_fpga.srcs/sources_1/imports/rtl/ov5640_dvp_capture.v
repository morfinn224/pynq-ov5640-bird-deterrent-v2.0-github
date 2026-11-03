`timescale 1ns / 1ps

// OV5640 8-bit DVP to RGB565 pixel-stream receiver.
//
// Assumptions for the first integration version:
// - The module is clocked directly by the camera PCLK.
// - VSYNC is active high between frames (configurable).
// - HREF is high while line bytes are valid.
// - RGB565 is sent high byte first (configurable).
//
// This block only receives and checks the stream. Clock-domain crossing and
// frame-buffer writing belong in the next integration layer.
module ov5640_dvp_capture #(
    parameter integer FRAME_WIDTH        = 640,
    parameter integer FRAME_HEIGHT       = 480,
    parameter         VSYNC_ACTIVE_LEVEL = 1'b1,
    parameter         FIRST_BYTE_IS_MSB  = 1'b1
)(
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,

    output reg         frame_active,
    output reg         frame_start,
    output reg         frame_end,
    output reg         line_start,
    output reg         line_end,

    output reg         pixel_valid,
    output reg [15:0]  pixel_rgb565,
    output reg [15:0]  pixel_x,
    output reg [15:0]  pixel_y,

    output reg         last_frame_good,
    output reg         last_odd_byte_error,
    output reg         last_dimension_error,
    output reg [15:0]  last_frame_width,
    output reg [15:0]  last_frame_height,
    output reg [31:0]  last_frame_pixel_count
);

    localparam integer EXPECTED_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

    wire vsync_active = (cam_vsync == VSYNC_ACTIVE_LEVEL);

    reg        vsync_active_d;
    reg        href_d;
    reg        byte_phase;
    reg [7:0]  first_byte;
    reg [15:0] line_pixel_count;
    reg [15:0] frame_line_count;
    reg [31:0] frame_pixel_count;
    reg [15:0] maximum_line_width;
    reg        odd_byte_error_work;
    reg        dimension_error_work;

    wire frame_start_event =  vsync_active_d && !vsync_active;
    wire frame_end_event   = !vsync_active_d &&  vsync_active;
    wire line_start_event  = !href_d && cam_href && frame_active;
    wire line_end_event    =  href_d && !cam_href && frame_active;

    always @(posedge pclk) begin
        if (!rst_n) begin
            vsync_active_d          <= 1'b1;
            href_d                  <= 1'b0;
            frame_active            <= 1'b0;
            frame_start             <= 1'b0;
            frame_end               <= 1'b0;
            line_start              <= 1'b0;
            line_end                <= 1'b0;
            pixel_valid             <= 1'b0;
            pixel_rgb565            <= 16'd0;
            pixel_x                 <= 16'd0;
            pixel_y                 <= 16'd0;
            byte_phase              <= 1'b0;
            first_byte              <= 8'd0;
            line_pixel_count        <= 16'd0;
            frame_line_count        <= 16'd0;
            frame_pixel_count       <= 32'd0;
            maximum_line_width      <= 16'd0;
            odd_byte_error_work     <= 1'b0;
            dimension_error_work    <= 1'b0;
            last_frame_good         <= 1'b0;
            last_odd_byte_error     <= 1'b0;
            last_dimension_error    <= 1'b0;
            last_frame_width        <= 16'd0;
            last_frame_height       <= 16'd0;
            last_frame_pixel_count  <= 32'd0;
        end
        else begin
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            line_start  <= 1'b0;
            line_end    <= 1'b0;
            pixel_valid <= 1'b0;

            vsync_active_d <= vsync_active;
            href_d         <= cam_href;

            if (frame_start_event) begin
                frame_active         <= 1'b1;
                frame_start          <= 1'b1;
                byte_phase           <= 1'b0;
                line_pixel_count     <= 16'd0;
                frame_line_count     <= 16'd0;
                frame_pixel_count    <= 32'd0;
                maximum_line_width   <= 16'd0;
                odd_byte_error_work  <= 1'b0;
                dimension_error_work <= 1'b0;
            end

            if (line_start_event) begin
                line_start       <= 1'b1;
                byte_phase       <= 1'b0;
                line_pixel_count <= 16'd0;
            end

            if (frame_active && cam_href && !vsync_active) begin
                if (!byte_phase) begin
                    first_byte <= cam_data;
                    byte_phase <= 1'b1;
                end
                else begin
                    if (FIRST_BYTE_IS_MSB)
                        pixel_rgb565 <= {first_byte, cam_data};
                    else
                        pixel_rgb565 <= {cam_data, first_byte};

                    pixel_valid       <= 1'b1;
                    pixel_x           <= line_pixel_count;
                    pixel_y           <= frame_line_count;
                    line_pixel_count  <= line_pixel_count + 1'b1;
                    frame_pixel_count <= frame_pixel_count + 1'b1;
                    byte_phase        <= 1'b0;
                end
            end

            if (line_end_event) begin
                line_end <= 1'b1;

                if (line_pixel_count > maximum_line_width)
                    maximum_line_width <= line_pixel_count;

                if (byte_phase)
                    odd_byte_error_work <= 1'b1;

                if (line_pixel_count != FRAME_WIDTH)
                    dimension_error_work <= 1'b1;

                frame_line_count <= frame_line_count + 1'b1;
                byte_phase       <= 1'b0;
            end

            if (frame_end_event) begin
                frame_active           <= 1'b0;
                frame_end              <= 1'b1;
                byte_phase             <= 1'b0;
                last_odd_byte_error    <= odd_byte_error_work;
                last_dimension_error   <= dimension_error_work ||
                                          (frame_line_count != FRAME_HEIGHT) ||
                                          (frame_pixel_count != EXPECTED_PIXELS);
                last_frame_width       <= maximum_line_width;
                last_frame_height      <= frame_line_count;
                last_frame_pixel_count <= frame_pixel_count;
                last_frame_good        <= !odd_byte_error_work &&
                                          !dimension_error_work &&
                                          (frame_line_count == FRAME_HEIGHT) &&
                                          (frame_pixel_count == EXPECTED_PIXELS);
            end

            if (vsync_active) begin
                byte_phase <= 1'b0;
            end
        end
    end

endmodule
