`timescale 1ns / 1ps

/*
 * One shared lane of fixed-point requantization and ReLU/clamp.
 * The shared engine registers this module's output only when the matching
 * valid token is present; acc/mult are isolated to zero while the lane is
 * idle.  The local zero check additionally suppresses a provably redundant
 * 32x32 multiply for sparse/zero-biased results.
 */
module requantize_relu_lane #(
    parameter integer DATA_BITS = 8
)(
    input  wire signed [31:0]          acc_value,
    input  wire signed [31:0]          mult_value,
    input  wire        [7:0]           shift_value,
    output wire signed [DATA_BITS-1:0] quantized_value
);

    reg signed [63:0] product;
    reg signed [63:0] q_value;
    reg signed [DATA_BITS-1:0] q_reg;

    localparam signed [DATA_BITS-1:0] RELU_MAX =
        {1'b0, {(DATA_BITS-1){1'b1}}};

    always @* begin
        // Exact zero gating: multiplication by zero and all subsequent
        // rounding/shift operations yield zero for the supported arithmetic.
        if ((acc_value == 32'sd0) || (mult_value == 32'sd0))
            product = 64'sd0;
        else
            product = acc_value * mult_value;

        if (shift_value > 0) begin
            product = product + (64'sd1 << (shift_value - 1));
            q_value = product >>> shift_value;
        end else begin
            q_value = product;
        end

        if (q_value < 0)
            q_reg = {DATA_BITS{1'b0}};
        else if (q_value > RELU_MAX)
            q_reg = RELU_MAX;
        else
            q_reg = q_value[DATA_BITS-1:0];
    end

    assign quantized_value = q_reg;

endmodule
