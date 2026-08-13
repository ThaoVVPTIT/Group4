`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 * Module: conv1_buf_new
 * One-channel 3x3 sliding-window buffer for a 28x28 input image.
 * The output uses row-major tap order with tap 0 in the LSB byte.
 *------------------------------------------------------------------------*/
module conv1_buf_new #(
    parameter WIDTH     = 28,
    parameter HEIGHT    = 28,
    parameter DATA_BITS = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         frame_clear,
    input  wire                         valid_in,
    input  wire signed [DATA_BITS-1:0]  data_in,
    output wire [(9*DATA_BITS)-1:0]     win_flat,
    output wire                         valid_out_buf
);

    wire [DATA_BITS-1:0] row0_p;
    wire [DATA_BITS-1:0] row1_p;
    wire [DATA_BITS-1:0] row2_p;
    wire                 rows_valid_w;
    wire                 new_row_w;

    // Two stored rows plus the current input row.
    line_buffer_model_ver3 #(
        .DATA_WIDTH (DATA_BITS),
        .IMG_WIDTH  (WIDTH),
        .IMG_HEIGHT (HEIGHT),
        .C_IN       (1)
    ) u_line_buf (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear),
        .pixel_valid  (valid_in),
        .pixel_in     (data_in),
        .row0_pixel   (row0_p),
        .row1_pixel   (row1_p),
        .row2_pixel   (row2_p),
        .rows_valid   (rows_valid_w),
        .new_row      (new_row_w),
        .channel_idx  (),
        .frame_c_done ()
    );

    // Horizontal shift registers produce the final 3x3 patch.
    window_generator_ver3 #(
        .DATA_WIDTH (DATA_BITS)
    ) u_win_gen (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (frame_clear),
        .pixel_valid      (rows_valid_w),
        .col_window_clear (new_row_w),
        .row0_pixel       (row0_p),
        .row1_pixel       (row1_p),
        .row2_pixel       (row2_p),
        .patch_3x3_data   (win_flat),
        .patch_3x3_valid  (valid_out_buf)
    );

endmodule
