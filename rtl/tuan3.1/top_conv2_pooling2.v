`timescale 1ns / 1ps

// ============================================================================
// MODULE: conv2_pool2_top
// Ch?c n?ng: K?t n?i CONV2 (13x13x6 -> 11x11x16) v?i Array 16 kh?i POOL2 (11x11x16 -> 5x5x16)
// Chu?n   : Verilog-2001 (S? d?ng 1D Bus cho c?ng ngõ ra)
// ============================================================================

module top_conv2_pooling2 #(
    parameter DATA_WIDTH  = 8,
    parameter IMG_WIDTH   = 13, // Kích th??c input vào Conv2: 13x13
    parameter IMG_HEIGHT  = 13,
    parameter KERNEL_SIZE = 3,
    parameter C_IN        = 6,  // 6 Channel ??u vào Conv2
    parameter C_OUT       = 16  // 16 Channel ??u ra Conv2 & Pool2
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire frame_clear,
    
    // Interface Stream ??u vào (13x13x6)
    input  wire pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,
    
    // Interface Stream ??u ra t? Pool2 Array (16 Channel song song, kích th??c 5x5 m?i channel)
    output wire [C_OUT-1:0] pool_out_valid,
    output wire signed [DATA_WIDTH*C_OUT-1:0] pool_out_ch, // Bus g?p 128-bit (16 ch x 8-bit)
    output wire [C_OUT-1:0] pool_out_last
);

    // =========================================================
    // 1. DÂY N?I TÍNH HI?U TRUNG GI N Gi?A CONV2 VÀ POOL2
    // =========================================================
    wire conv2_valid;
    wire conv2_last;
    wire signed [DATA_WIDTH-1:0] conv2_ch [0:C_OUT-1]; // M?ng n?i b? (???c phép trong Verilog)

    // =========================================================
    // 2. KH?I T?O MODULE TOP CONV2
    // =========================================================
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
        
        // N?i t?ng c?ng channel c?a Conv2 vào m?ng dây n?i b?
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

    // =========================================================
    // 3. KH?I T?O M?NG 16 MÔ-?UN POOL_TOP CH?Y SONG SONG
    // =========================================================
    genvar i;
    generate
        for (i = 0; i < C_OUT; i = i + 1) begin : gen_pool2_array
            pool_top #(
                .DATA_WIDTH (DATA_WIDTH),
                .IMG_WIDTH  (11), // Output c?a Conv2 là 11x11
                .IMG_HEIGHT (11),
                .KERNEL_SIZE(2),  // Max-Pooling 2x2
                .STRIDE     (2),  // Stride 2
                .C_OUT      (1)   // M?i instance x? lý ??c l?p 1 channel
            ) u_pool2_inst (
                .clk               (clk),
                .rst_n             (rst_n),
                .pool_start        (start),
                .pool_ready        (),
                .pool_channel_done (),
                .pool_frame_done   (),

                // D? li?u ngõ vào AXI-Stream Slave (L?y t? ngõ ra Conv2)
                .s_axis_valid      (conv2_valid),
                .s_axis_data       (conv2_ch[i]),
                .s_axis_ready      (),

                // D? li?u ngõ ra AXI-Stream Master
                .m_axis_valid      (pool_out_valid[i]),
                // C?t d?i bit t??ng ?ng trên bus 1D: [8*i +: 8]
                .m_axis_data       (pool_out_ch[DATA_WIDTH*i +: DATA_WIDTH]), 
                .m_axis_last       (pool_out_last[i])
            );
        end
    endgenerate

endmodule