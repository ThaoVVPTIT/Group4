//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: conv1_pool1_top
//// Ch?c n?ng: Tích h?p Conv1 (28x28x1) -> Pool1 Streaming (13x13x6) Zero-BRAM
//// ============================================================================

//module top_conv1_pooling_ver1 #(
//    parameter DATA_WIDTH  = 8,
//    parameter IMG_WIDTH   = 28,
//    parameter IMG_HEIGHT  = 28,
//    parameter KERNEL_SIZE = 3,
//    parameter C_IN        = 1,
//    parameter C_OUT       = 6
//)(
//    input  wire                         clk,
//    input  wire                         rst_n,

//    input  wire                         start,             
//    output wire                         ready,            
//    output wire                         done,         

//    // Stream Pixel ??u vào (?nh 28x28)
//    input  wire                         pixel_valid,
//    input  wire signed [DATA_WIDTH-1:0] pixel_in,

//    // Stream Output k?t qu? Pooling (6 Channels song song) sang BRAM/Conv2
//    output wire                         pool_out_valid,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch0,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch1,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch2,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch3,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch4,
//    output wire signed [DATA_WIDTH-1:0] pool_out_ch5,
//    output wire                         pool_out_last       // Báo pixel cu?i cùng c?a Channel
//);

//    // Kích thuoc Feature Map sau Conv1: 26x26
//    localparam CONV1_OUT_W = IMG_WIDTH - KERNEL_SIZE + 1;
//    localparam CONV1_OUT_H = IMG_HEIGHT - KERNEL_SIZE + 1;

//    // Các ???ng dây AXI-Stream n?i gi?a Conv1 và Pool1
//    wire conv1_valid;
//    wire signed [DATA_WIDTH-1:0] conv1_ch0, conv1_ch1, conv1_ch2;
//    wire signed [DATA_WIDTH-1:0] conv1_ch3, conv1_ch4, conv1_ch5;
//    wire conv1_frame_clear;

//    // Dây c? hoàn thành t? 6 khoi Pooling
//    wire [C_OUT-1:0] pool_done_bus;
//    wire [C_OUT-1:0] pool_valid_bus;
//    wire [C_OUT-1:0] pool_last_bus;
//    wire signed [DATA_WIDTH-1:0] pool_data_bus [0:C_OUT-1];

//    // ========================================================================
//    // 1. MODULE CONV1 (VER4 - ZERO BRAM STREAMING)
//    // ========================================================================
//    conv1_top_ver4 #(
//        .DATA_WIDTH (DATA_WIDTH),
//        .IMG_WIDTH  (IMG_WIDTH),
//        .IMG_HEIGHT (IMG_HEIGHT),
//        .KERNEL_SIZE(KERNEL_SIZE),
//        .C_IN       (C_IN),
//        .C_OUT      (C_OUT)
//    ) u_conv1 (
//        .clk                (clk),
//        .rst_n              (rst_n),
//        .start              (start),
//        .ready              (ready),
//        .done               (),                  // FSM Top se dùng pool_frame_done làm co done tong

//        .pixel_valid        (pixel_valid),
//        .pixel_in           (pixel_in),

//        // Stream Data b?n sang Pool1
//        .m_axis_valid       (conv1_valid),
//        .m_axis_data_ch0    (conv1_ch0),
//        .m_axis_data_ch1    (conv1_ch1),
//        .m_axis_data_ch2    (conv1_ch2),
//        .m_axis_data_ch3    (conv1_ch3),
//        .m_axis_data_ch4    (conv1_ch4),
//        .m_axis_data_ch5    (conv1_ch5),
//        .m_axis_frame_clear (conv1_frame_clear)  // Kích xung pool_start
//    );

//    // M?ng h? tr? n?i dây vào Loop
//    wire signed [DATA_WIDTH-1:0] conv1_data_array [0:C_OUT-1];
//    assign conv1_data_array[0] = conv1_ch0;
//    assign conv1_data_array[1] = conv1_ch1;
//    assign conv1_data_array[2] = conv1_ch2;
//    assign conv1_data_array[3] = conv1_ch3;
//    assign conv1_data_array[4] = conv1_ch4;
//    assign conv1_data_array[5] = conv1_ch5;

//    // ========================================================================
//    // 2. KH?I T?O 6 KH?I STREAMING POOLING SONG SONG
//    // ========================================================================
//    genvar p;
//    generate
//        for (p = 0; p < C_OUT; p = p + 1) begin : GEN_POOL1_ARRAY
//            pool_top #(
//                .DATA_WIDTH (DATA_WIDTH),
//                .IMG_WIDTH  (CONV1_OUT_W), // 26
//                .IMG_HEIGHT (CONV1_OUT_H), // 26
//                .KERNEL_SIZE(2),           // 2x2
//                .STRIDE     (2),           // Stride 2
//                .C_OUT      (1)            // M?i IP x? lý 1 Channel
//            ) u_pool1 (
//                .clk               (clk),
//                .rst_n             (rst_n),

//                // Control
//                .pool_start        (conv1_frame_clear),
//                .pool_ready        (),
//                .pool_channel_done (),
//                .pool_frame_done   (pool_done_bus[p]),

//                // Slave Stream (Nh?n t? Conv1)
//                .s_axis_valid      (conv1_valid),
//                .s_axis_data       (conv1_data_array[p]),
//                .s_axis_ready      (),

//                // Master Stream (Xuat ket qua)
//                .m_axis_valid      (pool_valid_bus[p]),
//                .m_axis_data       (pool_data_bus[p]),
//                .m_axis_last       (pool_last_bus[p])
//            );
//        end
//    endgenerate

//    // ========================================================================
//    // 3. GÁN TÍN HI?U NGÕ RA H? TH?NG
//    // ========================================================================
//    assign pool_out_valid = pool_valid_bus[0];
//    assign pool_out_last  = pool_last_bus[0];

//    assign pool_out_ch0   = pool_data_bus[0];
//    assign pool_out_ch1   = pool_data_bus[1];
//    assign pool_out_ch2   = pool_data_bus[2];
//    assign pool_out_ch3   = pool_data_bus[3];
//    assign pool_out_ch4   = pool_data_bus[4];
//    assign pool_out_ch5   = pool_data_bus[5];

//    // Co DONE toàn bo he thong: Khi khoi Pooling cuoi cùng làm xong
//    assign done = pool_done_bus[0];

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_conv1_pooling_ver1
// Ch?c n?ng: Tích h?p Conv1 (28x28x1) -> Pool1 Streaming (13x13x6) Zero-BRAM
// ============================================================================

module top_conv1_pooling_ver1 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 28,
    parameter IMG_HEIGHT  = 28,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 1,
    parameter C_OUT       = 6
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         start,              
    output wire                         ready,             
    output wire                         done,          

    // Stream Pixel ??u vào (?nh 28x28)
    input  wire                         pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,

    // Stream Output k?t qu? Pooling (6 Channels song song)
    output wire                         pool_out_valid,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch0,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch1,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch2,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch3,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch4,
    output wire signed [DATA_WIDTH-1:0] pool_out_ch5,
    output wire                         pool_out_last       // Báo pixel th? 169 (cu?i cùng)
);

    // Kích th??c Feature Map sau Conv1: 26x26
    localparam CONV1_OUT_W = IMG_WIDTH - KERNEL_SIZE + 1;
    localparam CONV1_OUT_H = IMG_HEIGHT - KERNEL_SIZE + 1;

    // Các ???ng dây AXI-Stream n?i gi?a Conv1 và Pool1
    wire conv1_valid;
    wire signed [DATA_WIDTH-1:0] conv1_ch0, conv1_ch1, conv1_ch2;
    wire signed [DATA_WIDTH-1:0] conv1_ch3, conv1_ch4, conv1_ch5;
    wire conv1_frame_clear;

    // Dây c? hoàn thành t? 6 kh?i Pooling
    wire [C_OUT-1:0] pool_done_bus;
    wire [C_OUT-1:0] pool_valid_bus;
    wire [C_OUT-1:0] pool_last_bus;
    wire signed [DATA_WIDTH-1:0] pool_data_bus [0:C_OUT-1];

    // ========================================================================
    // 1. MODULE CONV1 (ZERO BRAM STREAMING)
    // ========================================================================
    conv1_top_ver4 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT)
    ) u_conv1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .ready              (ready),
        .done               (),                  

        .pixel_valid        (pixel_valid),
        .pixel_in           (pixel_in),

        // Stream Data b?n sang Pool1
        .m_axis_valid       (conv1_valid),
        .m_axis_data_ch0    (conv1_ch0),
        .m_axis_data_ch1    (conv1_ch1),
        .m_axis_data_ch2    (conv1_ch2),
        .m_axis_data_ch3    (conv1_ch3),
        .m_axis_data_ch4    (conv1_ch4),
        .m_axis_data_ch5    (conv1_ch5),
        .m_axis_frame_clear (conv1_frame_clear)  // Kích xung pool_start
    );

    // M?ng h? tr? n?i dây
    wire signed [DATA_WIDTH-1:0] conv1_data_array [0:C_OUT-1];
    assign conv1_data_array[0] = conv1_ch0;
    assign conv1_data_array[1] = conv1_ch1;
    assign conv1_data_array[2] = conv1_ch2;
    assign conv1_data_array[3] = conv1_ch3;
    assign conv1_data_array[4] = conv1_ch4;
    assign conv1_data_array[5] = conv1_ch5;

    // ========================================================================
    // 2. KH?I T?O 6 KH?I STREAMING POOLING SONG SONG
    // ========================================================================
    genvar p;
    generate
        for (p = 0; p < C_OUT; p = p + 1) begin : GEN_POOL1_ARRAY
            pool_top #(
                .DATA_WIDTH (DATA_WIDTH),
                .IMG_WIDTH  (CONV1_OUT_W), // 26
                .IMG_HEIGHT (CONV1_OUT_H), // 26
                .KERNEL_SIZE(2),           // 2x2
                .STRIDE     (2),           // Stride 2
                .C_OUT      (1)            // M?i IP x? lý 1 Channel
            ) u_pool1 (
                .clk                (clk),
                .rst_n              (rst_n),

                // Control
                .pool_start        (conv1_frame_clear),
                .pool_ready        (),
                .pool_channel_done (),
                .pool_frame_done   (pool_done_bus[p]),

                // Slave Stream (Nh?n t? Conv1)
                .s_axis_valid      (conv1_valid),
                .s_axis_data       (conv1_data_array[p]),
                .s_axis_ready      (),

                // Master Stream (Xu?t k?t qu?)
                .m_axis_valid      (pool_valid_bus[p]),
                .m_axis_data       (pool_data_bus[p]),
                .m_axis_last       (pool_last_bus[p])
            );
        end
    endgenerate

    // ========================================================================
    // 3. GÁN TÍN HI?U NGÕ RA H? TH?NG
    // ========================================================================
    assign pool_out_valid = pool_valid_bus[0];
    assign pool_out_last  = pool_last_bus[0]; // B?t 1 t?i Stream #169

    assign pool_out_ch0   = pool_data_bus[0];
    assign pool_out_ch1   = pool_data_bus[1];
    assign pool_out_ch2   = pool_data_bus[2];
    assign pool_out_ch3   = pool_data_bus[3];
    assign pool_out_ch4   = pool_data_bus[4];
    assign pool_out_ch5   = pool_data_bus[5];

    // C? DONE t?ng 1: ??ng b? khi pixel cu?i cùng c?a Pool1 xu?t x??ng
    assign done = pool_last_bus[0];

endmodule