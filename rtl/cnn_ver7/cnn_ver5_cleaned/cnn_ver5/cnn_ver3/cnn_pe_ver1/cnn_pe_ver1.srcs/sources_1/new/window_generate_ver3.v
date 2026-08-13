`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 * Module: window_generator_ver3
 *
 * Builds one 3x3 patch from the three row taps.  The flattened order is
 * row-major with tap 0 in the least-significant DATA_WIDTH bits:
 *   tap 0,1,2 = top row; tap 3,4,5 = middle; tap 6,7,8 = bottom.
 *------------------------------------------------------------------------*/
module window_generator_ver3 #(
    parameter integer DATA_WIDTH = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         frame_clear,
    input  wire                         pixel_valid,
    input  wire                         col_window_clear,

    input  wire [DATA_WIDTH-1:0]        row0_pixel,
    input  wire [DATA_WIDTH-1:0]        row1_pixel,
    input  wire [DATA_WIDTH-1:0]        row2_pixel,

    output reg  [DATA_WIDTH*9-1:0]      patch_3x3_data,
    output reg                          patch_3x3_valid
);

    reg [DATA_WIDTH-1:0] win_01, win_02;
    reg [DATA_WIDTH-1:0] win_11, win_12;
    reg [DATA_WIDTH-1:0] win_21, win_22;

    /* Saturating count of accepted pixels in the current output row. */
    reg [1:0] col_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            win_01 <= 0;
            win_02 <= 0;
            win_11 <= 0;
            win_12 <= 0;
            win_21 <= 0;
            win_22 <= 0;
            col_count       <= 0;
            patch_3x3_data  <= 0;
            patch_3x3_valid <= 1'b0;
        end else begin
            patch_3x3_valid <= 1'b0;

            if (pixel_valid) begin
                if (col_window_clear) begin
                    /* First accepted column of a new raster row. */
                    win_01 <= 0;
                    win_02 <= row0_pixel;
                    win_11 <= 0;
                    win_12 <= row1_pixel;
                    win_21 <= 0;
                    win_22 <= row2_pixel;
                    col_count <= 2'd1;
                end else begin
                    win_01 <= win_02;
                    win_02 <= row0_pixel;
                    win_11 <= win_12;
                    win_12 <= row1_pixel;
                    win_21 <= win_22;
                    win_22 <= row2_pixel;

                    if (col_count < 2'd3)
                        col_count <= col_count + 1'b1;

                    if (col_count >= 2'd2) begin
                        patch_3x3_data[0*DATA_WIDTH +: DATA_WIDTH] <= win_01;
                        patch_3x3_data[1*DATA_WIDTH +: DATA_WIDTH] <= win_02;
                        patch_3x3_data[2*DATA_WIDTH +: DATA_WIDTH] <= row0_pixel;
                        patch_3x3_data[3*DATA_WIDTH +: DATA_WIDTH] <= win_11;
                        patch_3x3_data[4*DATA_WIDTH +: DATA_WIDTH] <= win_12;
                        patch_3x3_data[5*DATA_WIDTH +: DATA_WIDTH] <= row1_pixel;
                        patch_3x3_data[6*DATA_WIDTH +: DATA_WIDTH] <= win_21;
                        patch_3x3_data[7*DATA_WIDTH +: DATA_WIDTH] <= win_22;
                        patch_3x3_data[8*DATA_WIDTH +: DATA_WIDTH] <= row2_pixel;
                        patch_3x3_valid <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
