`timescale 1ns / 1ps

/*------------------------------------------------------------------------
 *  Module: conv2_buf_new
 *  Design : Depth-Parallel Sliding Window Buffer (8 Channels)
 *------------------------------------------------------------------------*/
module conv2_buf_new #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 13,
    parameter IMG_HEIGHT = 13,
    parameter IN_CH      = 8
)(
    input  wire                                 clk,
    input  wire                                 rst_n,
    input  wire                                 frame_clear,
    
    input  wire                                 valid_in,
    input  wire [(IN_CH*DATA_WIDTH)-1:0]        data_in_flat,

    output wire [(IN_CH*9*DATA_WIDTH)-1:0]      win_flat,
    output wire                                 valid_out_buf
);

    wire [DATA_WIDTH-1:0] row0_ch [0:IN_CH-1];
    wire [DATA_WIDTH-1:0] row1_ch [0:IN_CH-1];
    wire [DATA_WIDTH-1:0] row2_ch [0:IN_CH-1];

    wire                  rows_valid_ch [0:IN_CH-1];
    wire                  new_row_ch    [0:IN_CH-1];

    wire [DATA_WIDTH*9-1:0] patch_ch    [0:IN_CH-1];
    wire [IN_CH-1:0]       valid_ch;

    genvar c;
    generate
        for (c = 0; c < IN_CH; c = c + 1) begin : g_depth_parallel_sliding

            line_buffer_model_ver3 #(
                .DATA_WIDTH (DATA_WIDTH),
                .IMG_WIDTH  (IMG_WIDTH),
                .IMG_HEIGHT (IMG_HEIGHT),
                .C_IN       (1)           
            ) u_line_buf_ch (
                .clk          (clk),
                .rst_n        (rst_n),
                .frame_clear  (frame_clear),
                .pixel_valid  (valid_in),
                .pixel_in     (data_in_flat[c*DATA_WIDTH +: DATA_WIDTH]),
                .row0_pixel   (row0_ch[c]),
                .row1_pixel   (row1_ch[c]),
                .row2_pixel   (row2_ch[c]),
                .rows_valid   (rows_valid_ch[c]),
                .new_row      (new_row_ch[c]),
                .channel_idx  (),
                .frame_c_done ()
            );

            window_generator_ver3 #(
                .DATA_WIDTH (DATA_WIDTH)
            ) u_win_gen_ch (
                .clk              (clk),
                .rst_n            (rst_n),
                .frame_clear      (frame_clear),
                .pixel_valid      (rows_valid_ch[c]),
                .col_window_clear (new_row_ch[c]),
                .row0_pixel       (row0_ch[c]),
                .row1_pixel       (row1_ch[c]),
                .row2_pixel       (row2_ch[c]),
                .patch_3x3_data   (patch_ch[c]),
                .patch_3x3_valid  (valid_ch[c])
            );

            assign win_flat[c*(9*DATA_WIDTH) +: (9*DATA_WIDTH)] = patch_ch[c];

        end
    endgenerate

    /* All channel instances see the same valid and coordinates. */
    assign valid_out_buf = &valid_ch;

endmodule
