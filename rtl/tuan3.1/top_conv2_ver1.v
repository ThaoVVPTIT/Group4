//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: top_conv2_ver1
//// Ch?c n?ng: T?ng Tích Ch?p Conv2 (C_IN = 6, C_OUT = 16, IMG_SIZE = 13x13).
//// Architecture: Streaming Interleaved Channels -> Spatial-Channel Window -> 16 PE
//// ============================================================================

//module top_conv2_ver1 #(
//    parameter DATA_WIDTH  = 8,
//    parameter IMG_WIDTH   = 13, // Kích th??c ngõ vào t? Pool1 (13x13)
//    parameter IMG_HEIGHT  = 13,
//    parameter KERNEL_SIZE = 3,
//    parameter C_IN        = 6,  // 6 channels ??u vào
//    parameter C_OUT       = 16, // 16 channels ??u ra
//    parameter ACC_WIDTH   = 32,
//    parameter MULT_WIDTH  = 32,
//    parameter SHIFT_WIDTH = 8
//)(
//    input  wire                         clk,
//    input  wire                         rst_n,

//    // Giao di?n ?i?u khi?n & AXI-Stream Slave
//    input  wire                         start,
//    input  wire                         frame_clear,
//    input  wire                         pixel_valid, // K?t n?i t? pool_out_valid
//    input  wire signed [DATA_WIDTH-1:0] pixel_in,    // Nh?n dòng pixel tu?n t? 6 channels

//    // Giao di?n AXI-Stream Master (16 Channels Output)
//    output wire                         conv2_out_valid,
//    output wire                         conv2_out_last,  // Xung báo pixel cu?i cùng c?a Frame
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch0,  conv2_out_ch1,  conv2_out_ch2,  conv2_out_ch3,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch4,  conv2_out_ch5,  conv2_out_ch6,  conv2_out_ch7,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch8,  conv2_out_ch9,  conv2_out_ch10, conv2_out_ch11,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch12, conv2_out_ch13, conv2_out_ch14, conv2_out_ch15,
//    output wire                         conv2_done
//);

//    // ========================================================================
//    // 1. DUNG L??NG TR?NG S? (WEIGHTS & BIAS ROM FOR 16 FILTERS)
//    // ========================================================================
//    reg signed [DATA_WIDTH-1:0] c2_kernel [0:C_OUT*9*C_IN-1]; // 16 * 9 * 6 = 864 weights
//    reg signed [ACC_WIDTH-1:0]  c2_bias   [0:C_OUT-1];         // 16 biases
//    reg signed [MULT_WIDTH-1:0] c2_mult   [0:C_OUT-1];         // 16 multipliers
//    reg        [SHIFT_WIDTH-1:0]c2_shift  [0:C_OUT-1];         // 16 shifts

//    // Kh?i t?o ??c Weights t? File HEX (Ho?c s?n sàng nh?n gán t? Testbench)
//    initial begin
//        $readmemh("conv2_weights.hex", c2_kernel);
//        $readmemh("conv2_bias.hex",    c2_bias);
//        $readmemh("conv2_mult.hex",    c2_mult);
//        $readmemh("conv2_shift.hex",   c2_shift);
//    end

//    // ========================================================================
//    // 2. K?T N?I T?NG SLIDING WINDOW & CHANNEL PATCH
//    // ========================================================================
//    wire [DATA_WIDTH-1:0] row0_p, row1_p, row2_p;
//    wire                  rows_valid, new_row;
//    wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0] channel_idx;
//    wire                  frame_c_done;

//    // 2.1. Line Buffer (Model Ver3)
//    line_buffer_model_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .IMG_WIDTH (IMG_WIDTH),
//        .IMG_HEIGHT(IMG_HEIGHT),
//        .C_IN      (C_IN)
//    ) u_line_buf (
//        .clk          (clk),
//        .rst_n        (rst_n),
//        .frame_clear  (frame_clear || start),
//        .pixel_valid  (pixel_valid),
//        .pixel_in     (pixel_in),
//        .row0_pixel   (row0_p),
//        .row1_pixel   (row1_p),
//        .row2_pixel   (row2_p),
//        .rows_valid   (rows_valid),
//        .new_row      (new_row),
//        .channel_idx  (channel_idx),
//        .frame_c_done (frame_c_done)
//    );

//    // 2.2. Window Generator (Ver3)
//    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
//    wire                    patch_3x3_valid;

//    window_generator_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH)
//    ) u_win_gen (
//        .clk             (clk),
//        .rst_n           (rst_n),
//        .frame_clear     (frame_clear || start),
//        .pixel_valid     (rows_valid),
//        .col_window_clear(new_row),
//        .row0_pixel      (row0_p),
//        .row1_pixel      (row1_p),
//        .row2_pixel      (row2_p),
//        .patch_3x3_data  (patch_3x3_data),
//        .patch_3x3_valid (patch_3x3_valid)
//    );

//    // 2.3. Channel Patch Buffer (Ver3 - Gom 3x3x6 Patch)
//    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
//    wire                         patch_cin_valid;

//    channel_patch_buffer_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .C_IN      (C_IN)
//    ) u_chan_buf (
//        .clk            (clk),
//        .rst_n          (rst_n),
//        .frame_clear    (frame_clear || start),
//        .patch_3x3_valid(patch_3x3_valid),
//        .patch_3x3_data (patch_3x3_data),
//        .channel_idx    (channel_idx),
//        .patch_cin_data (patch_cin_data),
//        .patch_cin_valid(patch_cin_valid)
//    );

//    // ========================================================================
//    // 3. PE ARRAY (16 PE SO-SONG TÍNH CHO 16 FILTERS)
//    // ========================================================================
//    wire signed [DATA_WIDTH-1:0] pe_out [0:C_OUT-1];
//    wire                         pe_valid[0:C_OUT-1];

//    genvar f, w_idx; // Khai báo genvar chu?n ngoài vòng l?p
//    generate
//        for (f = 0; f < C_OUT; f = f + 1) begin : PE_LOOP
            
//            // Gom 54 weights (3x3x6) cho Filter th? f
//            wire signed [DATA_WIDTH*9*C_IN-1:0] filter_w;
//            for (w_idx = 0; w_idx < 9*C_IN; w_idx = w_idx + 1) begin : W_PACK
//                assign filter_w[w_idx*DATA_WIDTH +: DATA_WIDTH] = c2_kernel[f*9*C_IN + w_idx];
//            end

//            // Instantiate PE th? f
//            conv2_pe #(
//                .DATA_WIDTH (DATA_WIDTH),
//                .C_IN       (C_IN),
//                .ACC_WIDTH  (ACC_WIDTH),
//                .MULT_WIDTH (MULT_WIDTH),
//                .SHIFT_WIDTH(SHIFT_WIDTH)
//            ) u_pe (
//                .clk          (clk),
//                .rst_n        (rst_n),
//                .frame_clear  (frame_clear || start),
//                .patch_valid  (patch_cin_valid),
//                .patch_data   (patch_cin_data),
//                .weights      (filter_w),
//                .bias         (c2_bias[f]),
//                .multiplier   (c2_mult[f]),
//                .shift        (c2_shift[f]),
//                .output_data  (pe_out[f]),
//                .output_valid (pe_valid[f])
//            );
//        end
//    endgenerate

//    // ========================================================================
//    // 4. B? ??M PIXEL ??U RA & TÍN HI?U LAST
//    // ========================================================================
//    localparam OUT_PIXELS_PER_CH = (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1); // 11x11 = 121
//    reg [11:0] out_cnt;

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n || start || frame_clear) begin
//            out_cnt <= 12'd0;
//        end else if (pe_valid[0]) begin
//            if (out_cnt == OUT_PIXELS_PER_CH - 1)
//                out_cnt <= 12'd0;
//            else
//                out_cnt <= out_cnt + 1'b1;
//        end
//    end

//    // ========================================================================
//    // 5. MAPPING OUTPUT PORTS
//    // ========================================================================
//    assign conv2_out_valid = pe_valid[0]; 
//    assign conv2_out_last  = pe_valid[0] && (out_cnt == OUT_PIXELS_PER_CH - 1);

//    assign conv2_out_ch0  = pe_out[0];  assign conv2_out_ch1  = pe_out[1];
//    assign conv2_out_ch2  = pe_out[2];  assign conv2_out_ch3  = pe_out[3];
//    assign conv2_out_ch4  = pe_out[4];  assign conv2_out_ch5  = pe_out[5];
//    assign conv2_out_ch6  = pe_out[6];  assign conv2_out_ch7  = pe_out[7];
//    assign conv2_out_ch8  = pe_out[8];  assign conv2_out_ch9  = pe_out[9];
//    assign conv2_out_ch10 = pe_out[10]; assign conv2_out_ch11 = pe_out[11];
//    assign conv2_out_ch12 = pe_out[12]; assign conv2_out_ch13 = pe_out[13];
//    assign conv2_out_ch14 = pe_out[14]; assign conv2_out_ch15 = pe_out[15];

//    assign conv2_done = frame_c_done;

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_conv2_ver1
// Chuc nang: Tang Tich Chop Conv2 (C_IN = 6, C_OUT = 16, IMG_SIZE = 13x13).
// Architecture: Streaming Interleaved Channels -> Spatial-Channel Window -> 16 PE
// ============================================================================

module top_conv2_ver1 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 13, // Kich thuoc ngo vao tu Pool1 (13x13)
    parameter IMG_HEIGHT  = 13,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 6,  // 6 channels dau vao
    parameter C_OUT       = 16, // 16 channels dau ra
    parameter ACC_WIDTH   = 32,
    parameter MULT_WIDTH  = 32,
    parameter SHIFT_WIDTH = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Giao dien dieu khien & AXI-Stream Slave
    input  wire                         start,
    input  wire                         frame_clear,
    input  wire                         pixel_valid, // Ket noi tu pool_out_valid
    input  wire signed [DATA_WIDTH-1:0] pixel_in,    // Nhan dong pixel tuan tu 6 channels

    // Giao dien AXI-Stream Master (16 Channels Output)
    output wire                         conv2_out_valid,
    output wire                         conv2_out_last,  // Xung bao pixel cuoi cùng cua Frame
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch0,  conv2_out_ch1,  conv2_out_ch2,  conv2_out_ch3,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch4,  conv2_out_ch5,  conv2_out_ch6,  conv2_out_ch7,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch8,  conv2_out_ch9,  conv2_out_ch10, conv2_out_ch11,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch12, conv2_out_ch13, conv2_out_ch14, conv2_out_ch15,
    output wire                         conv2_done
);

    // ========================================================================
    // 1. DUNG LUONG TRONG SO (WEIGHTS & BIAS ROM FOR 16 FILTERS)
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c2_kernel [0:C_OUT*9*C_IN-1]; // 16 * 9 * 6 = 864 weights
    reg signed [ACC_WIDTH-1:0]  c2_bias   [0:C_OUT-1];         // 16 biases
    reg signed [MULT_WIDTH-1:0] c2_mult   [0:C_OUT-1];         // 16 multipliers
    reg        [SHIFT_WIDTH-1:0]c2_shift  [0:C_OUT-1];         // 16 shifts

    // Khoi tao doc Weights tu File HEX
    initial begin
        $readmemh("conv2_weights.hex", c2_kernel);
        $readmemh("conv2_bias.hex",    c2_bias);
        $readmemh("conv2_mult.hex",    c2_mult);
        $readmemh("conv2_shift.hex",   c2_shift);
    end

    // ========================================================================
    // 2. KET NOI TANG SLIDING WINDOW & CHANNEL PATCH
    // ========================================================================
    wire [DATA_WIDTH-1:0] row0_p, row1_p, row2_p;
    wire                  rows_valid, new_row;
    wire [(C_IN <= 1 ? 0 : $clog2(C_IN)-1) : 0] channel_idx;
    wire                  frame_c_done;

    // 2.1. Line Buffer (Model Ver3)
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_line_buf (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear || start),
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),
        .row0_pixel   (row0_p),
        .row1_pixel   (row1_p),
        .row2_pixel   (row2_p),
        .rows_valid   (rows_valid),
        .new_row      (new_row),
        .channel_idx  (channel_idx),
        .frame_c_done (frame_c_done)
    );

    // 2.2. Window Generator (Ver3)
    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_win_gen (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_clear     (frame_clear || start),
        .pixel_valid     (rows_valid),
        .col_window_clear(new_row),
        .row0_pixel      (row0_p),
        .row1_pixel      (row1_p),
        .row2_pixel      (row2_p),
        .patch_3x3_data  (patch_3x3_data),
        .patch_3x3_valid (patch_3x3_valid)
    );

    // 2.3. Channel Patch Buffer (Ver3 - Gom 3x3x6 Patch)
    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
    wire                         patch_cin_valid;

    channel_patch_buffer_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_IN      (C_IN)
    ) u_chan_buf (
        .clk            (clk),
        .rst_n          (rst_n),
        .frame_clear    (frame_clear || start),
        .patch_3x3_valid(patch_3x3_valid),
        .patch_3x3_data (patch_3x3_data),
        .channel_idx    (channel_idx),
        .patch_cin_data (patch_cin_data),
        .patch_cin_valid(patch_cin_valid)
    );

    // ========================================================================
    // 3. PE ARRAY (16 PE SO-SONG TINH CHO 16 FILTERS)
    // ========================================================================
    wire signed [DATA_WIDTH-1:0] pe_out [0:C_OUT-1];
    wire                         pe_valid[0:C_OUT-1];

    genvar f, w_idx;
    generate
        for (f = 0; f < C_OUT; f = f + 1) begin : PE_LOOP
            
            // Gom 54 weights (3x3x6) cho Filter thu f
            wire signed [DATA_WIDTH*9*C_IN-1:0] filter_w;
            for (w_idx = 0; w_idx < 9*C_IN; w_idx = w_idx + 1) begin : W_PACK
                assign filter_w[w_idx*DATA_WIDTH +: DATA_WIDTH] = c2_kernel[f*9*C_IN + w_idx];
            end

            // Instantiate PE thu f
            conv2_pe #(
                .DATA_WIDTH (DATA_WIDTH),
                .C_IN       (C_IN),
                .ACC_WIDTH  (ACC_WIDTH),
                .MULT_WIDTH (MULT_WIDTH),
                .SHIFT_WIDTH(SHIFT_WIDTH)
            ) u_pe (
                .clk          (clk),
                .rst_n        (rst_n),
                .frame_clear  (frame_clear || start),
                .patch_valid  (patch_cin_valid),
                .patch_data   (patch_cin_data),
                .weights      (filter_w),
                .bias         (c2_bias[f]),
                .multiplier   (c2_mult[f]),
                .shift        (c2_shift[f]),
                .output_data  (pe_out[f]),
                .output_valid (pe_valid[f])
            );
        end
    endgenerate

   // ========================================================================
    // 4. B? ??M PIXEL ??U RA & TÍN HI?U ?I?U KHI?N (L?C GLITCH M?U ??U)
    // ========================================================================
    localparam OUT_PIXELS_PER_CH = (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1); // 121
    
    reg [11:0] out_cnt;
    reg        frame_done_reg;
    reg        first_valid_seen; // C? ?ánh d?u ?ã b? qua m?u rác ??u tiên

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || start || frame_clear) begin
            out_cnt          <= 12'd0;
            frame_done_reg   <= 1'b0;
            first_valid_seen <= 1'b0;
        end else if (pe_valid[0] && !frame_done_reg) begin
            // N?u phát hi?n pulse valid ??u tiên khi d? li?u v?n b?ng 0 (Glitch)
            if (!first_valid_seen) begin
                if (pe_out[0] == 8'sd0) begin
                    // B? qua sample rác ??u tiên, KHÔNG t?ng out_cnt
                    first_valid_seen <= 1'b1; 
                end else begin
                    // N?u ngay t? ??u data ?ã ?úng (không b? rác)
                    first_valid_seen <= 1'b1;
                    out_cnt          <= out_cnt + 1'b1;
                end
            end else begin
                // Các sample d? li?u th?t phía sau
                if (out_cnt == OUT_PIXELS_PER_CH - 1) begin
                    out_cnt        <= out_cnt + 1'b1;
                    frame_done_reg <= 1'b1; // ?? 121 patch th?c t? -> Khóa h?n valid
                end else begin
                    out_cnt <= out_cnt + 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // 5. MAPPING OUTPUT PORTS (L?C XUNG VALID RÁC)
    // ========================================================================
    // Ch? b?t valid khi PE valid, CH?A xong frame VÀ ?Ã B? QUA xung rác ??u tiên (ho?c data khác 0)
    assign conv2_out_valid = pe_valid[0] && !frame_done_reg && 
                             (first_valid_seen || pe_out[0] != 8'sd0); 
    
    // Tín hi?u LAST ch? b?t ? ?úng patch th? 121 chu?n
    assign conv2_out_last  = conv2_out_valid && (out_cnt == OUT_PIXELS_PER_CH - 1);

    assign conv2_out_ch0  = pe_out[0];  assign conv2_out_ch1  = pe_out[1];
    assign conv2_out_ch2  = pe_out[2];  assign conv2_out_ch3  = pe_out[3];
    assign conv2_out_ch4  = pe_out[4];  assign conv2_out_ch5  = pe_out[5];
    assign conv2_out_ch6  = pe_out[6];  assign conv2_out_ch7  = pe_out[7];
    assign conv2_out_ch8  = pe_out[8];  assign conv2_out_ch9  = pe_out[9];
    assign conv2_out_ch10 = pe_out[10]; assign conv2_out_ch11 = pe_out[11];
    assign conv2_out_ch12 = pe_out[12]; assign conv2_out_ch13 = pe_out[13];
    assign conv2_out_ch14 = pe_out[14]; assign conv2_out_ch15 = pe_out[15];

    assign conv2_done = frame_done_reg || frame_c_done;

endmodule