////`timescale 1ns / 1ps

////// ============================================================================
////// MODULE: top_conv2_pooling2
////// Ch?c n?ng: K?t n?i CONV2 (13x13x6 -> 11x11x16) v?i Array 16 kh?i POOL2
////// ============================================================================

////module top_conv2_pooling2 #(
////    parameter DATA_WIDTH  = 8,
////    parameter IMG_WIDTH   = 13,
////    parameter IMG_HEIGHT  = 13,
////    parameter KERNEL_SIZE = 3,
////    parameter C_IN        = 6,  
////    parameter C_OUT       = 16  
////)(
////    input  wire clk,
////    input  wire rst_n,
////    input  wire start,
////    input  wire frame_clear,
    
////    // Interface Stream ??u vào (Bus 48-bit)
////    input  wire pixel_valid,
////    input  wire signed [DATA_WIDTH*C_IN-1:0] pixel_in, 
    
////    // Interface Stream ??u ra t? Pool2 Array (Bus 128-bit)
////    output wire [C_OUT-1:0] pool_out_valid,
////    output wire signed [DATA_WIDTH*C_OUT-1:0] pool_out_ch,
////    output wire [C_OUT-1:0] pool_out_last
////);

////    wire conv2_valid;
////    wire conv2_last;
////    wire signed [DATA_WIDTH-1:0] conv2_ch [0:C_OUT-1];

////    // Module Conv2 Top
////    top_conv2_ver1 #(
////        .DATA_WIDTH (DATA_WIDTH),
////        .IMG_WIDTH  (IMG_WIDTH),
////        .IMG_HEIGHT (IMG_HEIGHT),
////        .KERNEL_SIZE(KERNEL_SIZE),
////        .C_IN       (C_IN),
////        .C_OUT      (C_OUT)
////    ) u_conv2 (
////        .clk             (clk),
////        .rst_n           (rst_n),
////        .start           (start),
////        .frame_clear     (frame_clear),
////        .pixel_valid     (pixel_valid),
////        .pixel_in        (pixel_in),

////        .conv2_out_valid (conv2_valid),
////        .conv2_out_last  (conv2_last),
        
////        .conv2_out_ch0   (conv2_ch[0]),  .conv2_out_ch1 (conv2_ch[1]),
////        .conv2_out_ch2   (conv2_ch[2]),  .conv2_out_ch3 (conv2_ch[3]),
////        .conv2_out_ch4   (conv2_ch[4]),  .conv2_out_ch5 (conv2_ch[5]),
////        .conv2_out_ch6   (conv2_ch[6]),  .conv2_out_ch7 (conv2_ch[7]),
////        .conv2_out_ch8   (conv2_ch[8]),  .conv2_out_ch9 (conv2_ch[9]),
////        .conv2_out_ch10  (conv2_ch[10]), .conv2_out_ch11(conv2_ch[11]),
////        .conv2_out_ch12  (conv2_ch[12]), .conv2_out_ch13(conv2_ch[13]),
////        .conv2_out_ch14  (conv2_ch[14]), .conv2_out_ch15(conv2_ch[15]),
////        .conv2_done      ()
////    );

////    // Array 16 kh?i Pooling 2
////    genvar i;
////    generate
////        for (i = 0; i < C_OUT; i = i + 1) begin : gen_pool2_array
////            pool_top #(
////                .DATA_WIDTH (DATA_WIDTH),
////                .IMG_WIDTH  (11), // Kích th??c sau Conv2 là 11x11
////                .IMG_HEIGHT (11),
////                .KERNEL_SIZE(2), 
////                .STRIDE     (2), 
////                .C_OUT      (1)  
////            ) u_pool2_inst (
////                .clk                (clk),
////                .rst_n              (rst_n),
////                .pool_start         (start),
////                .pool_ready         (),
////                .pool_channel_done  (),
////                .pool_frame_done    (),

////                .s_axis_valid      (conv2_valid),
////                .s_axis_data       (conv2_ch[i]),
////                .s_axis_ready      (),

////                .m_axis_valid      (pool_out_valid[i]),
////                .m_axis_data       (pool_out_ch[DATA_WIDTH*i +: DATA_WIDTH]), 
////                .m_axis_last       (pool_out_last[i])
////            );
////        end
////    endgenerate

////endmodule

//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: top_conv2_pooling2 (FIXED PORT MAPPING)
//// ============================================================================

//module top_conv2_pooling2 #(
//    parameter DATA_WIDTH  = 8,
//    parameter IMG_WIDTH   = 13,
//    parameter IMG_HEIGHT  = 13,
//    parameter KERNEL_SIZE = 3,
//    parameter C_IN        = 6,  
//    parameter C_OUT       = 16  
//)(
//    input  wire clk,
//    input  wire rst_n,
//    input  wire start,
//    input  wire frame_clear,
    
//    // Interface Stream ??u vào (Bus 48-bit)
//    input  wire pixel_valid,                         // Dây valid t? Pool1
//    input  wire signed [DATA_WIDTH*C_IN-1:0] pixel_in, // Bus 48-bit t? Pool1
    
//    // Interface Stream ??u ra Pool2
//    output wire [C_OUT-1:0] pool_out_valid,
//    output wire signed [DATA_WIDTH*C_OUT-1:0] pool_out_ch,
//    output wire [C_OUT-1:0] pool_out_last
//);

//    wire conv2_valid;
//    wire conv2_last;
//    wire signed [DATA_WIDTH-1:0] conv2_ch [0:C_OUT-1];

//    // =========================================================
//    // INSTANTIATE CONV2 TOP
//    // =========================================================
//    top_conv2_ver1 #(
//        .DATA_WIDTH (DATA_WIDTH),
//        .IMG_WIDTH  (IMG_WIDTH),
//        .IMG_HEIGHT (IMG_HEIGHT),
//        .KERNEL_SIZE(KERNEL_SIZE),
//        .C_IN       (C_IN),
//        .C_OUT      (C_OUT)
//    ) u_conv2 (
//        .clk             (clk),
//        .rst_n           (rst_n),
//        .start           (start),
//        .frame_clear     (frame_clear),
        
//        // ?Ã FIX: ??m b?o n?i pixel_valid ngu?n tr?c ti?p vào u_conv2
//        .pixel_valid     (pixel_valid),             
//        .pixel_in        (pixel_in),

//        .conv2_out_valid (conv2_valid),
//        .conv2_out_last  (conv2_last),
        
//        .conv2_out_ch0   (conv2_ch[0]),  .conv2_out_ch1 (conv2_ch[1]),
//        .conv2_out_ch2   (conv2_ch[2]),  .conv2_out_ch3 (conv2_ch[3]),
//        .conv2_out_ch4   (conv2_ch[4]),  .conv2_out_ch5 (conv2_ch[5]),
//        .conv2_out_ch6   (conv2_ch[6]),  .conv2_out_ch7 (conv2_ch[7]),
//        .conv2_out_ch8   (conv2_ch[8]),  .conv2_out_ch9 (conv2_ch[9]),
//        .conv2_out_ch10  (conv2_ch[10]), .conv2_out_ch11(conv2_ch[11]),
//        .conv2_out_ch12  (conv2_ch[12]), .conv2_out_ch13(conv2_ch[13]),
//        .conv2_out_ch14  (conv2_ch[14]), .conv2_out_ch15(conv2_ch[15]),
//        .conv2_done      ()
//    );

//    // =========================================================
//    // INSTANTIATE POOL2 ARRAY (16 INSTANCES)
//    // =========================================================
//    genvar i;
//    generate
//        for (i = 0; i < C_OUT; i = i + 1) begin : gen_pool2_array
//            pool_top #(
//                .DATA_WIDTH (DATA_WIDTH),
//                .IMG_WIDTH  (11), 
//                .IMG_HEIGHT (11),
//                .KERNEL_SIZE(2), 
//                .STRIDE     (2), 
//                .C_OUT      (1)  
//            ) u_pool2_inst (
//                .clk                (clk),
//                .rst_n              (rst_n),
//                .pool_start         (start),
//                .pool_ready         (),
//                .pool_channel_done  (),
//                .pool_frame_done    (),

//                .s_axis_valid      (conv2_valid),
//                .s_axis_data       (conv2_ch[i]),
//                .s_axis_ready      (),

//                .m_axis_valid      (pool_out_valid[i]),
//                .m_axis_data       (pool_out_ch[DATA_WIDTH*i +: DATA_WIDTH]), 
//                .m_axis_last       (pool_out_last[i])
//            );
//        end
//    endgenerate

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_conv2_pooling2
// ============================================================================

module top_conv2_pooling2 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 13,
    parameter IMG_HEIGHT  = 13,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 6,  
    parameter C_OUT       = 16  
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire frame_clear,
    
    // Interface Stream 48-bit
    input  wire pixel_valid,
    input  wire signed [DATA_WIDTH*C_IN-1:0] pixel_in,
    
    // Interface Stream 128-bit
    output wire [C_OUT-1:0] pool_out_valid,
    output wire signed [DATA_WIDTH*C_OUT-1:0] pool_out_ch,
    output wire [C_OUT-1:0] pool_out_last
);

    wire conv2_valid;
    wire conv2_last;
    wire signed [DATA_WIDTH-1:0] conv2_ch [0:C_OUT-1];

    top_conv2_ver1 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT)
    ) u_conv2 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .frame_clear     (frame_clear),
        .pixel_valid     (pixel_valid),
        .pixel_in        (pixel_in),

        .conv2_out_valid (conv2_valid),
        .conv2_out_last  (conv2_last),
        
        .conv2_out_ch0   (conv2_ch[0]),  .conv2_out_ch1 (conv2_ch[1]),
        .conv2_out_ch2   (conv2_ch[2]),  .conv2_out_ch3 (conv2_ch[3]),
        .conv2_out_ch4   (conv2_ch[4]),  .conv2_out_ch5 (conv2_ch[5]),
        .conv2_out_ch6   (conv2_ch[6]),  .conv2_out_ch7 (conv2_ch[7]),
        .conv2_out_ch8   (conv2_ch[8]),  .conv2_out_ch9 (conv2_ch[9]),
        .conv2_out_ch10  (conv2_ch[10]), .conv2_out_ch11(conv2_ch[11]),
        .conv2_out_ch12  (conv2_ch[12]), .conv2_out_ch13(conv2_ch[13]),
        .conv2_out_ch14  (conv2_ch[14]), .conv2_out_ch15(conv2_ch[15]),
        .conv2_done      ()
    );

    genvar i;
    generate
        for (i = 0; i < C_OUT; i = i + 1) begin : gen_pool2_array
            pool_top #(
                .DATA_WIDTH (DATA_WIDTH),
                .IMG_WIDTH  (11), 
                .IMG_HEIGHT (11),
                .KERNEL_SIZE(2), 
                .STRIDE     (2), 
                .C_OUT      (1)  
            ) u_pool2_inst (
                .clk                (clk),
                .rst_n              (rst_n),
                .pool_start         (start),
                .pool_ready         (),
                .pool_channel_done  (),
                .pool_frame_done    (),

                .s_axis_valid      (conv2_valid),
                .s_axis_data       (conv2_ch[i]),
                .s_axis_ready      (),

                .m_axis_valid      (pool_out_valid[i]),
                .m_axis_data       (pool_out_ch[DATA_WIDTH*i +: DATA_WIDTH]), 
                .m_axis_last       (pool_out_last[i])
            );
        end
    endgenerate

endmodule