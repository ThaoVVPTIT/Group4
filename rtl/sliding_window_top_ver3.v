`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_sliding_window_ver1 (Updated to Ver3 Standard)
//
// Ch?c n?ng: Module Top tích h?p chu?i Pipeline 3 giai ?o?n:
//   Stage 1: Line Buffer (L?u 2 hàng, xu?t 3 pixel cùng c?t)
//   Stage 2: Window Generator (Tr??t c?a s? 3x3x1 single-channel)
//   Stage 3: Channel Patch Buffer (Gom 3x3x1 ?? C_IN channels thành Tensor 3x3xC_IN)
// ============================================================================

module top_sliding_window_ver3 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28,
    parameter IMG_HEIGHT = 28,
    parameter C_IN       = 6
)(
    input  wire                                             clk,
    input  wire                                             rst_n,

    // Tín hi?u ?i?u khi?n xóa s?ch toàn b? Pipeline khi chuy?n sang Frame ?nh m?i
    input  wire                                             frame_clear,

    // External Stream Input Interface
    input  wire                                             pixel_valid,
    input  wire [DATA_WIDTH-1:0]                            pixel_in,

    // =========================================================================
    // INTERFACE STAGE 1: LINE BUFFER OUTPUTS (C?t 3 pixels cùng v? trí)
    // =========================================================================
    output wire [DATA_WIDTH-1:0]                            row0_pixel, // Hàng current - 2
    output wire [DATA_WIDTH-1:0]                            row1_pixel, // Hàng current - 1
    output wire [DATA_WIDTH-1:0]                            row2_pixel, // Hàng current (Nh?n tr?c ti?p t? pixel_in)
    output wire                                             rows_valid, // C? báo ?ã ?? 3 hàng ?? c?p d? li?u cho Window Gen

    // =========================================================================
    // INTERFACE STAGE 2: WINDOW GEN OUTPUTS (Single-channel 3x3 Patch)
    // =========================================================================
    output wire [DATA_WIDTH*9-1:0]                          patch_3x3_data,
    output wire                                             patch_3x3_valid,

    // =========================================================================
    // INTERFACE STAGE 3: CHANNEL BUFFER OUTPUTS (Tensor 3x3xC_IN cho PE Array)
    // =========================================================================
    output wire [DATA_WIDTH*9*C_IN-1:0]                     patch_cin_data,
    output wire                                             patch_cin_valid,

    // Status Monitors
    output wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,
    output wire                                             frame_c_done
);

    // Dây n?i n?i b? báo k?t thúc m?t hàng
    wire new_row;

    // =========================================================================
    // STAGE 1: LINE BUFFER MODEL (VER3)
    // =========================================================================
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_line_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear),   // ??u n?i frame_clear
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),

        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .rows_valid   (rows_valid),
        .new_row      (new_row),

        .channel_idx  (channel_idx),
        .frame_c_done (frame_c_done)
    );

    // =========================================================================
    // STAGE 2: 3x3 WINDOW GENERATOR (VER3)
    // =========================================================================
    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_gen (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (frame_clear),      // ??u n?i frame_clear
        .pixel_valid      (rows_valid),
        .col_window_clear (new_row),
        
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),

        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // =========================================================================
    // STAGE 3: CHANNEL PATCH BUFFER (VER3)
    // =========================================================================
    channel_patch_buffer_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_IN      (C_IN)
    ) u_channel_patch_buffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_clear     (frame_clear),     // ??u n?i frame_clear
        .patch_3x3_valid (patch_3x3_valid),
        .patch_3x3_data  (patch_3x3_data),
        .channel_idx     (channel_idx),

        .patch_cin_valid (patch_cin_valid),
        .patch_cin_data  (patch_cin_data)
    );

endmodule