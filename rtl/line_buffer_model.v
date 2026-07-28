`timescale 1ns/1ps

module line_buffer_model_ver2 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28,
    parameter IMG_HEIGHT = 28,
    parameter C_IN       = 6
)(
    input  wire                                             clk,
    input  wire                                             rst_n,

    input  wire                                             pixel_valid,
    input  wire [DATA_WIDTH-1:0]                            pixel_in,

    // D? li?u 3 pixel cùng c?t c?a Channel hi?n t?i
    output wire [DATA_WIDTH-1:0]                            row0_pixel,
    output wire [DATA_WIDTH-1:0]                            row1_pixel,
    output wire [DATA_WIDTH-1:0]                            row2_pixel,

    output wire                                             rows_valid, 
    output reg                                              new_row,

    output reg  [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,
    output reg                                              frame_c_done
);

    localparam COL_CNT_WIDTH = (IMG_WIDTH <= 1)  ? 1 : $clog2(IMG_WIDTH);
    localparam ROW_CNT_WIDTH = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);

    // M?ng b? ??m 2 hàng
    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

    reg [COL_CNT_WIDTH-1:0] col_cnt;
    reg [ROW_CNT_WIDTH-1:0] row_cnt;
    reg [1:0]               row_phase;
    reg                     row_end_tick;
    reg                     chan_end_tick; // C? trì hoãn chuy?n channel_idx sang nh?p sau

    integer i;

    // Read-Before-Write
    assign row0_pixel = mem_line0[col_cnt];
    assign row1_pixel = mem_line1[col_cnt];
    assign row2_pixel = pixel_in;

    // Xu?t rows_valid ngay l?p t?c cùng nh?p v?i pixel_in th? 3
//    assign rows_valid = (pixel_valid && (row_phase == 2'b10));
assign rows_valid = (pixel_valid && (row_phase == 2'b10) && (row_cnt >= 2'd2));


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt       <= {COL_CNT_WIDTH{1'b0}};
            row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
            row_phase     <= 2'b00;
            channel_idx   <= 0;
            row_end_tick  <= 1'b0;
            chan_end_tick <= 1'b0;
            new_row       <= 1'b0;
            frame_c_done  <= 1'b0;

            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
                mem_line0[i] <= {DATA_WIDTH{1'b0}};
                mem_line1[i] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            new_row      <= 1'b0;
            frame_c_done <= 1'b0;

            // X? lý c? new_row
            if (row_end_tick) begin
                new_row      <= 1'b1;
                row_end_tick <= 1'b0;
            end

            // N?U NH?P TR??C LÀ PIXEL CU?I C?A CHANNEL -> BÂY GI? M?I ???C T?NG CHANNEL_IDX!
            if (chan_end_tick) begin
                chan_end_tick <= 1'b0;
                if (channel_idx == C_IN - 1) begin
                    channel_idx  <= 0;
                    frame_c_done <= 1'b1; // Báo hoàn thành toàn b? C_IN channels
                end else begin
                    channel_idx  <= channel_idx + 1'b1;
                end
            end

            if (pixel_valid) begin
                mem_line1[col_cnt] <= pixel_in;
                mem_line0[col_cnt] <= mem_line1[col_cnt];

                if (col_cnt == IMG_WIDTH - 1) begin
                    col_cnt      <= {COL_CNT_WIDTH{1'b0}};
                    row_end_tick <= 1'b1;

                    if (row_phase < 2'b10) begin
                        row_phase <= row_phase + 1'b1;
                    end

                    if (row_cnt == IMG_HEIGHT - 1) begin
                        row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
                        row_phase     <= 2'b00;
                        
                        // ?ÁNH D?U K?T THÚC CHANNEL (Ch? nh?p clock sau m?i chuy?n channel_idx)
                        chan_end_tick <= 1'b1;

                    end else begin
                        row_cnt <= row_cnt + 1'b1;
                    end
                end else begin
                    col_cnt      <= col_cnt + 1'b1;
                    row_end_tick <= 1'b0;
                end
            end
        end
    end

endmodule