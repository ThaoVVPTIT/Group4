//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: top_conv2_ver1 (STRICT VALID GATE & BOUNDARY COUNTER FIX)
//// ============================================================================

//module top_conv2_ver1 #(
//    parameter DATA_WIDTH  = 8,
//    parameter IMG_WIDTH   = 13,
//    parameter IMG_HEIGHT  = 13,
//    parameter KERNEL_SIZE = 3,
//    parameter C_IN        = 6, 
//    parameter C_OUT       = 16,
//    parameter ACC_WIDTH   = 32,
//    parameter MULT_WIDTH  = 32,
//    parameter SHIFT_WIDTH = 8
//)(
//    input  wire                         clk,
//    input  wire                         rst_n,

//    input  wire                         start,
//    input  wire                         frame_clear,
//    input  wire                         pixel_valid, 
//    input  wire signed [DATA_WIDTH*C_IN-1:0] pixel_in,

//    output wire                         conv2_out_valid,
//    output wire                         conv2_out_last,  
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch0,  conv2_out_ch1,  conv2_out_ch2,  conv2_out_ch3,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch4,  conv2_out_ch5,  conv2_out_ch6,  conv2_out_ch7,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch8,  conv2_out_ch9,  conv2_out_ch10, conv2_out_ch11,
//    output wire signed [DATA_WIDTH-1:0] conv2_out_ch12, conv2_out_ch13, conv2_out_ch14, conv2_out_ch15,
//    output wire                         conv2_done
//);

//    // ========================================================================
//    // 1. ROM WEIGHTS & BIAS
//    // ========================================================================
//    reg signed [DATA_WIDTH-1:0] c2_kernel [0:C_OUT*9*C_IN-1];
//    reg signed [ACC_WIDTH-1:0]  c2_bias   [0:C_OUT-1];         
//    reg signed [MULT_WIDTH-1:0] c2_mult   [0:C_OUT-1];         
//    reg        [SHIFT_WIDTH-1:0]c2_shift  [0:C_OUT-1];         

//    initial begin
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_kernel.mem",     c2_kernel);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_bias.mem",       c2_bias);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_multiplier.mem", c2_mult);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_shift.mem",      c2_shift);
//    end

//    // Xung clear duy nh?t 1-cycle khi start dâng lên
//    reg start_d;
//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) start_d <= 1'b0;
//        else        start_d <= start;
//    end
//    wire internal_clear = frame_clear || (start && !start_d);

//    // CH?N VALID RÁC: Ch? cho phép pixel_valid vào LineBuffer khi start = 1
//    wire pixel_valid_gated = pixel_valid && start;

//    // ========================================================================
//    // 2. STAGE SLIDING WINDOW (48-BIT BUS)
//    // ========================================================================
//    wire [DATA_WIDTH*C_IN-1:0] row0_p, row1_p, row2_p;
//    wire                       rows_valid, new_row;

//    line_buffer_model_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH * C_IN),
//        .IMG_WIDTH (IMG_WIDTH),
//        .IMG_HEIGHT(IMG_HEIGHT),
//        .C_IN      (1)
//    ) u_line_buf (
//        .clk          (clk),
//        .rst_n        (rst_n),
//        .frame_clear  (internal_clear),
//        .pixel_valid  (pixel_valid_gated),
//        .pixel_in     (pixel_in),
//        .row0_pixel   (row0_p),
//        .row1_pixel   (row1_p),
//        .row2_pixel   (row2_p),
//        .rows_valid   (rows_valid),
//        .new_row      (new_row),
//        .channel_idx  (),
//        .frame_c_done ()
//    );

//    wire [DATA_WIDTH*C_IN*9-1:0] patch_3x3_parallel;
//    wire                         patch_3x3_valid;

//    window_generator_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH * C_IN)
//    ) u_win_gen (
//        .clk              (clk),
//        .rst_n            (rst_n),
//        .frame_clear      (internal_clear),
//        .pixel_valid      (rows_valid),
//        .col_window_clear (new_row),
//        .row0_pixel       (row0_p),
//        .row1_pixel       (row1_p),
//        .row2_pixel       (row2_p),
//        .patch_3x3_data   (patch_3x3_parallel),
//        .patch_3x3_valid  (patch_3x3_valid)
//    );

//    // ========================================================================
//    // 3. PE ARRAY (16 PE)
//    // ========================================================================
//    wire signed [DATA_WIDTH-1:0] pe_out [0:C_OUT-1];
//    wire                         pe_valid[0:C_OUT-1];

//    genvar f, w_idx;
//    generate
//        for (f = 0; f < C_OUT; f = f + 1) begin : PE_LOOP
//            wire signed [DATA_WIDTH*9*C_IN-1:0] filter_w;
//            for (w_idx = 0; w_idx < 9*C_IN; w_idx = w_idx + 1) begin : W_PACK
//                assign filter_w[w_idx*DATA_WIDTH +: DATA_WIDTH] = c2_kernel[f*9*C_IN + w_idx];
//            end

//            conv2_pe #(
//                .DATA_WIDTH (DATA_WIDTH),
//                .C_IN       (C_IN),
//                .ACC_WIDTH  (ACC_WIDTH),
//                .MULT_WIDTH (MULT_WIDTH),
//                .SHIFT_WIDTH(SHIFT_WIDTH)
//            ) u_pe (
//                .clk          (clk),
//                .rst_n        (rst_n),
//                .frame_clear  (internal_clear),
//                .patch_valid  (patch_3x3_valid),
//                .patch_data   (patch_3x3_parallel),
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
//    // 4. B? ??M PIXEL ??U RA (KHÓA C?NG ?ÚNG 121 PIXELS)
//    // ========================================================================
//    localparam OUT_PIXELS_PER_CH = (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1); // 121
    
//    reg [11:0] out_cnt;
//    reg        conv2_done_reg;

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n || internal_clear) begin
//            out_cnt        <= 12'd0;
//            conv2_done_reg <= 1'b0;
//        end else if (pe_valid[0]) begin
//            if (out_cnt == OUT_PIXELS_PER_CH - 1) begin // M?c 120 (Pixel th? 121)
//                out_cnt        <= 12'd0;
//                conv2_done_reg <= 1'b1; 
//            end else begin
//                out_cnt <= out_cnt + 1'b1;
//            end
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

//    assign conv2_done = conv2_done_reg;

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_conv2_ver1 (L?C V?N HÀNH B?N V?NG - CH?NG TRÀN V?T XÀ)
// ============================================================================

module top_conv2_ver1 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 13, // Kích th??c ngõ vào t? Pool1 (13x13)
    parameter IMG_HEIGHT  = 13,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 6,  // 6 channels ??u vào
    parameter C_OUT       = 16, // 16 channels ??u ra
    parameter ACC_WIDTH   = 32,
    parameter MULT_WIDTH  = 32,
    parameter SHIFT_WIDTH = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Giao di?n ?i?u khi?n & AXI-Stream Slave
    input  wire                         start,
    input  wire                         frame_clear,
    input  wire                         pixel_valid, 
    input  wire signed [DATA_WIDTH*C_IN-1:0] pixel_in, // Bus 48-bit (6 ch x 8-bit)

    // Giao di?n AXI-Stream Master (16 Channels Output)
    output wire                         conv2_out_valid,
    output wire                         conv2_out_last,  
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch0,  conv2_out_ch1,  conv2_out_ch2,  conv2_out_ch3,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch4,  conv2_out_ch5,  conv2_out_ch6,  conv2_out_ch7,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch8,  conv2_out_ch9,  conv2_out_ch10, conv2_out_ch11,
    output wire signed [DATA_WIDTH-1:0] conv2_out_ch12, conv2_out_ch13, conv2_out_ch14, conv2_out_ch15,
    output wire                         conv2_done
);

    // ========================================================================
    // 1. DUNG L??NG TR?NG S? (WEIGHTS & BIAS ROM FOR 16 FILTERS)
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c2_kernel [0:C_OUT*9*C_IN-1];
    reg signed [ACC_WIDTH-1:0]  c2_bias   [0:C_OUT-1];         
    reg signed [MULT_WIDTH-1:0] c2_mult   [0:C_OUT-1];         
    reg        [SHIFT_WIDTH-1:0]c2_shift  [0:C_OUT-1];         

    initial begin
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_kernel.mem",     c2_kernel);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_bias.mem",       c2_bias);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_multiplier.mem", c2_mult);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv2_shift.mem",      c2_shift);
    end

    // T?o xung internal_clear 1-cycle khi start dâng lên
    reg start_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_d <= 1'b0;
        else        start_d <= start;
    end
    wire internal_clear = frame_clear || (start && !start_d);

    // Ch? nh?n pixel_valid khi start ?ang active
    wire pixel_valid_gated = pixel_valid && start;

    // ========================================================================
    // 2. STAGE SLIDING WINDOW (48-BIT BUS)
    // ========================================================================
    wire [DATA_WIDTH*C_IN-1:0] row0_p, row1_p, row2_p;
    wire                       rows_valid, new_row;

    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH * C_IN),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (1)
    ) u_line_buf (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (internal_clear),
        .pixel_valid  (pixel_valid_gated),
        .pixel_in     (pixel_in),
        .row0_pixel   (row0_p),
        .row1_pixel   (row1_p),
        .row2_pixel   (row2_p),
        .rows_valid   (rows_valid),
        .new_row      (new_row),
        .channel_idx  (),
        .frame_c_done ()
    );

    wire [DATA_WIDTH*C_IN*9-1:0] patch_3x3_parallel;
    wire                         patch_3x3_valid;

    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH * C_IN)
    ) u_win_gen (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (internal_clear),
        .pixel_valid      (rows_valid),
        .col_window_clear (new_row),
        .row0_pixel       (row0_p),
        .row1_pixel       (row1_p),
        .row2_pixel       (row2_p),
        .patch_3x3_data   (patch_3x3_parallel),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // ========================================================================
    // 3. PE ARRAY (16 PE)
    // ========================================================================
    wire signed [DATA_WIDTH-1:0] pe_out [0:C_OUT-1];
    wire                         pe_valid[0:C_OUT-1];

    genvar f, w_idx;
    generate
        for (f = 0; f < C_OUT; f = f + 1) begin : PE_LOOP
            wire signed [DATA_WIDTH*9*C_IN-1:0] filter_w;
            for (w_idx = 0; w_idx < 9*C_IN; w_idx = w_idx + 1) begin : W_PACK
                assign filter_w[w_idx*DATA_WIDTH +: DATA_WIDTH] = c2_kernel[f*9*C_IN + w_idx];
            end

            conv2_pe #(
                .DATA_WIDTH (DATA_WIDTH),
                .C_IN       (C_IN),
                .ACC_WIDTH  (ACC_WIDTH),
                .MULT_WIDTH (MULT_WIDTH),
                .SHIFT_WIDTH(SHIFT_WIDTH)
            ) u_pe (
                .clk          (clk),
                .rst_n        (rst_n),
                .frame_clear  (internal_clear),
                .patch_valid  (patch_3x3_valid),
                .patch_data   (patch_3x3_parallel),
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
    // 4. B? ??M PIXEL ??U RA (KHÓA C?NG ?ÚNG 121 PIXELS = 11x11)
    // ========================================================================
    localparam OUT_PIXELS_PER_CH = (IMG_WIDTH - KERNEL_SIZE + 1) * (IMG_HEIGHT - KERNEL_SIZE + 1); // 121
    
    reg [11:0] out_cnt;
    reg        conv2_done_reg;
    reg        frame_finished; // C? ch?n khi ??m ?? 121 pixels

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || internal_clear) begin
            out_cnt        <= 12'd0;
            conv2_done_reg <= 1'b0;
            frame_finished <= 1'b0;
        end else if (pe_valid[0] && !frame_finished) begin
            if (out_cnt == OUT_PIXELS_PER_CH - 1) begin // M?c index 120 (Pixel th? 121)
                out_cnt        <= out_cnt + 1'b1;
                conv2_done_reg <= 1'b1; 
                frame_finished <= 1'b1; // KHÓA M?CH: Không cho phép nh?n thêm b?t k? pixel rác nào!
            end else begin
                out_cnt <= out_cnt + 1'b1;
            end
        end
    end

    // ========================================================================
    // 5. MAPPING OUTPUT PORTS
    // ========================================================================
    // Valid b? c?t ngay khi frame_finished b?t cao
    assign conv2_out_valid = pe_valid[0] && !frame_finished; 
    
    // Phát xung LAST chính xác t?i pixel th? 121
    assign conv2_out_last  = pe_valid[0] && (out_cnt == OUT_PIXELS_PER_CH - 1);

    assign conv2_out_ch0  = pe_out[0];  assign conv2_out_ch1  = pe_out[1];
    assign conv2_out_ch2  = pe_out[2];  assign conv2_out_ch3  = pe_out[3];
    assign conv2_out_ch4  = pe_out[4];  assign conv2_out_ch5  = pe_out[5];
    assign conv2_out_ch6  = pe_out[6];  assign conv2_out_ch7  = pe_out[7];
    assign conv2_out_ch8  = pe_out[8];  assign conv2_out_ch9  = pe_out[9];
    assign conv2_out_ch10 = pe_out[10]; assign conv2_out_ch11 = pe_out[11];
    assign conv2_out_ch12 = pe_out[12]; assign conv2_out_ch13 = pe_out[13];
    assign conv2_out_ch14 = pe_out[14]; assign conv2_out_ch15 = pe_out[15];

    assign conv2_done = conv2_done_reg;

endmodule