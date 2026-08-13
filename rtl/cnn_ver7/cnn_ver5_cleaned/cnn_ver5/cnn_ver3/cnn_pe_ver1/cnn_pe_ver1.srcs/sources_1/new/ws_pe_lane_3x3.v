`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 * Module: ws_pe_lane_3x3
 *
 * One physical compute lane of the tiled resident-weight PE array.
 * The lane contains exactly nine signed INT8 multipliers.  The products are
 * first reduced by kernel row, then by a balanced three-row tree.  The
 * caller selects weights from the local resident RF and keeps the output
 * partial sum stationary while accumulating dot_sum across input channels.
 *
 * This module is deliberately combinational.  The shared engine places a
 * clock-enabled pipeline register immediately after dot_sum.  Keeping the
 * register in the caller also lets the legacy wrappers reuse this PE without
 * changing their interface.
 *------------------------------------------------------------------------*/
module ws_pe_lane_3x3 #(
    parameter integer DATA_BITS = 8
)(
    input  wire [(9*DATA_BITS)-1:0] activation_flat,
    input  wire [(9*DATA_BITS)-1:0] weight_flat,
    output wire signed [31:0]       dot_sum
);

    localparam integer PROD_BITS = 2*DATA_BITS;
    // Nine signed products need three guard bits.  For INT8 this reduces the
    // adder tree from 32 bits to 19 bits without changing its numeric range.
    localparam integer SUM_BITS  = PROD_BITS + 3;

    wire signed [DATA_BITS-1:0] activation [0:8];
    wire signed [DATA_BITS-1:0] weight     [0:8];
    wire signed [DATA_BITS-1:0] activation_gated [0:8];
    wire signed [DATA_BITS-1:0] weight_gated     [0:8];
    wire signed [PROD_BITS-1:0] product    [0:8];
    wire signed [SUM_BITS-1:0]  product_ext[0:8];

    genvar tap;
    generate
        for (tap = 0; tap < 9; tap = tap + 1) begin : g_tap
            assign activation[tap] = activation_flat[tap*DATA_BITS +: DATA_BITS];
            assign weight[tap]     = weight_flat[tap*DATA_BITS +: DATA_BITS];
            // Exact operand isolation: a zero activation/weight must produce
            // zero, so suppressing the multiplier in that case is numerically
            // transparent and reduces unnecessary switching on sparse maps.
            wire tap_enable =
                (activation[tap] != {DATA_BITS{1'b0}}) &&
                (weight[tap]     != {DATA_BITS{1'b0}});

            // Gate before (rather than after) the multiplier.  The explicitly
            // signed intermediate nets also prevent a conditional operator
            // from accidentally turning signed INT8 multiplication unsigned.
            assign activation_gated[tap] = tap_enable
                ? activation[tap] : {DATA_BITS{1'b0}};
            assign weight_gated[tap] = tap_enable
                ? weight[tap] : {DATA_BITS{1'b0}};
            assign product[tap] = activation_gated[tap] * weight_gated[tap];
            assign product_ext[tap] =
                {{(SUM_BITS-PROD_BITS){product[tap][PROD_BITS-1]}}, product[tap]};
        end
    endgenerate

    // Three row-stationary partial sums.  Keeping these row boundaries
    // explicit makes the intended 3-PE-row mapping visible to synthesis.
    // Named levels prevent an accidental serial nine-input addition chain.
    wire signed [SUM_BITS-1:0] row_pair0 = product_ext[0] + product_ext[1];
    wire signed [SUM_BITS-1:0] row_pair1 = product_ext[3] + product_ext[4];
    wire signed [SUM_BITS-1:0] row_pair2 = product_ext[6] + product_ext[7];

    wire signed [SUM_BITS-1:0] row_sum0 = row_pair0 + product_ext[2];
    wire signed [SUM_BITS-1:0] row_sum1 = row_pair1 + product_ext[5];
    wire signed [SUM_BITS-1:0] row_sum2 = row_pair2 + product_ext[8];

    wire signed [SUM_BITS-1:0] row_sum01 = row_sum0 + row_sum1;
    wire signed [SUM_BITS-1:0] dot_sum_narrow = row_sum01 + row_sum2;

    assign dot_sum =
        {{(32-SUM_BITS){dot_sum_narrow[SUM_BITS-1]}}, dot_sum_narrow};

endmodule
