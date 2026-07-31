`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/28/2026 12:01:16 PM
// Design Name: 
// Module Name: conv1_top_ver3
// Project Name: 
// Target Devices: `timescale 1ns / 1ps

// ============================================================================
// MODULE: conv1_top_ver1 (Zero-BRAM Streaming Standard)
// Ch?c n?ng: Conv1 (28x28x1 -> 26x26x6) xu?t Stream tr?c ti?p sang Pooling
// ============================================================================

module conv1_top_ver3 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 28,
    parameter IMG_HEIGHT  = 28,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 1,
    parameter C_OUT       = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Giao di?n FSM
    input  wire                         start,
    output wire                         ready,
    output wire                         done,

    // Stream Pixel Input
    input  wire                         pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,

    // Stream Output BUS sang Pooling IP (X? song song 6 Channels)
    output wire                         m_axis_valid,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch0,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch1,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch2,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch3,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch4,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch5,
    output wire                         m_axis_frame_clear // Kích ho?t pool_start
);

    // Localparams & Calculators
    localparam OUTPUT_WIDTH  = IMG_WIDTH - KERNEL_SIZE + 1;
    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1;
    localparam PATCH_COUNT   = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam PATCH_ADDR_WIDTH = (PATCH_COUNT <= 1) ? 1 : $clog2(PATCH_COUNT);

    reg busy;
    reg done_reg;
    reg frame_clear;

    assign ready = !busy;
    assign done  = done_reg;
    assign m_axis_frame_clear = frame_clear;

    wire pixel_valid_gate = pixel_valid && busy;

    // Stage 1 & 2 Wires
    wire [DATA_WIDTH-1:0] row0_pixel, row1_pixel, row2_pixel;
    wire                  rows_valid, new_row;
    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    // Line Buffer & Window Generator Instantiations
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH), .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .C_IN(C_IN)
    ) u_line_buffer (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear),
        .pixel_valid(pixel_valid_gate), .pixel_in(pixel_in),
        .row0_pixel(row0_pixel), .row1_pixel(row1_pixel), .row2_pixel(row2_pixel),
        .rows_valid(rows_valid), .new_row(new_row),
        .channel_idx(), .frame_c_done()
    );

    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_generator (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear),
        .pixel_valid(rows_valid), .col_window_clear(new_row),
        .row0_pixel(row0_pixel), .row1_pixel(row1_pixel), .row2_pixel(row2_pixel),
        .patch_3x3_data(patch_3x3_data), .patch_3x3_valid(patch_3x3_valid)
    );

    // ROM Weights / Bias Loaders
    reg signed [DATA_WIDTH-1:0] c1_kernel [0:C_OUT*9-1]; 
    reg signed [31:0]           c1_bias   [0:C_OUT-1];   
    reg signed [31:0]           c1_mult   [0:C_OUT-1];   
    reg [7:0]                   c1_shift  [0:C_OUT-1];   

    initial begin
        $readmemh("weights_hex/conv1_kernel.hex",     c1_kernel);
        $readmemh("weights_hex/conv1_bias.hex",       c1_bias);
        $readmemh("weights_hex/conv1_multiplier.hex", c1_mult);
        $readmemh("weights_hex/conv1_shift.hex",      c1_shift);
    end

    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    assign p0 = patch_3x3_data[71:64]; assign p1 = patch_3x3_data[63:56]; assign p2 = patch_3x3_data[55:48];
    assign p3 = patch_3x3_data[47:40]; assign p4 = patch_3x3_data[39:32]; assign p5 = patch_3x3_data[31:24];
    assign p6 = patch_3x3_data[23:16]; assign p7 = patch_3x3_data[15:8];  assign p8 = patch_3x3_data[7:0];

    wire signed [DATA_WIDTH-1:0] pe_output [0:C_OUT-1];
    wire                         pe_valid  [0:C_OUT-1];

    // Instantiate 6 PE Units
    genvar f;
    generate
        for (f = 0; f < C_OUT; f = f + 1) begin : GEN_PE
            conv1_pe u_pe (
                .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
                .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
                .w0(c1_kernel[f*9+0]), .w1(c1_kernel[f*9+1]), .w2(c1_kernel[f*9+2]),
                .w3(c1_kernel[f*9+3]), .w4(c1_kernel[f*9+4]), .w5(c1_kernel[f*9+5]),
                .w6(c1_kernel[f*9+6]), .w7(c1_kernel[f*9+7]), .w8(c1_kernel[f*9+8]),
                .bias(c1_bias[f]), .multiplier(c1_mult[f]), .shift(c1_shift[f]),
                .output_data(pe_output[f]), .output_valid(pe_valid[f])
            );
        end
    endgenerate

    // DIRECT STREAMING OUTPUT ASSIGNMENT (LO?I B? HOÀN TOÀN BRAM C1_OUT)
    assign m_axis_valid    = pe_valid[0];
    assign m_axis_data_ch0 = pe_output[0];
    assign m_axis_data_ch1 = pe_output[1];
    assign m_axis_data_ch2 = pe_output[2];
    assign m_axis_data_ch3 = pe_output[3];
    assign m_axis_data_ch4 = pe_output[4];
    assign m_axis_data_ch5 = pe_output[5];

    // FSM Control Logic
    reg [PATCH_ADDR_WIDTH-1:0] patch_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
            busy      <= 1'b0;
            done_reg  <= 1'b0;
        end else begin
            done_reg    <= 1'b0;
            frame_clear <= 1'b0;

            if (start && !busy) begin
                busy        <= 1'b1;
                frame_clear <= 1'b1;
            end

            if (pe_valid[0]) begin
                if (patch_cnt == PATCH_COUNT - 1) begin
                    patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
                    busy      <= 1'b0;
                    done_reg  <= 1'b1; // Báo hoàn thành toàn b? Conv1
                end else begin
                    patch_cnt <= patch_cnt + 1'b1;
                end
            end
        end
    end

endmodule

