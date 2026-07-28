//`timescale 1ns/1ps

//// ============================================================================
//// MODULE: line_buffer_model_ver3
////
//// Ch?c n?ng: B? ??m hàng (Line Buffer) dùng cho phép tính Tích ch?p 2D.
////            - L?u gi? 2 hàng c? trong RAM n?i b? (mem_line0, mem_line1).
////            - Xu?t ra 3 pixel cùng v? trí c?t thu?c 3 hàng liên ti?p (row0, row1, row2).
////            - H? tr? tín hi?u frame_clear ?? làm s?ch tr?ng thái khi chuy?n Frame.
//// ============================================================================

//module line_buffer_model_ver3 #(
//    parameter DATA_WIDTH = 8,
//    parameter IMG_WIDTH  = 28,
//    parameter IMG_HEIGHT = 28,
//    parameter C_IN       = 1
//)(
//    input  wire                                             clk,
//    input  wire                                             rst_n,

//    // Tín hi?u xóa tr?ng thái & RAM ??m ?? b?t ??u Frame m?i
//    input  wire                                             frame_clear,

//    // Giao di?n d? li?u Pixel ?i vào
//    input  wire                                             pixel_valid,
//    input  wire [DATA_WIDTH-1:0]                            pixel_in,

//    // D? li?u ??u ra: 3 Pixel cùng c?t c?a 3 hàng liên ti?p
//    output wire [DATA_WIDTH-1:0]                            row0_pixel, // Hàng c? h?n (Hàng current - 2)
//    output wire [DATA_WIDTH-1:0]                            row1_pixel, // Hàng tr??c ?ó (Hàng current - 1)
//    output wire [DATA_WIDTH-1:0]                            row2_pixel, // Hàng hi?n t?i (pixel_in)

//    // Tín hi?u ?i?u khi?n ??u ra
//    output wire                                             rows_valid, // Báo 3 pixel cùng c?t ?ã h?p l? (?? 3 hàng)
//    output reg                                              new_row,    // Xung báo v?a k?t thúc 1 hàng (chi?m 1 cycle)

//    // Qu?n lý Channel (Dành cho Conv2 v?i C_IN > 1)
//    output reg  [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]      channel_idx,
//    output reg                                              frame_c_done
//);

//    // ========================================================================
//    // LOCAL PARAMETERS & INTERNAL REGISTERS
//    // ========================================================================
//    localparam COL_CNT_WIDTH = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH);
//    localparam ROW_CNT_WIDTH = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);

//    // B? ??m Line RAM
//    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
//    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

//    // B? ??m v? trí
//    reg [COL_CNT_WIDTH-1:0] col_cnt;
//    reg [ROW_CNT_WIDTH-1:0] row_cnt;

//    // Tr?ng thái n?p ?m hàng (Warm-up phase):
//    // 2'b00: Ch?a có hàng nào
//    // 2'b01: ?ã n?p xong Hàng 0
//    // 2'b10: ?ã n?p xong Hàng 0 và Hàng 1 (?? ?i?u ki?n xu?t 3 hàng)
//    reg [1:0] row_phase;

//    reg row_end_tick;
//    reg chan_end_tick;

//    integer i;

//    // ========================================================================
//    // OUTPUT ASSIGNMENTS (READ RAM BEFORE WRITE LOGIC)
//    // ========================================================================
//    assign row0_pixel = mem_line0[col_cnt];
//    assign row1_pixel = mem_line1[col_cnt];
//    assign row2_pixel = pixel_in;

//    // rows_valid CH? H?P L? KHI:
//    // 1. Pixel ?i vào ?ang valid (pixel_valid = 1)
//    // 2. ?ã n?p ?? 2 hàng c? trong RAM (row_phase == 2'b10)
//    // 3. ?ang ? hàng th? 3 tr? ?i (row_cnt >= 2'd2) -> Tránh b?t s?m ? cu?i Hàng 1
//    assign rows_valid = (pixel_valid && (row_phase == 2'b10) && (row_cnt >= 2'd2));

//    // ========================================================================
//    // MAIN SEQUENTIAL LOGIC
//    // ========================================================================
//    always @(posedge clk or negedge rst_n) begin
        
//        // --------------------------------------------------------------------
//        // 1. HARD RESET
//        // --------------------------------------------------------------------
//        if (!rst_n) begin
//            col_cnt       <= {COL_CNT_WIDTH{1'b0}};
//            row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
//            row_phase     <= 2'b00;
//            channel_idx   <= 0;
//            row_end_tick  <= 1'b0;
//            chan_end_tick <= 1'b0;
//            new_row       <= 1'b0;
//            frame_c_done  <= 1'b0;

//            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
//                mem_line0[i] <= {DATA_WIDTH{1'b0}};
//                mem_line1[i] <= {DATA_WIDTH{1'b0}};
//            end
//        end

//        // --------------------------------------------------------------------
//        // 2. FRAME CLEAR (Reset ??ng b? khi b?t ??u Frame m?i)
//        // --------------------------------------------------------------------
//        else if (frame_clear) begin
//            col_cnt       <= {COL_CNT_WIDTH{1'b0}};
//            row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
//            row_phase     <= 2'b00;
//            channel_idx   <= 0;
//            row_end_tick  <= 1'b0;
//            chan_end_tick <= 1'b0;
//            new_row       <= 1'b0;
//            frame_c_done  <= 1'b0;

//            for (i = 0; i < IMG_WIDTH; i = i + 1) begin
//                mem_line0[i] <= {DATA_WIDTH{1'b0}};
//                mem_line1[i] <= {DATA_WIDTH{1'b0}};
//            end
//        end

//        // --------------------------------------------------------------------
//        // 3. NORMAL OPERATION
//        // --------------------------------------------------------------------
//        else begin
//            // M?c ??nh h? xung sau 1 clock
//            new_row      <= 1'b0;
//            frame_c_done <= 1'b0;

//            // X? lý xung báo chuy?n hàng
//            if (row_end_tick) begin
//                new_row      <= 1'b1;
//                row_end_tick <= 1'b0;
//            end

//            // X? lý chuy?n Kênh (Channel)
//            if (chan_end_tick) begin
//                chan_end_tick <= 1'b0;
//                if (channel_idx == C_IN - 1) begin
//                    channel_idx  <= 0;
//                    frame_c_done <= 1'b1;
//                end else begin
//                    channel_idx  <= channel_idx + 1'b1;
//                end
//            end

//            // X? lý khi có Pixel h?p l? chui vào Stream
//            if (pixel_valid) begin
                
//                // D?ch chuy?n b? ??m hàng (Shift Line Buffer)
//                mem_line0[col_cnt] <= mem_line1[col_cnt];
//                mem_line1[col_cnt] <= pixel_in;

//                // Khi ch?m c?t cu?i cùng c?a hàng hi?n t?i
//                if (col_cnt == IMG_WIDTH - 1) begin
//                    col_cnt      <= {COL_CNT_WIDTH{1'b0}};
//                    row_end_tick <= 1'b1;

//                    // T?ng pha tích l?y hàng cho ??n khi ?? 2 hàng c?
//                    if (row_phase < 2'b10) begin
//                        row_phase <= row_phase + 1'b1;
//                    end

//                    // Ki?m tra k?t thúc toàn b? Hàng c?a 1 Channel
//                    if (row_cnt == IMG_HEIGHT - 1) begin
//                        row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
//                        row_phase     <= 2'b00;
//                        chan_end_tick <= 1'b1;
//                    end else begin
//                        row_cnt <= row_cnt + 1'b1;
//                    end
//                end 
//                // Chuy?n sang c?t ti?p theo trong hàng
//                else begin
//                    col_cnt      <= col_cnt + 1'b1;
//                    row_end_tick <= 1'b0;
//                end
//            end
//        end
//    end

//endmodule

`timescale 1ns/1ps

// ============================================================================
// MODULE: line_buffer_model_ver3 (?Ã FIX L?I S?P ROW_PHASE V? 00 ? ROW CU?I)
// ============================================================================

`timescale 1ns/1ps

module line_buffer_model_ver3 #(
    parameter DATA_WIDTH = 8,
    parameter IMG_WIDTH  = 28,
    parameter IMG_HEIGHT = 28,
    parameter C_IN       = 1
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
    output reg                                                new_row,

    output reg  [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0]       channel_idx,
    output reg                                                frame_c_done
);

    localparam COL_CNT_WIDTH = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH);
    localparam ROW_CNT_WIDTH = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);

    reg [DATA_WIDTH-1:0] mem_line0 [0:IMG_WIDTH-1];
    reg [DATA_WIDTH-1:0] mem_line1 [0:IMG_WIDTH-1];

    reg [COL_CNT_WIDTH-1:0] col_cnt;
    reg [ROW_CNT_WIDTH-1:0] row_cnt;
    reg [1:0] row_phase;

    reg row_end_tick;
    reg chan_end_tick;
    integer i;

    assign row0_pixel = mem_line0[col_cnt];
    assign row1_pixel = mem_line1[col_cnt];
    assign row2_pixel = pixel_in;

    // rows_valid ch? kích ho?t khi pixel_valid ?ang b?t VÀ ?ã n?p ?? ít nh?t 2 dòng c?
    assign rows_valid = pixel_valid && (row_phase == 2'b10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || frame_clear) begin
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

            if (row_end_tick) begin
                new_row      <= 1'b1;
                row_end_tick <= 1'b0;
            end

            if (chan_end_tick) begin
                chan_end_tick <= 1'b0;
                if (channel_idx == C_IN - 1) begin
                    channel_idx  <= 0;
                    frame_c_done <= 1'b1;
                end else begin
                    channel_idx  <= channel_idx + 1'b1;
                end
            end

            if (pixel_valid) begin
                mem_line0[col_cnt] <= mem_line1[col_cnt];
                mem_line1[col_cnt] <= pixel_in;

                if (col_cnt == IMG_WIDTH - 1) begin
                    col_cnt      <= {COL_CNT_WIDTH{1'b0}};
                    row_end_tick <= 1'b1;

                    if (row_phase < 2'b10) begin
                        row_phase <= row_phase + 1'b1;
                    end

                    if (row_cnt == IMG_HEIGHT - 1) begin
                        row_cnt       <= {ROW_CNT_WIDTH{1'b0}};
                        // CHÚ Ý: Không reset row_phase v? 00 ? ?ây ?? tránh ng?t rows_valid nh?p cu?i
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