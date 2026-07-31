`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv1_pe
// Ch?c n?ng: Processing Element (PE) th?c hi?n Tích ch?p 3x3 cho 1 Filter.
//            - Chu?i tính toán: MAC 3x3 + Bias -> Quantization -> Clamp -> ReLU.
//            - ??ng b? Output Register (Tr? 1 nh?p clock) + H? tr? frame_clear.
// ============================================================================

module conv1_pe #(
    parameter DATA_WIDTH  = 8,
    parameter ACC_WIDTH   = 32,
    parameter MULT_WIDTH  = 32,
    parameter SHIFT_WIDTH = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Tín hi?u ?i?u khi?n
    input  wire                         frame_clear,   // Reset s?ch PE khi sang Frame m?i
    input  wire                         patch_valid,   // Báo Patch 3x3 ??u vào h?p l?

    // Patch 3x3 Input (9 pixels Signed INT8)
    input  wire signed [DATA_WIDTH-1:0] p0, p1, p2,
    input  wire signed [DATA_WIDTH-1:0] p3, p4, p5,
    input  wire signed [DATA_WIDTH-1:0] p6, p7, p8,

    // Filter Weights 3x3 (9 weights Signed INT8)
    input  wire signed [DATA_WIDTH-1:0] w0, w1, w2,
    input  wire signed [DATA_WIDTH-1:0] w3, w4, w5,
    input  wire signed [DATA_WIDTH-1:0] w6, w7, w8,

    // Bias + Quantization Parameters
    input  wire signed [ACC_WIDTH-1:0]  bias,
    input  wire signed [MULT_WIDTH-1:0] multiplier,
    input  wire        [SHIFT_WIDTH-1:0] shift,

    // Output Data & Valid Flag
    output reg  signed [DATA_WIDTH-1:0] output_data,
    output reg                          output_valid
);

    localparam PRODUCT_WIDTH = DATA_WIDTH * 2;

    // Tín hi?u trung gian
    reg signed [PRODUCT_WIDTH-1:0] prod0, prod1, prod2, prod3, prod4, prod5, prod6, prod7, prod8;
    reg signed [ACC_WIDTH-1:0]     mac_sum;
    reg signed [63:0]              quant_product;
    reg signed [63:0]              quant_value;
    reg signed [DATA_WIDTH-1:0]    result_comb;

    // ========================================================================
    // 1. COMBINATIONAL COMPUTATION (MAC + QUANTIZATION + RELU)
    // ========================================================================
    always @(*) begin
        // Step 1: Phép nhân 9 cap Pixel * Weight
        prod0 = p0 * w0; prod1 = p1 * w1; prod2 = p2 * w2;
        prod3 = p3 * w3; prod4 = p4 * w4; prod5 = p5 * w5;
        prod6 = p6 * w6; prod7 = p7 * w7; prod8 = p8 * w8;

        // Step 2: T?ng tích góp + Bias
        mac_sum = bias + prod0 + prod1 + prod2 + prod3 + prod4 + prod5 + prod6 + prod7 + prod8;

        // Step 3: L??ng t? hóa (Scale Multiplier)
        quant_product = mac_sum * multiplier;

        // Step 4: Rounding + D?ch bit (Right Shift)
        if (shift != 0) begin
            quant_value = quant_product + (64'sd1 <<< (shift - 1)); // Rounding
            quant_value = quant_value >>> shift;                   // Shift
        end else begin
            quant_value = quant_product;
        end

        // Step 5: Clamp INT8 [-128, 127] + ReLU [0, 127]
        if (quant_value < 0) begin
            result_comb = {DATA_WIDTH{1'b0}}; // ReLU c?t âm v? 0
        end else if (quant_value > 127) begin
            result_comb = 8'sd127;            // Upper clamp 127
        end else begin
            result_comb = quant_value[DATA_WIDTH-1:0];
        end
    end

    // ========================================================================
    // 2. OUTPUT REGISTER (??ng b? nh?p Clock + Frame Clear)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_data  <= {DATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else if (frame_clear) begin
            output_data  <= {DATA_WIDTH{1'b0}};
            output_valid <= 1'b0;
        end else begin
            output_valid <= patch_valid;
            if (patch_valid) begin
                output_data <= result_comb;
            end else begin
                output_data <= {DATA_WIDTH{1'b0}}; // Tr? bus v? 0 khi không valid
            end
        end
    end

endmodule