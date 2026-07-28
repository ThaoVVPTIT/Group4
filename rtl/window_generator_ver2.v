`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/25/2026 12:24:03 AM
// Design Name: 
// Module Name: window_generator_ver2
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module window_generator_ver2 #(
    parameter DATA_WIDTH = 8
)(
    input  wire                       clk,
    input  wire                       rst_n,

    //============================================================
    // CONTROL
    //============================================================
    input  wire                       pixel_valid, // khi nhan duoc 1 cot tu line buffer
    input  wire                       col_window_clear,
    input  wire                       window_clear,

    //============================================================
    // 3 PIXELS SAME COLUMN
    //============================================================
    input  wire [DATA_WIDTH-1:0]      row0_pixel,
    input  wire [DATA_WIDTH-1:0]      row1_pixel,
    input  wire [DATA_WIDTH-1:0]      row2_pixel,

    //============================================================
    // OUTPUT: ONE 3x3 PATCH
    //============================================================
    output reg  [DATA_WIDTH*9-1:0]    patch_3x3_data,
    output reg                        patch_3x3_valid
);

    //============================================================
    // 3x3 WINDOW REGISTERS
    //
    //     col0   col1   col2
    //
    // row0  00     01     02
    // row1  10     11     12
    // row2  20     21     22
    //============================================================

    reg [DATA_WIDTH-1:0] win_00, win_01, win_02;
    reg [DATA_WIDTH-1:0] win_10, win_11, win_12;
    reg [DATA_WIDTH-1:0] win_20, win_21, win_22;

    // 0: ch?a nh?n c?t nào
    // 1: ?ã nh?n 1 c?t
    // 2: ?ã nh?n 2 c?t
    // 3: ?ã ?? 3 c?t
    reg [1:0] col_count;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            win_00 <= 0;
            win_01 <= 0;
            win_02 <= 0;

            win_10 <= 0;
            win_11 <= 0;
            win_12 <= 0;

            win_20 <= 0;
            win_21 <= 0;
            win_22 <= 0;

            col_count       <= 2'd0;
            patch_3x3_data  <= 0;
            patch_3x3_valid <= 1'b0;

        end else begin

            // M?c ??nh patch ch? valid 1 clock
            patch_3x3_valid <= 1'b0;


            //====================================================
            // 1. CLEAR FRAME
            //====================================================

            if (window_clear) begin

                win_00 <= 0;
                win_01 <= 0;
                win_02 <= 0;

                win_10 <= 0;
                win_11 <= 0;
                win_12 <= 0;

                win_20 <= 0;
                win_21 <= 0;
                win_22 <= 0;

                col_count <= 2'd0;

            end


            //====================================================
            // 2. CLEAR HORIZONTAL WINDOW
            // Khi b?t ??u m?t hàng m?i
            //====================================================

            else if (col_window_clear) begin

                win_00 <= 0;
                win_01 <= 0;
                win_02 <= 0;

                win_10 <= 0;
                win_11 <= 0;
                win_12 <= 0;

                win_20 <= 0;
                win_21 <= 0;
                win_22 <= 0;

                col_count <= 2'd0;

            end


            //====================================================
            // 3. RECEIVE ONE COLUMN
            //====================================================

            else if (pixel_valid) begin

                //================================================
                // D?CH C?A S? SANG TRÁI
                //================================================

                win_00 <= win_01;
                win_01 <= win_02;
                win_02 <= row0_pixel;

                win_10 <= win_11;
                win_11 <= win_12;
                win_12 <= row1_pixel;

                win_20 <= win_21;
                win_21 <= win_22;
                win_22 <= row2_pixel;


                //================================================
                // ??M S? C?T ?Ã NH?N
                //================================================

                if (col_count < 2'd3) begin
                    col_count <= col_count + 1'b1;
                end


                //================================================
                // T?O PATCH KHI ?Ã CÓ ?? 3 C?T
                //
                // Hai c?t c?:
                //   win_01, win_02
                //
                // C?t m?i:
                //   rowX_pixel
                //
                // => t?o patch 3x3 hoàn ch?nh
                //================================================

                if (col_count >= 2'd2) begin

                    patch_3x3_data <= {
                        win_01, win_02, row0_pixel,
                        win_11, win_12, row1_pixel,
                        win_21, win_22, row2_pixel
                    };

                    patch_3x3_valid <= 1'b1;

                end

            end

        end

    end

endmodule
