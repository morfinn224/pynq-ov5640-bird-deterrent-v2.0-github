`timescale 1ns / 1ps

module tb_ov5640_dvp_capture;

    localparam integer TEST_WIDTH  = 4;
    localparam integer TEST_HEIGHT = 3;

    reg        pclk;
    reg        rst_n;
    reg        cam_vsync;
    reg        cam_href;
    reg [7:0]  cam_data;

    wire        frame_active;
    wire        frame_start;
    wire        frame_end;
    wire        line_start;
    wire        line_end;
    wire        pixel_valid;
    wire [15:0] pixel_rgb565;
    wire [15:0] pixel_x;
    wire [15:0] pixel_y;
    wire        last_frame_good;
    wire        last_odd_byte_error;
    wire        last_dimension_error;
    wire [15:0] last_frame_width;
    wire [15:0] last_frame_height;
    wire [31:0] last_frame_pixel_count;

    integer x_index;
    integer y_index;
    integer valid_pixel_count;
    integer frame_start_count;
    integer frame_end_count;
    integer line_start_count;
    integer line_end_count;
    integer error_count;
    reg [15:0] expected_pixel;
    reg        check_pixel_values;

    ov5640_dvp_capture #(
        .FRAME_WIDTH(TEST_WIDTH),
        .FRAME_HEIGHT(TEST_HEIGHT),
        .VSYNC_ACTIVE_LEVEL(1'b1),
        .FIRST_BYTE_IS_MSB(1'b1)
    ) uut (
        .pclk(pclk),
        .rst_n(rst_n),
        .cam_vsync(cam_vsync),
        .cam_href(cam_href),
        .cam_data(cam_data),
        .frame_active(frame_active),
        .frame_start(frame_start),
        .frame_end(frame_end),
        .line_start(line_start),
        .line_end(line_end),
        .pixel_valid(pixel_valid),
        .pixel_rgb565(pixel_rgb565),
        .pixel_x(pixel_x),
        .pixel_y(pixel_y),
        .last_frame_good(last_frame_good),
        .last_odd_byte_error(last_odd_byte_error),
        .last_dimension_error(last_dimension_error),
        .last_frame_width(last_frame_width),
        .last_frame_height(last_frame_height),
        .last_frame_pixel_count(last_frame_pixel_count)
    );

    always #5 pclk = ~pclk;

    always @(negedge pclk) begin
        if (frame_start)
            frame_start_count = frame_start_count + 1;
        if (frame_end)
            frame_end_count = frame_end_count + 1;
        if (line_start)
            line_start_count = line_start_count + 1;
        if (line_end)
            line_end_count = line_end_count + 1;

        if (pixel_valid && check_pixel_values) begin
            expected_pixel = {8'hA0 + pixel_y[7:0], pixel_x[7:0]};
            if (pixel_rgb565 !== expected_pixel) begin
                $display("ERROR pixel x=%0d y=%0d data=%h expected=%h",
                         pixel_x, pixel_y, pixel_rgb565, expected_pixel);
                error_count = error_count + 1;
            end
            valid_pixel_count = valid_pixel_count + 1;
        end
    end

    task send_valid_frame;
        begin
            @(negedge pclk);
            cam_vsync = 1'b0;
            repeat (2) @(negedge pclk);

            for (y_index = 0; y_index < TEST_HEIGHT; y_index = y_index + 1) begin
                @(negedge pclk);
                cam_href = 1'b1;
                for (x_index = 0; x_index < TEST_WIDTH; x_index = x_index + 1) begin
                    cam_data = 8'hA0 + y_index;
                    @(negedge pclk);
                    cam_data = x_index[7:0];
                    if (x_index != TEST_WIDTH - 1)
                        @(negedge pclk);
                end
                @(negedge pclk);
                cam_href = 1'b0;
                cam_data = 8'd0;
                repeat (2) @(negedge pclk);
            end

            cam_vsync = 1'b1;
            repeat (3) @(negedge pclk);
        end
    endtask

    task send_bad_frame;
        begin
            cam_vsync = 1'b0;
            repeat (2) @(negedge pclk);
            @(negedge pclk);
            cam_href = 1'b1;
            cam_data = 8'h12;
            @(negedge pclk);
            cam_data = 8'h34;
            @(negedge pclk);
            cam_data = 8'h56; // Deliberately leave an unmatched byte.
            @(negedge pclk);
            cam_href = 1'b0;
            cam_data = 8'd0;
            repeat (2) @(negedge pclk);
            cam_vsync = 1'b1;
            repeat (3) @(negedge pclk);
        end
    endtask

    initial begin
        pclk               = 1'b0;
        rst_n              = 1'b0;
        cam_vsync          = 1'b1;
        cam_href           = 1'b0;
        cam_data           = 8'd0;
        valid_pixel_count  = 0;
        frame_start_count  = 0;
        frame_end_count    = 0;
        line_start_count   = 0;
        line_end_count     = 0;
        error_count        = 0;
        check_pixel_values = 1'b1;

        repeat (4) @(negedge pclk);
        rst_n = 1'b1;
        repeat (2) @(negedge pclk);

        send_valid_frame();

        if (!last_frame_good || last_odd_byte_error ||
            last_dimension_error ||
            (last_frame_width != TEST_WIDTH) ||
            (last_frame_height != TEST_HEIGHT) ||
            (last_frame_pixel_count != TEST_WIDTH * TEST_HEIGHT) ||
            (valid_pixel_count != TEST_WIDTH * TEST_HEIGHT) ||
            (line_start_count != TEST_HEIGHT) ||
            (line_end_count != TEST_HEIGHT)) begin
            $display("ERROR valid frame summary good=%0d odd=%0d dim=%0d width=%0d height=%0d pixels=%0d stream_pixels=%0d lines=%0d/%0d",
                     last_frame_good, last_odd_byte_error,
                     last_dimension_error, last_frame_width,
                     last_frame_height, last_frame_pixel_count,
                     valid_pixel_count, line_start_count, line_end_count);
            error_count = error_count + 1;
        end
        else begin
            $display("PASS valid 4x3 RGB565 frame");
        end

        check_pixel_values = 1'b0;
        send_bad_frame();

        if (last_frame_good || !last_odd_byte_error ||
            !last_dimension_error) begin
            $display("ERROR malformed frame was not rejected good=%0d odd=%0d dim=%0d",
                     last_frame_good, last_odd_byte_error,
                     last_dimension_error);
            error_count = error_count + 1;
        end
        else begin
            $display("PASS malformed frame rejected");
        end

        if ((frame_start_count != 2) || (frame_end_count != 2)) begin
            $display("ERROR frame pulse counts start=%0d end=%0d",
                     frame_start_count, frame_end_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("ALL OV5640 DVP CAPTURE TESTS PASSED");
        else
            $display("OV5640 DVP CAPTURE TEST FAILED error_count=%0d",
                     error_count);

        $finish;
    end

endmodule
