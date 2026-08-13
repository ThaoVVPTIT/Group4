`timescale 1ns/1ps

/*------------------------------------------------------------------------
 * Module: line_buffer_model_ver3
 *
 * Two-line buffer for a raster-scanned 3x3 sliding window.  Counters and
 * memories advance only on pixel_valid, so arbitrary bubbles in the input
 * stream do not alter the image coordinates.
 *------------------------------------------------------------------------*/
module line_buffer_model_ver3 #(
    parameter integer DATA_WIDTH = 8,
    parameter integer IMG_WIDTH  = 28,
    parameter integer IMG_HEIGHT = 28,
    parameter integer C_IN       = 1
)(
    input  wire                                               clk,
    input  wire                                               rst_n,
    input  wire                                               frame_clear,
    input  wire                                               pixel_valid,
    input  wire [DATA_WIDTH-1:0]                              pixel_in,

    output wire [DATA_WIDTH-1:0]                              row0_pixel,
    output wire [DATA_WIDTH-1:0]                              row1_pixel,
    output wire [DATA_WIDTH-1:0]                              row2_pixel,

    output wire                                               rows_valid,
    output wire                                               new_row,

    output reg  [((C_IN <= 1) ? 1 : $clog2(C_IN))-1:0]       channel_idx,
    output reg                                                frame_c_done
);

    localparam integer COL_CNT_WIDTH = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH);
    localparam integer ROW_CNT_WIDTH = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);

    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

    reg [COL_CNT_WIDTH-1:0] col_cnt;
    reg [ROW_CNT_WIDTH-1:0] row_cnt;

    integer i;

    /*
     * Before the active clock edge, mem_line0[col_cnt] and
     * mem_line1[col_cnt] contain the pixels two rows and one row above the
     * current input pixel.  The window generator samples all three values
     * on that edge, before the nonblocking memory updates take effect.
     */
    assign row0_pixel = mem_line0[col_cnt];
    assign row1_pixel = mem_line1[col_cnt];
    assign row2_pixel = pixel_in;

    /* Both qualifiers accompany the same accepted pixel beat. */
    assign rows_valid = pixel_valid && (row_cnt >= 2);
    assign new_row    = pixel_valid && (col_cnt == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
            col_cnt      <= {COL_CNT_WIDTH{1'b0}};
            row_cnt      <= {ROW_CNT_WIDTH{1'b0}};
            channel_idx  <= 0;
            frame_c_done <= 1'b0;

            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                mem_line0[i] <= {DATA_WIDTH{1'b0}};
                mem_line1[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            frame_c_done <= 1'b0;

            if (pixel_valid) begin
                mem_line0[col_cnt] <= mem_line1[col_cnt];
                mem_line1[col_cnt] <= pixel_in;

                if (col_cnt == IMG_WIDTH - 1) begin
                    col_cnt <= {COL_CNT_WIDTH{1'b0}};

                    if (row_cnt == IMG_HEIGHT - 1) begin
                        row_cnt <= {ROW_CNT_WIDTH{1'b0}};

                        if (channel_idx == C_IN - 1) begin
                            channel_idx  <= 0;
                            frame_c_done <= 1'b1;
                        end else begin
                            channel_idx <= channel_idx + 1'b1;
                        end
                    end else begin
                        row_cnt <= row_cnt + 1'b1;
                    end
                end else begin
                    col_cnt <= col_cnt + 1'b1;
                end
            end
        end
    end

endmodule
