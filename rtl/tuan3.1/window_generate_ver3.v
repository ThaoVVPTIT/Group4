//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: window_generator_ver3 (?Ã FIX L?I B? M?T PIXEL KHI NEW_ROW)
//// ============================================================================

//module window_generator_ver3 #(
//    parameter DATA_WIDTH = 8
//)(
//    input  wire                      clk,
//    input  wire                      rst_n,

//    input  wire                      frame_clear,      // Reset s?ch khi sang Frame m?i
//    input  wire                      pixel_valid,      // N?i v?i rows_valid c?a Line Buffer
//    input  wire                      col_window_clear, // N?i v?i new_row c?a Line Buffer

//    // ??u vào 3 Pixels thu?c 3 Hàng liên ti?p
//    input  wire [DATA_WIDTH-1:0]      row0_pixel,
//    input  wire [DATA_WIDTH-1:0]      row1_pixel,
//    input  wire [DATA_WIDTH-1:0]      row2_pixel,

//    // ??u ra C?a s? tr??t 3x3
//    output reg  [DATA_WIDTH*9-1:0]    patch_3x3_data,
//    output reg                       patch_3x3_valid
//);

//    reg [DATA_WIDTH-1:0] win_00, win_01, win_02;
//    reg [DATA_WIDTH-1:0] win_10, win_11, win_12;
//    reg [DATA_WIDTH-1:0] win_20, win_21, win_22;

//    reg [1:0] col_count;

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            win_00 <= 0; win_01 <= 0; win_02 <= 0;
//            win_10 <= 0; win_11 <= 0; win_12 <= 0;
//            win_20 <= 0; win_21 <= 0; win_22 <= 0;
//            col_count       <= 2'd0;
//            patch_3x3_data  <= 0;
//            patch_3x3_valid <= 1'b0;
//        end else begin
//            // M?c ??nh h? valid sau 1 nh?p clock
//            patch_3x3_valid <= 1'b0;

//            // 1. FRAME CLEAR (Reset toàn b?)
//            if (frame_clear) begin
//                win_00 <= 0; win_01 <= 0; win_02 <= 0;
//                win_10 <= 0; win_11 <= 0; win_12 <= 0;
//                win_20 <= 0; win_21 <= 0; win_22 <= 0;
//                col_count      <= 2'd0;
//                patch_3x3_data <= 0;
//            end 

//            // 2. SHIFT WINDOW VÀ TÍNH M?T C?A S?
//            else if (pixel_valid) begin
//                // Shift c?a s? tr??t
//                win_00 <= win_01; win_01 <= win_02; win_02 <= row0_pixel;
//                win_10 <= win_11; win_11 <= win_12; win_12 <= row1_pixel;
//                win_20 <= win_21; win_21 <= win_22; win_22 <= row2_pixel;

//                // X? lý b? ??m c?t khi sang hàng m?i
//                if (col_window_clear) begin
//                    col_count <= 2'd1; // N?p pixel ??u tiên c?a hàng m?i
//                end else if (col_count < 2'd3) begin
//                    col_count <= col_count + 1'b1;
//                end

//                // T?o Patch 3x3 khi ?ã n?p ?? t? 3 c?t tr? lên (và không n?m ? pha v?a clear)
//                if (!col_window_clear && (col_count >= 2'd2)) begin
//                    patch_3x3_data <= {
//                        win_01, win_02, row0_pixel,
//                        win_11, win_12, row1_pixel,
//                        win_21, win_22, row2_pixel
//                    };
//                    patch_3x3_valid <= 1'b1;
//                end
//            end
//        end
//    end

//endmodule

`timescale 1ns / 1ps

module window_generator_ver3 #(
    parameter DATA_WIDTH = 8
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      frame_clear,
    input  wire                      pixel_valid,
    input  wire                      col_window_clear,

    input  wire [DATA_WIDTH-1:0]      row0_pixel,
    input  wire [DATA_WIDTH-1:0]      row1_pixel,
    input  wire [DATA_WIDTH-1:0]      row2_pixel,

    output reg  [DATA_WIDTH*9-1:0]    patch_3x3_data,
    output reg                       patch_3x3_valid
);

    reg [DATA_WIDTH-1:0] win_00, win_01, win_02;
    reg [DATA_WIDTH-1:0] win_10, win_11, win_12;
    reg [DATA_WIDTH-1:0] win_20, win_21, win_22;

    reg [1:0] col_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            win_00 <= 0; win_01 <= 0; win_02 <= 0;
            win_10 <= 0; win_11 <= 0; win_12 <= 0;
            win_20 <= 0; win_21 <= 0; win_22 <= 0;
            col_count       <= 2'd0;
            patch_3x3_data  <= 0;
            patch_3x3_valid <= 1'b0;
        end else begin
            // M?c ??nh h? valid
            patch_3x3_valid <= 1'b0;

            if (pixel_valid) begin
                // D?ch c?a s? 3x3
                win_00 <= win_01; win_01 <= win_02; win_02 <= row0_pixel;
                win_10 <= win_11; win_11 <= win_12; win_12 <= row1_pixel;
                win_20 <= win_21; win_21 <= win_22; win_22 <= row2_pixel;

                // Qu?n lý ??m c?t
                if (col_window_clear) begin
                    col_count <= 2'd1;
                end else if (col_count < 2'd3) begin
                    col_count <= col_count + 1'b1;
                end

                // B?t valid ngay khi ?? 3 c?t trong c?a s?
                if (!col_window_clear && (col_count >= 2'd2)) begin
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