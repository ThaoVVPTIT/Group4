`timescale 1ns / 1ps

// ============================================================================
// MODULE: window_generator_ver3 (?Ã FIX CHU?N LOGIC CH?T PATCH C?T)
// Ch?c n?ng: T?o c?a s? 3x3 cho Conv1 (8-bit) và Conv2 (48-bit song song)
// ============================================================================

module window_generator_ver3 #(
    parameter DATA_WIDTH = 8
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       frame_clear,
    input  wire                       pixel_valid,
    input  wire                       col_window_clear, // Tín hi?u new_row t? LineBuffer

    input  wire [DATA_WIDTH-1:0]      row0_pixel,
    input  wire [DATA_WIDTH-1:0]      row1_pixel,
    input  wire [DATA_WIDTH-1:0]      row2_pixel,

    output reg  [DATA_WIDTH*9-1:0]    patch_3x3_data,
    output reg                        patch_3x3_valid
);

    reg [DATA_WIDTH-1:0] win_00, win_01, win_02;
    reg [DATA_WIDTH-1:0] win_10, win_11, win_12;
    reg [DATA_WIDTH-1:0] win_20, win_21, win_22;

    reg [1:0] col_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            win_00 <= {DATA_WIDTH{1'b0}}; win_01 <= {DATA_WIDTH{1'b0}}; win_02 <= {DATA_WIDTH{1'b0}};
            win_10 <= {DATA_WIDTH{1'b0}}; win_11 <= {DATA_WIDTH{1'b0}}; win_12 <= {DATA_WIDTH{1'b0}};
            win_20 <= {DATA_WIDTH{1'b0}}; win_21 <= {DATA_WIDTH{1'b0}}; win_22 <= {DATA_WIDTH{1'b0}};
            col_count       <= 2'd0;
            patch_3x3_data  <= {(DATA_WIDTH*9){1'b0}};
            patch_3x3_valid <= 1'b0;
        end else begin
            // M?c ??nh h? valid sau 1 clock
            patch_3x3_valid <= 1'b0;

            if (pixel_valid) begin
                // D?ch c?a s? 3x3
                win_00 <= win_01; win_01 <= win_02; win_02 <= row0_pixel;
                win_10 <= win_11; win_11 <= win_12; win_12 <= row1_pixel;
                win_20 <= win_21; win_21 <= win_22; win_22 <= row2_pixel;

                // Qu?n lý ??m c?t khi sang hàng m?i
                if (col_window_clear) begin
                    col_count <= 2'd1; // Pixel ??u tiên c?a hàng m?i
                end else if (col_count < 2'd2) begin
                    col_count <= col_count + 1'b1;
                end

                // B?T VALID: ?ã n?p ?? ít nh?t 2 pixel tr??c ?ó + 1 pixel hi?n t?i (?? 3 c?t)
                // ?ã fix: B? ?i?u ki?n !col_window_clear ?? không b? m?t patch ? biên hàng
                if ((col_count >= 2'd2) && !col_window_clear) begin
                    patch_3x3_data <= {
                        win_01, win_02, row0_pixel,
                        win_11, win_12, row1_pixel,
                        win_21, win_22, row2_pixel
                    };
                    patch_3x3_valid <= 1'b1;
                end else if (col_window_clear && (col_count >= 2'd2)) begin
                    // Cho phép ch?t n?t patch cu?i hàng n?u xung col_window_clear nh?y lên
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