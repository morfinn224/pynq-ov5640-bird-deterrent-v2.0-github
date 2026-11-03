`timescale 1ns / 1ps

module ov5640_sccb_init (
    input  wire clk,
    input  wire reset_n,
    input  wire test_pattern_enable,

    output reg  cam_reset_n,
    output reg  cam_pwdn,
    inout  wire cam_scl,
    inout  wire cam_sda,

    output reg  init_done,
    output reg  init_error,
    output reg  [15:0] chip_id,
    output reg         chip_id_valid,
    output reg         test_pattern_active,
    output wire        test_pattern_busy
);
    
    localparam integer WAIT_1MS  = 100_000;
    localparam integer WAIT_10MS = 1_000_000;
    localparam integer WAIT_20MS = 2_000_000;
    localparam integer CFG_COUNT = 175;

    localparam P_POWER_HOLD   = 4'd0;
    localparam P_PWDN_WAIT    = 4'd1;
    localparam P_RESET_WAIT   = 4'd2;
    localparam P_ID_HI_ISSUE  = 4'd3;
    localparam P_ID_HI_WAIT   = 4'd4;
    localparam P_ID_LO_ISSUE  = 4'd5;
    localparam P_ID_LO_WAIT   = 4'd6;
    localparam P_ISSUE        = 4'd7;
    localparam P_WAIT_WRITE   = 4'd8;
    localparam P_SOFT_WAIT    = 4'd9;
    localparam P_FINISHED     = 4'd10;
    localparam P_ERROR        = 4'd11;
    localparam P_TEST_ISSUE   = 4'd12;
    localparam P_TEST_WAIT    = 4'd13;
    reg [3:0]  power_state;
    reg [21:0] delay_count;
    reg [7:0]  cfg_index;

    reg         sccb_start;
    wire        sccb_busy;
    wire        sccb_done;
    reg         sccb_read;
    reg  [15:0] sccb_reg_addr;
    reg  [7:0]  sccb_write_data;
    wire [7:0]  sccb_read_data;
    wire        sccb_ack_error;
    wire [23:0] current_word;

    /*
     * First-board validation profile, based on the Zephyr OV5640 DVP driver:
     * 320x240, RGB565, 30 fps timing, DVP D[7:0], real-scene output.
     * Register 0x503D defaults to 0x00. Software may later select 0x84
     * through the AXI camera-test-pattern control register.
     */
    function [23:0] cfg_word;
        input [7:0] index;
        begin
            case (index)
                8'd0: cfg_word = {16'h3008, 8'h82}; // Software reset; wait 10 ms
                8'd1: cfg_word = {16'h3008, 8'h42}; // Software standby
                8'd2: cfg_word = {16'h3103, 8'h13}; // System clock from PLL
                8'd3: cfg_word = {16'h3103, 8'h03}; // System clock setup
                8'd4: cfg_word = {16'h3000, 8'h00}; // Release system blocks
                8'd5: cfg_word = {16'h3004, 8'hFF}; // Enable clocks
                8'd6: cfg_word = {16'h3002, 8'h1C}; // Reset DVP-related blocks before setup
                8'd7: cfg_word = {16'h3006, 8'hC3}; // Enable required clocks
                8'd8: cfg_word = {16'h302E, 8'h08}; // System control
                8'd9: cfg_word = {16'h3618, 8'h00}; // Analog control
                8'd10: cfg_word = {16'h3612, 8'h29}; // Analog control
                8'd11: cfg_word = {16'h3708, 8'h64}; // Sensor timing
                8'd12: cfg_word = {16'h3709, 8'h52}; // Sensor timing
                8'd13: cfg_word = {16'h370C, 8'h03}; // Sensor timing
                8'd14: cfg_word = {16'h3820, 8'h41}; // Timing orientation
                8'd15: cfg_word = {16'h3821, 8'h07}; // Timing orientation
                8'd16: cfg_word = {16'h3630, 8'h36}; // Analog control
                8'd17: cfg_word = {16'h3631, 8'h0E}; // Analog control
                8'd18: cfg_word = {16'h3632, 8'hE2}; // Analog control
                8'd19: cfg_word = {16'h3633, 8'h12}; // Analog control
                8'd20: cfg_word = {16'h3621, 8'hE0}; // Analog control
                8'd21: cfg_word = {16'h3704, 8'hA0}; // Sensor timing
                8'd22: cfg_word = {16'h3703, 8'h5A}; // Sensor timing
                8'd23: cfg_word = {16'h3715, 8'h78}; // Sensor timing
                8'd24: cfg_word = {16'h3717, 8'h01}; // Sensor timing
                8'd25: cfg_word = {16'h370B, 8'h60}; // Sensor timing
                8'd26: cfg_word = {16'h3705, 8'h1A}; // Sensor timing
                8'd27: cfg_word = {16'h3905, 8'h02}; // Analog control
                8'd28: cfg_word = {16'h3906, 8'h10}; // Analog control
                8'd29: cfg_word = {16'h3901, 8'h0A}; // Analog control
                8'd30: cfg_word = {16'h3731, 8'h12}; // Sensor timing
                8'd31: cfg_word = {16'h3600, 8'h08}; // Analog control
                8'd32: cfg_word = {16'h3601, 8'h33}; // Analog control
                8'd33: cfg_word = {16'h302D, 8'h60}; // System control
                8'd34: cfg_word = {16'h3620, 8'h52}; // Analog control
                8'd35: cfg_word = {16'h371B, 8'h20}; // Sensor timing
                8'd36: cfg_word = {16'h471C, 8'h50}; // DVP control
                8'd37: cfg_word = {16'h3A13, 8'h43}; // AEC control
                8'd38: cfg_word = {16'h3A18, 8'h00}; // AEC gain ceiling high
                8'd39: cfg_word = {16'h3A19, 8'h7C}; // AEC gain ceiling low
                8'd40: cfg_word = {16'h3635, 8'h13}; // Analog control
                8'd41: cfg_word = {16'h3636, 8'h03}; // Analog control
                8'd42: cfg_word = {16'h3634, 8'h40}; // Analog control
                8'd43: cfg_word = {16'h3622, 8'h01}; // Analog control
                8'd44: cfg_word = {16'h3C01, 8'h00}; // 50/60 Hz control
                8'd45: cfg_word = {16'h3A00, 8'h58}; // AEC control
                8'd46: cfg_word = {16'h4001, 8'h02}; // Black-level control
                8'd47: cfg_word = {16'h4004, 8'h02}; // Black-level control
                8'd48: cfg_word = {16'h4005, 8'h1A}; // Black-level control
                8'd49: cfg_word = {16'h5001, 8'hA3}; // Enable ISP functions
                8'd50: cfg_word = {16'h3A0F, 8'h30}; // AEC stable range
                8'd51: cfg_word = {16'h3A10, 8'h28}; // AEC stable range
                8'd52: cfg_word = {16'h3A1B, 8'h30}; // AEC stable range
                8'd53: cfg_word = {16'h3A1E, 8'h26}; // AEC stable range
                8'd54: cfg_word = {16'h3A11, 8'h60}; // AEC stable range
                8'd55: cfg_word = {16'h3A1F, 8'h14}; // AEC stable range
                8'd56: cfg_word = {16'h4050, 8'h6E}; // DVP black-level control
                8'd57: cfg_word = {16'h4051, 8'h8F}; // DVP black-level control
                8'd58: cfg_word = {16'h3017, 8'hFF}; // Enable DVP data pins
                8'd59: cfg_word = {16'h3018, 8'hFF}; // Enable DVP control pins
                8'd60: cfg_word = {16'h302C, 8'h02}; // DVP drive strength
                8'd61: cfg_word = {16'h3630, 8'h2E}; // DVP analog tuning
                8'd62: cfg_word = {16'h3635, 8'h1C}; // DVP analog tuning
                8'd63: cfg_word = {16'h300E, 8'h58}; // Disable MIPI; use DVP
                8'd64: cfg_word = {16'h302E, 8'h00}; // DVP system control
                8'd65: cfg_word = {16'h4713, 8'h04}; // DVP mode
                8'd66: cfg_word = {16'h4407, 8'h04}; // DVP output control
                8'd67: cfg_word = {16'h460B, 8'h35}; // DVP timing
                8'd68: cfg_word = {16'h3406, 8'h00}; // Enable automatic white balance
                8'd69: cfg_word = {16'h3503, 8'h00}; // Enable automatic exposure/gain
                8'd70: cfg_word = {16'h3800, 8'h00}; // QVGA sensor X start high
                8'd71: cfg_word = {16'h3801, 8'h10}; // QVGA sensor X start low
                8'd72: cfg_word = {16'h3802, 8'h00}; // QVGA sensor Y start high
                8'd73: cfg_word = {16'h3803, 8'h0E}; // QVGA sensor Y start low
                8'd74: cfg_word = {16'h3804, 8'h0A}; // QVGA sensor X end high
                8'd75: cfg_word = {16'h3805, 8'h2F}; // QVGA sensor X end low
                8'd76: cfg_word = {16'h3806, 8'h07}; // QVGA sensor Y end high
                8'd77: cfg_word = {16'h3807, 8'hA5}; // QVGA sensor Y end low
                8'd78: cfg_word = {16'h3808, 8'h01}; // Output width 320 high
                8'd79: cfg_word = {16'h3809, 8'h40}; // Output width 320 low
                8'd80: cfg_word = {16'h380A, 8'h00}; // Output height 240 high
                8'd81: cfg_word = {16'h380B, 8'hF0}; // Output height 240 low
                8'd82: cfg_word = {16'h380C, 8'h06}; // HTS 1600 high
                8'd83: cfg_word = {16'h380D, 8'h40}; // HTS 1600 low
                8'd84: cfg_word = {16'h380E, 8'h03}; // VTS 1000 high
                8'd85: cfg_word = {16'h380F, 8'hE8}; // VTS 1000 low
                8'd86: cfg_word = {16'h3810, 8'h00}; // Horizontal offset high
                8'd87: cfg_word = {16'h3811, 8'h02}; // Horizontal offset low
                8'd88: cfg_word = {16'h3812, 8'h00}; // Vertical offset high
                8'd89: cfg_word = {16'h3813, 8'h04}; // Vertical offset low
                8'd90: cfg_word = {16'h3814, 8'h31}; // Horizontal subsample
                8'd91: cfg_word = {16'h3815, 8'h31}; // Vertical subsample
                8'd92: cfg_word = {16'h3824, 8'h02}; // Manual DVP PCLK divider
                8'd93: cfg_word = {16'h460C, 8'h22}; // DVP PCLK divider mode
                8'd94: cfg_word = {16'h4300, 8'h6F}; // RGB565 byte order
                8'd95: cfg_word = {16'h501F, 8'h01}; // ISP RGB output
                8'd96: cfg_word = {16'h3821, 8'h07}; // DVP mode; clear MIPI timing bit
                8'd97: cfg_word = {16'h3002, 8'h1C}; // Release DVP reset mask
                8'd98: cfg_word = {16'h3006, 8'hC3}; // Keep DVP clocks enabled
                8'd99: cfg_word = {16'h3035, 8'h21}; // 30 fps PLL divider
                8'd100: cfg_word = {16'h3036, 8'h60}; // 30 fps PLL multiplier
                8'd101: cfg_word = {16'h4837, 8'h0A}; // Pixel-clock period
                8'd102: cfg_word = {16'h3034, 8'h18}; // 8-bit system mode
                8'd103: cfg_word = {16'h3037, 8'h13}; // PLL root/pre divider
                8'd104: cfg_word = {16'h3108, 8'h01}; // PCLK/SCLK root dividers
                // The ATK 8-bit module exposes sensor D[9:2] and relabels
                // those lines as module D[7:0].  DATA_ORDER=0 selects that
                // route.  0x02 instead leaves module D6/D7 stuck at zero.
                8'd105: cfg_word = {16'h4745, 8'h00}; // Sensor D[9:2] -> module D[7:0]
                // FPGA samples DVP on PCLK rising edges.  Make the sensor update
                // data on falling edges so setup/hold time is available.
                8'd106: cfg_word = {16'h4740, 8'h20}; // PCLK update falling; HREF/VSYNC unchanged
                8'd107: cfg_word = {16'h503D, 8'h00}; // Disable test pattern; real-scene default

                // Complete ISP colour pipeline.  The earlier compact table
                // enabled ISP/SDE in 0x5001 but left the post-reset AWB,
                // colour-matrix, gamma and saturation controls uninitialised.
                // On this module that produced valid RGB565 timing but only
                // neutral (black/white/grey) pixels.  These values match the
                // upstream Linux OV5640 global initialisation profile.
                8'd108: cfg_word = {16'h5000, 8'hA7}; // LENC/raw gamma/BPC/WPC/AWB gain
                8'd109: cfg_word = {16'h5180, 8'hFF};
                8'd110: cfg_word = {16'h5181, 8'hF2};
                8'd111: cfg_word = {16'h5182, 8'h00};
                8'd112: cfg_word = {16'h5183, 8'h14};
                8'd113: cfg_word = {16'h5184, 8'h25};
                8'd114: cfg_word = {16'h5185, 8'h24};
                8'd115: cfg_word = {16'h5186, 8'h09};
                8'd116: cfg_word = {16'h5187, 8'h09};
                8'd117: cfg_word = {16'h5188, 8'h09};
                8'd118: cfg_word = {16'h5189, 8'h88};
                8'd119: cfg_word = {16'h518A, 8'h54};
                8'd120: cfg_word = {16'h518B, 8'hEE};
                8'd121: cfg_word = {16'h518C, 8'hB2};
                8'd122: cfg_word = {16'h518D, 8'h50};
                8'd123: cfg_word = {16'h518E, 8'h34};
                8'd124: cfg_word = {16'h518F, 8'h6B};
                8'd125: cfg_word = {16'h5190, 8'h46};
                8'd126: cfg_word = {16'h5191, 8'hF8};
                8'd127: cfg_word = {16'h5192, 8'h04};
                8'd128: cfg_word = {16'h5193, 8'h70};
                8'd129: cfg_word = {16'h5194, 8'hF0};
                8'd130: cfg_word = {16'h5195, 8'hF0};
                8'd131: cfg_word = {16'h5196, 8'h03};
                8'd132: cfg_word = {16'h5197, 8'h01};
                8'd133: cfg_word = {16'h5198, 8'h04};
                8'd134: cfg_word = {16'h5199, 8'h6C};
                8'd135: cfg_word = {16'h519A, 8'h04};
                8'd136: cfg_word = {16'h519B, 8'h00};
                8'd137: cfg_word = {16'h519C, 8'h09};
                8'd138: cfg_word = {16'h519D, 8'h2B};
                8'd139: cfg_word = {16'h519E, 8'h38};
                8'd140: cfg_word = {16'h5381, 8'h1E};
                8'd141: cfg_word = {16'h5382, 8'h5B};
                8'd142: cfg_word = {16'h5383, 8'h08};
                8'd143: cfg_word = {16'h5384, 8'h0A};
                8'd144: cfg_word = {16'h5385, 8'h7E};
                8'd145: cfg_word = {16'h5386, 8'h88};
                8'd146: cfg_word = {16'h5387, 8'h7C};
                8'd147: cfg_word = {16'h5388, 8'h6C};
                8'd148: cfg_word = {16'h5389, 8'h10};
                8'd149: cfg_word = {16'h538A, 8'h01};
                8'd150: cfg_word = {16'h538B, 8'h98};
                8'd151: cfg_word = {16'h5480, 8'h01};
                8'd152: cfg_word = {16'h5481, 8'h08};
                8'd153: cfg_word = {16'h5482, 8'h14};
                8'd154: cfg_word = {16'h5483, 8'h28};
                8'd155: cfg_word = {16'h5484, 8'h51};
                8'd156: cfg_word = {16'h5485, 8'h65};
                8'd157: cfg_word = {16'h5486, 8'h71};
                8'd158: cfg_word = {16'h5487, 8'h7D};
                8'd159: cfg_word = {16'h5488, 8'h87};
                8'd160: cfg_word = {16'h5489, 8'h91};
                8'd161: cfg_word = {16'h548A, 8'h9A};
                8'd162: cfg_word = {16'h548B, 8'hAA};
                8'd163: cfg_word = {16'h548C, 8'hB8};
                8'd164: cfg_word = {16'h548D, 8'hCD};
                8'd165: cfg_word = {16'h548E, 8'hDD};
                8'd166: cfg_word = {16'h548F, 8'hEA};
                8'd167: cfg_word = {16'h5490, 8'h1D};
                8'd168: cfg_word = {16'h5580, 8'h02}; // Enable normal saturation path
                8'd169: cfg_word = {16'h5583, 8'h40}; // U saturation
                8'd170: cfg_word = {16'h5584, 8'h10}; // V saturation
                8'd171: cfg_word = {16'h5589, 8'h10};
                8'd172: cfg_word = {16'h558A, 8'h00};
                8'd173: cfg_word = {16'h558B, 8'hF8};
                8'd174: cfg_word = {16'h3008, 8'h02}; // Leave standby and start streaming
                default: cfg_word = 24'h000000;
            endcase
        end
    endfunction

    assign current_word = cfg_word(cfg_index);
    assign test_pattern_busy = (power_state == P_TEST_ISSUE) ||
                               (power_state == P_TEST_WAIT);

    ov5640_sccb_master #(
        .CLK_DIV        (500),
        .DEVICE_ADDRESS (7'h3c)
    ) u_sccb_master (
        .clk              (clk),
        .rst_n            (reset_n),
        .start            (sccb_start),
        .read_not_write   (sccb_read),
        .register_address (sccb_reg_addr),
        .write_data       (sccb_write_data),
        .read_data        (sccb_read_data),
        .busy             (sccb_busy),
        .done             (sccb_done),
        .ack_error        (sccb_ack_error),
        .sccb_scl         (cam_scl),
        .sccb_sda         (cam_sda)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cam_reset_n <= 1'b0;
            cam_pwdn    <= 1'b1;
            init_done   <= 1'b0;
            init_error  <= 1'b0;
            chip_id     <= 16'd0;
            chip_id_valid <= 1'b0;
            test_pattern_active <= 1'b0;
            sccb_start  <= 1'b0;
            sccb_read   <= 1'b0;
            sccb_reg_addr <= 16'd0;
            sccb_write_data <= 8'd0;
            power_state <= P_POWER_HOLD;
            delay_count <= 22'd0;
            cfg_index   <= 8'd0;
        end else begin
            sccb_start <= 1'b0;

            case (power_state)
                P_POWER_HOLD: begin
                    cam_reset_n <= 1'b0;
                    cam_pwdn    <= 1'b1;

                    if (delay_count == WAIT_1MS - 1) begin
                        delay_count <= 22'd0;
                        cam_pwdn    <= 1'b0;
                        power_state <= P_PWDN_WAIT;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                P_PWDN_WAIT: begin
                    if (delay_count == WAIT_1MS - 1) begin
                        delay_count <= 22'd0;
                        cam_reset_n <= 1'b1;
                        power_state <= P_RESET_WAIT;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                P_RESET_WAIT: begin
                    if (delay_count == WAIT_20MS - 1) begin
                        delay_count <= 22'd0;
                        power_state <= P_ID_HI_ISSUE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                P_ID_HI_ISSUE: begin
                    if (!sccb_busy) begin
                        sccb_read       <= 1'b1;
                        sccb_reg_addr   <= 16'h300A;
                        sccb_write_data <= 8'd0;
                        sccb_start      <= 1'b1;
                        power_state     <= P_ID_HI_WAIT;
                    end
                end

                P_ID_HI_WAIT: begin
                    if (sccb_done) begin
                        chip_id[15:8] <= sccb_read_data;
                        power_state   <= P_ID_LO_ISSUE;
                    end
                end

                P_ID_LO_ISSUE: begin
                    if (!sccb_busy) begin
                        sccb_read       <= 1'b1;
                        sccb_reg_addr   <= 16'h300B;
                        sccb_write_data <= 8'd0;
                        sccb_start      <= 1'b1;
                        power_state     <= P_ID_LO_WAIT;
                    end
                end

                P_ID_LO_WAIT: begin
                    if (sccb_done) begin
                        chip_id[7:0] <= sccb_read_data;
                        chip_id_valid <= 1'b1;
                        if ({chip_id[15:8], sccb_read_data} == 16'h5640) begin
                            cfg_index   <= 8'd0;
                            power_state <= P_ISSUE;
                        end else begin
                            init_error  <= 1'b1;
                            power_state <= P_ERROR;
                        end
                    end
                end

                P_ISSUE: begin
                    if (!sccb_busy) begin
                        sccb_read       <= 1'b0;
                        sccb_reg_addr   <= current_word[23:8];
                        sccb_write_data <= current_word[7:0];
                        sccb_start      <= 1'b1;
                        power_state     <= P_WAIT_WRITE;
                    end
                end

                P_WAIT_WRITE: begin
                    if (sccb_done) begin
                        if (cfg_index == 0) begin
                            delay_count <= 22'd0;
                            cfg_index   <= 8'd1;
                            power_state <= P_SOFT_WAIT;
                        end else if (cfg_index == CFG_COUNT - 1) begin
                            init_done   <= 1'b1;
                            power_state <= P_FINISHED;
                        end else begin
                            cfg_index   <= cfg_index + 1'b1;
                            power_state <= P_ISSUE;
                        end
                    end
                end

                P_SOFT_WAIT: begin
                    if (delay_count == WAIT_10MS - 1) begin
                        delay_count <= 22'd0;
                        power_state <= P_ISSUE;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end

                P_FINISHED: begin
                    init_done <= 1'b1;
                    if (test_pattern_enable != test_pattern_active)
                        power_state <= P_TEST_ISSUE;
                end
                P_TEST_ISSUE: begin
                    if (!sccb_busy) begin
                        sccb_read       <= 1'b0;
                        sccb_reg_addr   <= 16'h503D;
                        sccb_write_data <= test_pattern_enable ? 8'h80 : 8'h00;
                        sccb_start      <= 1'b1;
                        power_state     <= P_TEST_WAIT;
                    end
                end
                P_TEST_WAIT: begin
                    if (sccb_done) begin
                        if (sccb_ack_error) begin
                            init_error  <= 1'b1;
                            power_state <= P_ERROR;
                        end else begin
                            test_pattern_active <= test_pattern_enable;
                            power_state <= P_FINISHED;
                        end
                    end
                end
                P_ERROR: begin
                    init_done  <= 1'b0;
                    init_error <= 1'b1;
                end
                default: begin
                    power_state <= P_POWER_HOLD;
                end
            endcase
        end
    end

endmodule


module ov5640_sccb_write #(
    parameter integer CLK_HZ  = 100_000_000,
    parameter integer SCCB_HZ = 100_000
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [15:0] reg_addr,
    input  wire [7:0]  reg_data,

    output reg         busy,
    output reg         done,
    output reg         nack,

    inout  wire        cam_scl,
    inout  wire        cam_sda
);

    localparam integer HALF_DIV = CLK_HZ / (SCCB_HZ * 2);

    localparam S_IDLE         = 4'd0;
    localparam S_START_A      = 4'd1;
    localparam S_START_B      = 4'd2;
    localparam S_BIT_LOW      = 4'd3;
    localparam S_BIT_HIGH     = 4'd4;
    localparam S_ACK_LOW      = 4'd5;
    localparam S_ACK_HIGH     = 4'd6;
    localparam S_ACK_SAMPLE   = 4'd7;
    localparam S_STOP_LOW     = 4'd8;
    localparam S_STOP_HIGH    = 4'd9;
    localparam S_STOP_RELEASE = 4'd10;

    reg [15:0] div_count;
    reg [3:0]  state;
    reg [31:0] tx_shift;
    reg [2:0]  bit_count;
    reg [2:0]  byte_count;

    reg scl_drive_low;
    reg sda_drive_low;

    wire half_tick;

    assign half_tick = (div_count == HALF_DIV - 1);

    // Open-drain outputs; external pull-ups are required.
    wire scl_in;
wire sda_in;

IOBUF u_cam_scl_iobuf (
    .I  (1'b0),
    .T  (~scl_drive_low),
    .O  (scl_in),
    .IO (cam_scl)
);

IOBUF u_cam_sda_iobuf (
    .I  (1'b0),
    .T  (~sda_drive_low),
    .O  (sda_in),
    .IO (cam_sda)
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            div_count <= 16'd0;
        end else if (half_tick) begin
            div_count <= 16'd0;
        end else begin
            div_count <= div_count + 1'b1;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_IDLE;
            tx_shift      <= 32'd0;
            bit_count     <= 3'd7;
            byte_count    <= 3'd0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            nack          <= 1'b0;
        end else begin
            done <= 1'b0;

            if ((state == S_IDLE) && start) begin
                // OV5640 write address is 0x78.
                tx_shift   <= {8'h78, reg_addr, reg_data};
                bit_count  <= 3'd7;
                byte_count <= 3'd0;
                busy       <= 1'b1;
                nack       <= 1'b0;
                state      <= S_START_A;
            end else if (half_tick) begin
                case (state)
                    S_IDLE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                    end

                    S_START_A: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= S_START_B;
                    end

                    S_START_B: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state         <= S_BIT_LOW;
                    end

                    S_BIT_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= ~tx_shift[31];
                        state         <= S_BIT_HIGH;
                    end

                    S_BIT_HIGH: begin
                        scl_drive_low <= 1'b0;
                        tx_shift      <= {tx_shift[30:0], 1'b0};

                        if (bit_count == 0) begin
                            bit_count <= 3'd7;
                            state     <= S_ACK_LOW;
                        end else begin
                            bit_count <= bit_count - 1'b1;
                            state     <= S_BIT_LOW;
                        end
                    end

                    S_ACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= S_ACK_HIGH;
                    end

                    S_ACK_HIGH: begin
    scl_drive_low <= 1'b0;
    state         <= S_ACK_SAMPLE;
end

    S_ACK_SAMPLE: begin
    scl_drive_low <= 1'b0;

    // SCCB 写周期的第 9 位是 don't-care，不检查 I2C ACK。
    if (byte_count == 3) begin
        state <= S_STOP_LOW;
    end else begin
        byte_count <= byte_count + 1'b1;
        state      <= S_BIT_LOW;
    end
end

                    S_STOP_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state         <= S_STOP_HIGH;
                    end

                    S_STOP_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state         <= S_STOP_RELEASE;
                    end

                    S_STOP_RELEASE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= S_IDLE;
                    end

                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
