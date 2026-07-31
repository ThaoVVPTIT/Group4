`timescale 1ns / 1ps

module conv1_top_ver4 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 28,
    parameter IMG_HEIGHT  = 28,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 1,
    parameter C_OUT       = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Giao di?n ?i?u khi?n FSM
    input  wire                         start,        
    output wire                         ready,        
    output wire                         done,         

    // Giao di?n Stream Pixel ??u vào
    input  wire                         pixel_valid,  
    input  wire signed [DATA_WIDTH-1:0] pixel_in,     

    // GIAO DI?N AXI-STREAM OUTPUT (X? SANG POOLING IP)
    output wire                         m_axis_valid,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch0,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch1,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch2,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch3,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch4,
    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch5,
    output wire                         m_axis_frame_clear 
);

    localparam OUTPUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;  // 26
    localparam OUTPUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 26
    localparam PATCH_COUNT      = OUTPUT_WIDTH * OUTPUT_HEIGHT;  // 676
    localparam PATCH_ADDR_WIDTH = (PATCH_COUNT <= 1) ? 1 : $clog2(PATCH_COUNT);

    reg busy;
    reg done_reg;
    reg frame_clear;

    assign ready              = !busy;
    assign done               = done_reg;
    assign m_axis_frame_clear = frame_clear; 

    // ?Ã S?A: B? gate busy/start ?? pixel_valid ?i th?ng vào Line Buffer
    wire pixel_valid_gate;
    assign pixel_valid_gate = pixel_valid; 

    // Dây n?i Stage 1 -> Stage 2
    wire [DATA_WIDTH-1:0] row0_pixel, row1_pixel, row2_pixel;
    wire                  rows_valid, new_row;

    // Dây n?i Stage 2 -> PE Array
    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    // ========================================================================
    // 1. STAGE 1: LINE BUFFER MODEL (VER3)
    // ========================================================================
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_line_buffer (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear),
        .pixel_valid  (pixel_valid_gate),
        .pixel_in     (pixel_in),

        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .rows_valid   (rows_valid),
        .new_row      (new_row),

        .channel_idx  (),
        .frame_c_done ()
    );

    // ========================================================================
    // 2. STAGE 2: 3x3 WINDOW GENERATOR (VER3)
    // ========================================================================
    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_window_generator (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (frame_clear),
        .pixel_valid      (rows_valid),
        .col_window_clear (new_row),
        
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),

        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // ========================================================================
    // 3. ROMS WEIGHTS / BIAS / QUANTIZATION PARAMETERS
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] c1_kernel [0:C_OUT*9-1]; 
    reg signed [31:0]           c1_bias   [0:C_OUT-1];   
    reg signed [31:0]           c1_mult   [0:C_OUT-1];   
    reg [7:0]                   c1_shift  [0:C_OUT-1];   

    initial begin
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_kernel.mem",     c1_kernel);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_bias.mem",       c1_bias);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_multiplier.mem", c1_mult);
        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_shift.mem",      c1_shift);
    end

    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    assign p0 = patch_3x3_data[71:64]; assign p1 = patch_3x3_data[63:56]; assign p2 = patch_3x3_data[55:48];
    assign p3 = patch_3x3_data[47:40]; assign p4 = patch_3x3_data[39:32]; assign p5 = patch_3x3_data[31:24];
    assign p6 = patch_3x3_data[23:16]; assign p7 = patch_3x3_data[15:8];  assign p8 = patch_3x3_data[7:0];

    wire signed [DATA_WIDTH-1:0] pe_output [0:C_OUT-1];
    wire                         pe_valid  [0:C_OUT-1];

    // ========================================================================
    // 4. INSTANTIATE 6 KH?I PE
    // ========================================================================
    conv1_pe u_pe_0 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[0]), .w1(c1_kernel[1]), .w2(c1_kernel[2]),
        .w3(c1_kernel[3]), .w4(c1_kernel[4]), .w5(c1_kernel[5]),
        .w6(c1_kernel[6]), .w7(c1_kernel[7]), .w8(c1_kernel[8]),
        .bias(c1_bias[0]), .multiplier(c1_mult[0]), .shift(c1_shift[0]),
        .output_data(pe_output[0]), .output_valid(pe_valid[0])
    );

    conv1_pe u_pe_1 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[9]),  .w1(c1_kernel[10]), .w2(c1_kernel[11]),
        .w3(c1_kernel[12]), .w4(c1_kernel[13]), .w5(c1_kernel[14]),
        .w6(c1_kernel[15]), .w7(c1_kernel[16]), .w8(c1_kernel[17]),
        .bias(c1_bias[1]), .multiplier(c1_mult[1]), .shift(c1_shift[1]),
        .output_data(pe_output[1]), .output_valid(pe_valid[1])
    );

    conv1_pe u_pe_2 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[18]), .w1(c1_kernel[19]), .w2(c1_kernel[20]),
        .w3(c1_kernel[21]), .w4(c1_kernel[22]), .w5(c1_kernel[23]),
        .w6(c1_kernel[24]), .w7(c1_kernel[25]), .w8(c1_kernel[26]),
        .bias(c1_bias[2]), .multiplier(c1_mult[2]), .shift(c1_shift[2]),
        .output_data(pe_output[2]), .output_valid(pe_valid[2])
    );

    conv1_pe u_pe_3 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[27]), .w1(c1_kernel[28]), .w2(c1_kernel[29]),
        .w3(c1_kernel[30]), .w4(c1_kernel[31]), .w5(c1_kernel[32]),
        .w6(c1_kernel[33]), .w7(c1_kernel[34]), .w8(c1_kernel[35]),
        .bias(c1_bias[3]), .multiplier(c1_mult[3]), .shift(c1_shift[3]),
        .output_data(pe_output[3]), .output_valid(pe_valid[3])
    );

    conv1_pe u_pe_4 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[36]), .w1(c1_kernel[37]), .w2(c1_kernel[38]),
        .w3(c1_kernel[39]), .w4(c1_kernel[40]), .w5(c1_kernel[41]),
        .w6(c1_kernel[42]), .w7(c1_kernel[43]), .w8(c1_kernel[44]),
        .bias(c1_bias[4]), .multiplier(c1_mult[4]), .shift(c1_shift[4]),
        .output_data(pe_output[4]), .output_valid(pe_valid[4])
    );

    conv1_pe u_pe_5 (
        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear), .patch_valid(patch_3x3_valid),
        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
        .w0(c1_kernel[45]), .w1(c1_kernel[46]), .w2(c1_kernel[47]),
        .w3(c1_kernel[48]), .w4(c1_kernel[49]), .w5(c1_kernel[50]),
        .w6(c1_kernel[51]), .w7(c1_kernel[52]), .w8(c1_kernel[53]),
        .bias(c1_bias[5]), .multiplier(c1_mult[5]), .shift(c1_shift[5]),
        .output_data(pe_output[5]), .output_valid(pe_valid[5])
    );

    // ========================================================================
    // 5. DIRECT AXI-STREAM OUTPUT ASSIGNMENT
    // ========================================================================
    assign m_axis_valid    = pe_valid[0];
    assign m_axis_data_ch0 = pe_output[0];
    assign m_axis_data_ch1 = pe_output[1];
    assign m_axis_data_ch2 = pe_output[2];
    assign m_axis_data_ch3 = pe_output[3];
    assign m_axis_data_ch4 = pe_output[4];
    assign m_axis_data_ch5 = pe_output[5];

    // ========================================================================
    // 6. FSM CONTROL LOGIC (?Ã T?I ?U C? CH? B?T BUSY)
    // ========================================================================
    reg [PATCH_ADDR_WIDTH-1:0] patch_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            patch_cnt   <= {PATCH_ADDR_WIDTH{1'b0}};
            busy        <= 1'b0;
            done_reg    <= 1'b0;
            frame_clear <= 1'b0;
        end else begin
            done_reg    <= 1'b0;
            frame_clear <= 1'b0;

            if (start && !busy) begin
                busy        <= 1'b1;
                frame_clear <= 1'b1; 
            end

            if (pe_valid[0]) begin
                if (patch_cnt == PATCH_COUNT - 1) begin
                    patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
                    busy      <= 1'b0;
                    done_reg  <= 1'b1; 
                end else begin
                    patch_cnt <= patch_cnt + 1'b1;
                end
            end
        end
    end

endmodule

//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: conv1_top_ver4
//// Ch?c n?ng: Top-level Tích ch?p Conv1 (28x28x1 -> 26x26x6) Zero-BRAM Streaming
//// ?ã fix: ??ng b? xung reset/frame_clear tri?t ?? cho toàn b? Pipeline
//// ============================================================================

//module conv1_top_ver4 #(
//    parameter DATA_WIDTH  = 8,
//    parameter IMG_WIDTH   = 28,
//    parameter IMG_HEIGHT  = 28,
//    parameter KERNEL_SIZE = 3,
//    parameter C_IN        = 1,
//    parameter C_OUT       = 6
//)(
//    input  wire                         clk,
//    input  wire                         rst_n,

//    // Giao di?n ?i?u khi?n FSM
//    input  wire                         start,        
//    output wire                         ready,        
//    output wire                         done,         

//    // Giao di?n Stream Pixel ??u vào
//    input  wire                         pixel_valid,  
//    input  wire signed [DATA_WIDTH-1:0] pixel_in,     

//    // GIAO DI?N AXI-STREAM OUTPUT (X? SANG POOLING IP)
//    output wire                         m_axis_valid,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch0,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch1,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch2,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch3,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch4,
//    output wire signed [DATA_WIDTH-1:0] m_axis_data_ch5,
//    output wire                         m_axis_frame_clear 
//);

//    localparam OUTPUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;  // 26
//    localparam OUTPUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 26
//    localparam PATCH_COUNT      = OUTPUT_WIDTH * OUTPUT_HEIGHT;  // 676
//    localparam PATCH_ADDR_WIDTH = (PATCH_COUNT <= 1) ? 1 : $clog2(PATCH_COUNT);

//    reg busy;
//    reg done_reg;
//    reg frame_clear;

//    assign ready              = !busy;
//    assign done               = done_reg;
//    assign m_axis_frame_clear = frame_clear; 

//    // ??a pixel_valid tr?c ti?p vào Line Buffer
//    wire pixel_valid_gate;
//    assign pixel_valid_gate = pixel_valid;

//    // Dây n?i Stage 1 -> Stage 2
//    wire [DATA_WIDTH-1:0] row0_pixel, row1_pixel, row2_pixel;
//    wire                  rows_valid, new_row;

//    // Dây n?i Stage 2 -> PE Array
//    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
//    wire                    patch_3x3_valid;

//    // ========================================================================
//    // 1. STAGE 1: LINE BUFFER MODEL (VER3)
//    // ========================================================================
//    line_buffer_model_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .IMG_WIDTH (IMG_WIDTH),
//        .IMG_HEIGHT(IMG_HEIGHT),
//        .C_IN      (C_IN)
//    ) u_line_buffer (
//        .clk          (clk),
//        .rst_n        (rst_n),
//        .frame_clear  (frame_clear || start), // ?Ã S?A: Thêm || start
//        .pixel_valid  (pixel_valid_gate),
//        .pixel_in     (pixel_in),

//        .row0_pixel   (row0_pixel),
//        .row1_pixel   (row1_pixel),
//        .row2_pixel   (row2_pixel),
//        .rows_valid   (rows_valid),
//        .new_row      (new_row),

//        .channel_idx  (),
//        .frame_c_done ()
//    );

//    // ========================================================================
//    // 2. STAGE 2: 3x3 WINDOW GENERATOR (VER3)
//    // ========================================================================
//    window_generator_ver3 #(
//        .DATA_WIDTH(DATA_WIDTH)
//    ) u_window_generator (
//        .clk              (clk),
//        .rst_n            (rst_n),
//        .frame_clear      (frame_clear || start), // ?Ã S?A: Thêm || start
//        .pixel_valid      (rows_valid),
//        .col_window_clear (new_row),
        
//        .row0_pixel       (row0_pixel),
//        .row1_pixel       (row1_pixel),
//        .row2_pixel       (row2_pixel),

//        .patch_3x3_data   (patch_3x3_data),
//        .patch_3x3_valid  (patch_3x3_valid)
//    );

//    // ========================================================================
//    // 3. ROMS WEIGHTS / BIAS / QUANTIZATION PARAMETERS
//    // ========================================================================
//    reg signed [DATA_WIDTH-1:0] c1_kernel [0:C_OUT*9-1]; 
//    reg signed [31:0]           c1_bias   [0:C_OUT-1];   
//    reg signed [31:0]           c1_mult   [0:C_OUT-1];   
//    reg [7:0]                   c1_shift  [0:C_OUT-1];   

//    initial begin
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_kernel.mem",     c1_kernel);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_bias.mem",       c1_bias);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_multiplier.mem", c1_mult);
//        $readmemh("E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/conv1_shift.mem",      c1_shift);
//    end

//    wire signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
//    assign p0 = patch_3x3_data[71:64]; assign p1 = patch_3x3_data[63:56]; assign p2 = patch_3x3_data[55:48];
//    assign p3 = patch_3x3_data[47:40]; assign p4 = patch_3x3_data[39:32]; assign p5 = patch_3x3_data[31:24];
//    assign p6 = patch_3x3_data[23:16]; assign p7 = patch_3x3_data[15:8];  assign p8 = patch_3x3_data[7:0];

//    wire signed [DATA_WIDTH-1:0] pe_output [0:C_OUT-1];
//    wire                         pe_valid  [0:C_OUT-1];

//    // ========================================================================
//    // 4. INSTANTIATE 6 KH?I PE (?Ã S?A C?NG FRAME_CLEAR V?I START)
//    // ========================================================================
//    conv1_pe u_pe_0 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[0]), .w1(c1_kernel[1]), .w2(c1_kernel[2]),
//        .w3(c1_kernel[3]), .w4(c1_kernel[4]), .w5(c1_kernel[5]),
//        .w6(c1_kernel[6]), .w7(c1_kernel[7]), .w8(c1_kernel[8]),
//        .bias(c1_bias[0]), .multiplier(c1_mult[0]), .shift(c1_shift[0]),
//        .output_data(pe_output[0]), .output_valid(pe_valid[0])
//    );

//    conv1_pe u_pe_1 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[9]),  .w1(c1_kernel[10]), .w2(c1_kernel[11]),
//        .w3(c1_kernel[12]), .w4(c1_kernel[13]), .w5(c1_kernel[14]),
//        .w6(c1_kernel[15]), .w7(c1_kernel[16]), .w8(c1_kernel[17]),
//        .bias(c1_bias[1]), .multiplier(c1_mult[1]), .shift(c1_shift[1]),
//        .output_data(pe_output[1]), .output_valid(pe_valid[1])
//    );

//    conv1_pe u_pe_2 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[18]), .w1(c1_kernel[19]), .w2(c1_kernel[20]),
//        .w3(c1_kernel[21]), .w4(c1_kernel[22]), .w5(c1_kernel[23]),
//        .w6(c1_kernel[24]), .w7(c1_kernel[25]), .w8(c1_kernel[26]),
//        .bias(c1_bias[2]), .multiplier(c1_mult[2]), .shift(c1_shift[2]),
//        .output_data(pe_output[2]), .output_valid(pe_valid[2])
//    );

//    conv1_pe u_pe_3 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[27]), .w1(c1_kernel[28]), .w2(c1_kernel[29]),
//        .w3(c1_kernel[30]), .w4(c1_kernel[31]), .w5(c1_kernel[32]),
//        .w6(c1_kernel[33]), .w7(c1_kernel[34]), .w8(c1_kernel[35]),
//        .bias(c1_bias[3]), .multiplier(c1_mult[3]), .shift(c1_shift[3]),
//        .output_data(pe_output[3]), .output_valid(pe_valid[3])
//    );

//    conv1_pe u_pe_4 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[36]), .w1(c1_kernel[37]), .w2(c1_kernel[38]),
//        .w3(c1_kernel[39]), .w4(c1_kernel[40]), .w5(c1_kernel[41]),
//        .w6(c1_kernel[42]), .w7(c1_kernel[43]), .w8(c1_kernel[44]),
//        .bias(c1_bias[4]), .multiplier(c1_mult[4]), .shift(c1_shift[4]),
//        .output_data(pe_output[4]), .output_valid(pe_valid[4])
//    );

//    conv1_pe u_pe_5 (
//        .clk(clk), .rst_n(rst_n), .frame_clear(frame_clear || start), .patch_valid(patch_3x3_valid),
//        .p0(p0), .p1(p1), .p2(p2), .p3(p3), .p4(p4), .p5(p5), .p6(p6), .p7(p7), .p8(p8),
//        .w0(c1_kernel[45]), .w1(c1_kernel[46]), .w2(c1_kernel[47]),
//        .w3(c1_kernel[48]), .w4(c1_kernel[49]), .w5(c1_kernel[50]),
//        .w6(c1_kernel[51]), .w7(c1_kernel[52]), .w8(c1_kernel[53]),
//        .bias(c1_bias[5]), .multiplier(c1_mult[5]), .shift(c1_shift[5]),
//        .output_data(pe_output[5]), .output_valid(pe_valid[5])
//    );

//    // ========================================================================
//    // 5. DIRECT AXI-STREAM OUTPUT ASSIGNMENT
//    // ========================================================================
//    assign m_axis_valid    = pe_valid[0];
//    assign m_axis_data_ch0 = pe_output[0];
//    assign m_axis_data_ch1 = pe_output[1];
//    assign m_axis_data_ch2 = pe_output[2];
//    assign m_axis_data_ch3 = pe_output[3];
//    assign m_axis_data_ch4 = pe_output[4];
//    assign m_axis_data_ch5 = pe_output[5];

//    // ========================================================================
//    // 6. FSM CONTROL LOGIC
//    // ========================================================================
//    reg [PATCH_ADDR_WIDTH-1:0] patch_cnt;

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            patch_cnt   <= {PATCH_ADDR_WIDTH{1'b0}};
//            busy        <= 1'b0;
//            done_reg    <= 1'b0;
//            frame_clear <= 1'b0;
//        end else begin
//            done_reg    <= 1'b0;
//            frame_clear <= 1'b0;

//            if (start && !busy) begin
//                busy        <= 1'b1;
//                frame_clear <= 1'b1; 
//            end

//            if (pe_valid[0]) begin
//                if (patch_cnt == PATCH_COUNT - 1) begin
//                    patch_cnt <= {PATCH_ADDR_WIDTH{1'b0}};
//                    busy      <= 1'b0;
//                    done_reg  <= 1'b1; 
//                end else begin
//                    patch_cnt <= patch_cnt + 1'b1;
//                end
//            end
//        end
//    end

//endmodule