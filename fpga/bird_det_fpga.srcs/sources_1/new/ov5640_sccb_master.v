`timescale 1ns / 1ps

// SCCB master for one OV5640 16-bit-register read or write transaction.
// The ninth SCCB bit is sampled only as a diagnostic; it never aborts a
// transaction.  A real-device presence check is performed with chip ID 0x5640.
module ov5640_sccb_master #(
    parameter integer CLK_DIV = 500,
    parameter [6:0]   DEVICE_ADDRESS = 7'h3c
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        read_not_write,
    input  wire [15:0] register_address,
    input  wire [7:0]  write_data,
    output reg  [7:0]  read_data,
    output reg         busy,
    output reg         done,
    output reg         ack_error,
    inout  wire        sccb_scl,
    inout  wire        sccb_sda
);

    localparam [4:0]
        ST_IDLE         = 5'd0,
        ST_START_IDLE   = 5'd1,
        ST_START_ASSERT = 5'd2,
        ST_TX_LOW       = 5'd3,
        ST_TX_HIGH      = 5'd4,
        ST_ACK_LOW      = 5'd5,
        ST_ACK_HIGH     = 5'd6,
        ST_RS_LOW       = 5'd7,
        ST_RS_HIGH      = 5'd8,
        ST_RS_ASSERT    = 5'd9,
        ST_RX_LOW       = 5'd10,
        ST_RX_HIGH      = 5'd11,
        ST_NACK_LOW     = 5'd12,
        ST_NACK_HIGH    = 5'd13,
        ST_STOP_LOW     = 5'd14,
        ST_STOP_HIGH    = 5'd15,
        ST_STOP_RELEASE = 5'd16;

    localparam [2:0]
        SEQ_ADDRESS_WRITE = 3'd0,
        SEQ_REGISTER_HIGH = 3'd1,
        SEQ_REGISTER_LOW  = 3'd2,
        SEQ_WRITE_DATA    = 3'd3,
        SEQ_ADDRESS_READ  = 3'd4;

    reg [4:0]  state;
    reg [2:0]  sequence;
    reg [31:0] divider_count;
    reg [2:0]  bit_index;
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;
    reg [15:0] register_address_latched;
    reg [7:0]  write_data_latched;
    reg        read_request_latched;
    reg        scl_drive_low;
    reg        sda_drive_low;
    wire       sda_in;

    // SCL is write-only in this single-master design. SDA remains bidirectional
    // because register reads sample data from the camera.
    OBUFT u_sccb_scl_obuf (
        .I (1'b0),
        .T (~scl_drive_low),
        .O (sccb_scl)
    );

    IOBUF u_sccb_sda_iobuf (
        .I  (1'b0),
        .T  (~sda_drive_low),
        .O  (sda_in),
        .IO (sccb_sda)
    );

    wire divider_tick = (divider_count == CLK_DIV - 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            state                    <= ST_IDLE;
            sequence                 <= SEQ_ADDRESS_WRITE;
            divider_count            <= 32'd0;
            bit_index                <= 3'd7;
            tx_shift                 <= 8'd0;
            rx_shift                 <= 8'd0;
            register_address_latched <= 16'd0;
            write_data_latched       <= 8'd0;
            read_request_latched     <= 1'b0;
            read_data                <= 8'd0;
            busy                     <= 1'b0;
            done                     <= 1'b0;
            ack_error                <= 1'b0;
            scl_drive_low            <= 1'b0;
            sda_drive_low            <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                divider_count <= 32'd0;
                if (start) begin
                    register_address_latched <= register_address;
                    write_data_latched       <= write_data;
                    read_request_latched     <= read_not_write;
                    busy                     <= 1'b1;
                    ack_error                <= 1'b0;
                    scl_drive_low            <= 1'b0;
                    sda_drive_low            <= 1'b0;
                    state                    <= ST_START_IDLE;
                end
            end else if (divider_tick) begin
                divider_count <= 32'd0;
                case (state)
                    ST_START_IDLE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= ST_START_ASSERT;
                    end
                    ST_START_ASSERT: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        tx_shift      <= {DEVICE_ADDRESS, 1'b0};
                        bit_index     <= 3'd7;
                        sequence      <= SEQ_ADDRESS_WRITE;
                        state         <= ST_TX_LOW;
                    end
                    ST_TX_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= ~tx_shift[bit_index];
                        state         <= ST_TX_HIGH;
                    end
                    ST_TX_HIGH: begin
                        scl_drive_low <= 1'b0;
                        if (bit_index == 0)
                            state <= ST_ACK_LOW;
                        else begin
                            bit_index <= bit_index - 1'b1;
                            state     <= ST_TX_LOW;
                        end
                    end
                    ST_ACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_ACK_HIGH;
                    end
                    ST_ACK_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        ack_error     <= ack_error | sda_in;
                        case (sequence)
                            SEQ_ADDRESS_WRITE: begin
                                tx_shift <= register_address_latched[15:8];
                                bit_index <= 3'd7;
                                sequence <= SEQ_REGISTER_HIGH;
                                state <= ST_TX_LOW;
                            end
                            SEQ_REGISTER_HIGH: begin
                                tx_shift <= register_address_latched[7:0];
                                bit_index <= 3'd7;
                                sequence <= SEQ_REGISTER_LOW;
                                state <= ST_TX_LOW;
                            end
                            SEQ_REGISTER_LOW: begin
                                if (read_request_latched)
                                    state <= ST_RS_LOW;
                                else begin
                                    tx_shift <= write_data_latched;
                                    bit_index <= 3'd7;
                                    sequence <= SEQ_WRITE_DATA;
                                    state <= ST_TX_LOW;
                                end
                            end
                            SEQ_WRITE_DATA: state <= ST_STOP_LOW;
                            SEQ_ADDRESS_READ: begin
                                bit_index <= 3'd7;
                                rx_shift  <= 8'd0;
                                state     <= ST_RX_LOW;
                            end
                            default: state <= ST_STOP_LOW;
                        endcase
                    end
                    ST_RS_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_RS_HIGH;
                    end
                    ST_RS_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= ST_RS_ASSERT;
                    end
                    ST_RS_ASSERT: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        tx_shift      <= {DEVICE_ADDRESS, 1'b1};
                        bit_index     <= 3'd7;
                        sequence      <= SEQ_ADDRESS_READ;
                        state         <= ST_TX_LOW;
                    end
                    ST_RX_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_RX_HIGH;
                    end
                    ST_RX_HIGH: begin
                        scl_drive_low       <= 1'b0;
                        rx_shift[bit_index] <= sda_in;
                        if (bit_index == 0) begin
                            read_data <= {rx_shift[7:1], sda_in};
                            state     <= ST_NACK_LOW;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state     <= ST_RX_LOW;
                        end
                    end
                    ST_NACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_NACK_HIGH;
                    end
                    ST_NACK_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= ST_STOP_LOW;
                    end
                    ST_STOP_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_HIGH;
                    end
                    ST_STOP_HIGH: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_RELEASE;
                    end
                    ST_STOP_RELEASE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                    default: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end
                endcase
            end else begin
                divider_count <= divider_count + 1'b1;
            end
        end
    end
endmodule
