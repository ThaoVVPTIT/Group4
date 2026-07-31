`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv2_pe
// Ch?c n?ng: Processing Element (PE) cho Conv2 (C_IN = 6).
//            Th?c hi?n tích ch?p 3x3x6 (54 MACs) + Bias + Quantization + ReLU.
// ============================================================================

module conv2_pe #(
    parameter DATA_WIDTH  = 8,
    parameter C_IN        = 6,
    parameter ACC_WIDTH   = 32,
    parameter MULT_WIDTH  = 32,
    parameter SHIFT_WIDTH = 8
)(
    input  wire                               clk,
    input  wire                               rst_n,
    input  wire                               frame_clear,
    input  wire                               patch_valid, // Tín hi?u patch_cin_valid t? Channel Buffer

    // ??u vào 54 Pixels (3x3x6) và 54 Weights (3x3x6)
    input  wire signed [DATA_WIDTH*9*C_IN-1:0] patch_data,
    input  wire signed [DATA_WIDTH*9*C_IN-1:0] weights,

    // Tham s? Quantization
    input  wire signed [ACC_WIDTH-1:0]        bias,
    input  wire signed [MULT_WIDTH-1:0]       multiplier,
    input  wire        [SHIFT_WIDTH-1:0]      shift,

    // Ngõ ra
    output reg  signed [DATA_WIDTH-1:0]       output_data,
    output reg                                output_valid
);

    localparam TOTAL_ELEMENTS = 9 * C_IN; // 54 ph?n t?
    localparam PRODUCT_WIDTH  = DATA_WIDTH * 2;

    reg signed [ACC_WIDTH-1:0]  mac_sum;
    reg signed [63:0]          quant_product;
    reg signed [63:0]          quant_value;
    reg signed [DATA_WIDTH-1:0] result_comb;

    integer i;
    reg signed [DATA_WIDTH-1:0] pixel_item;
    reg signed [DATA_WIDTH-1:0] weight_item;
    reg signed [PRODUCT_WIDTH-1:0] prod;

    // ========================================================================
    // 1. COMBINATIONAL MAC 3x3xC_IN & QUANTIZATION
    // ========================================================================
    always @(*) begin
        // Step 1: Tính t?ng tích l?y (54 phép nhân + Bias)
        mac_sum = bias;
        for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
            pixel_item = patch_data[i*DATA_WIDTH +: DATA_WIDTH];
            weight_item = weights[i*DATA_WIDTH +: DATA_WIDTH];
            prod       = pixel_item * weight_item;
            mac_sum    = mac_sum + prod;
        end

        // Step 2: Quantization (Scale Multiplier)
        quant_product = mac_sum * multiplier;

        // Step 3: Rounding + Right Shift
        if (shift != 0) begin
            quant_value = quant_product + (64'sd1 <<< (shift - 1));
            quant_value = quant_value >>> shift;
        end else begin
            quant_value = quant_product;
        end

        // Step 4: Clamp INT8 [-128, 127] + ReLU [0, 127]
        if (quant_value < 0) begin
            result_comb = {DATA_WIDTH{1'b0}};
        end else if (quant_value > 127) begin
            result_comb = 8'sd127;
        end else begin
            result_comb = quant_value[DATA_WIDTH-1:0];
        end
    end

    // ========================================================================
    // 2. OUTPUT REGISTER
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            output_data  <= {DATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            output_valid <= patch_valid;
            if (patch_valid) begin
                output_data <= result_comb;
            end else begin
                output_data <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule