`timescale 1ns / 1ps

module rgb565_axis_source #(
    parameter integer FRAME_WIDTH  = 320,
    parameter integer FRAME_HEIGHT = 240
)(
    // Camera pixel-clock domain
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME pixel_clk, ASSOCIATED_BUSIF M_AXIS_VIDEO, ASSOCIATED_RESET aresetn, FREQ_HZ 12000000" *)
    input  wire        pixel_clk,

    // Asynchronous active-low reset; synchronized internally
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,

    // Pixel input from ov5640_camera_frontend
    input  wire [15:0] pixel_rgb565,
    input  wire        pixel_valid,
    input  wire [15:0] pixel_x,
    input  wire [15:0] pixel_y,

    // AXI4-Stream video output
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TDATA" *)
    output reg  [15:0] m_axis_tdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TKEEP" *)
    output wire [1:0]  m_axis_tkeep,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TVALID" *)
    output reg         m_axis_tvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TREADY" *)
    input  wire        m_axis_tready,

    // TUSER[0] marks the first pixel of a frame
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TUSER" *)
    output reg         m_axis_tuser,

    // TLAST marks the last pixel of each line
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_VIDEO TLAST" *)
    output reg         m_axis_tlast,

    // Sticky diagnostic flag: downstream could not accept a pixel
    output reg         overflow
);

    // Reset synchronizer for the camera pixel-clock domain
    reg [1:0] reset_sync;

    always @(posedge pixel_clk or negedge aresetn) begin
        if (!aresetn)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    wire pixel_reset_n = reset_sync[1];

    // Both bytes of every RGB565 pixel are valid
    assign m_axis_tkeep = 2'b11;

    // The output register may be replaced when empty or consumed.
    wire output_available = !m_axis_tvalid || m_axis_tready;

    always @(posedge pixel_clk) begin
        if (!pixel_reset_n) begin
            m_axis_tdata  <= 16'h0000;
            m_axis_tvalid <= 1'b0;
            m_axis_tuser  <= 1'b0;
            m_axis_tlast  <= 1'b0;
            overflow      <= 1'b0;
        end
        else begin
            // Remove a word after a successful AXI4-Stream transfer.
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            if (pixel_valid) begin
                if (output_available) begin
                    m_axis_tdata  <= pixel_rgb565;
                    m_axis_tvalid <= 1'b1;

                    // Start of frame: first pixel at coordinate (0,0)
                    m_axis_tuser  <=
                        (pixel_x == 16'd0) &&
                        (pixel_y == 16'd0);

                    // End of line: pixel x = FRAME_WIDTH - 1
                    m_axis_tlast  <=
                        (pixel_x == FRAME_WIDTH - 1);
                end
                else begin
                    // The camera cannot be paused, so record any overflow.
                    overflow <= 1'b1;
                end
            end
        end
    end

endmodule