`timescale 1ns / 1ps

// ============================================================================
// MODULE: top_conv_feature_extractor
// Ch?c n?ng: Ghép toàn b? Feature Extractor CNN (Conv1 -> Pool1 -> Conv2 -> Pool2)
// Input    : Stream Pixel (28x28x1) l?y t? BRAM / LineBuffer
// Output   : Stream Bus 128-bit (16 channels x 8-bit, 5x5) g?i sang FC Engine
// Giao ti?p: T??ng thích hoàn toàn v?i Handshake protocol c?a scheduler.v
// ============================================================================

module top_conv_feature_extractor #(
    parameter DATA_WIDTH  = 8,
    parameter C_OUT_POOL1 = 6,
    parameter C_OUT_POOL2 = 16
)(
    input  wire clk,
    input  wire rst_n,
    
    // --- Giao di?n Control Handshake t? Scheduler ---
    input  wire pe_compute_en,        // Tín hi?u start/enable t? Scheduler (thay cho start l?)
    output wire pe_ready,             // Báo s?n sàng nh?n Patch/Pixel
    output wire pe_done,              // Báo cho Scheduler bi?t ?ã hoàn thành toàn b? Feature Map

    // --- Giao di?n Stream nh?n t? BRAM / Sliding Window ---
    input  wire pixel_valid,
    input  wire signed [DATA_WIDTH-1:0] pixel_in,

    // --- Giao di?n Stream xu?t ra cho FC / BRAM Buffer ---
    output wire [C_OUT_POOL2-1:0] pool2_out_valid,
    output wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch, // Bus 128-bit (16ch x 8bit)
    output wire [C_OUT_POOL2-1:0] pool2_out_last
);

    // =========================================================
    // 1. DÂY TÍN HI?U N?I GI?A CONV1-POOL1 SANG CONV2-POOL2
    // =========================================================
    wire pool1_out_valid;
    wire pool1_out_last;
    wire conv1_done;

    // Bus gom ?? 6 Channels (6 x 8-bit = 48-bit) t? Pool1 truy?n sang Conv2
    wire signed [DATA_WIDTH-1:0] pool1_ch [0:C_OUT_POOL1-1];
    wire signed [DATA_WIDTH*C_OUT_POOL1-1:0] pool1_bus_flattened;

    // Chuy?n m?ng Channel t? Pool1 thành 1 Bus duy nh?t ?? n?i vào Conv2
    generate
        genvar i;
        for (i = 0; i < C_OUT_POOL1; i = i + 1) begin : PACK_POOL1_BUS
            assign pool1_bus_flattened[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH] = pool1_ch[i];
        end
    endgenerate

    // =========================================================
    // 2. KH?I T?O T?NG 1: CONV1 (28x28x1) -> POOL1 (13x13x6)
    // =========================================================
    top_conv1_pooling_ver1 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (28),
        .IMG_HEIGHT (28),
        .KERNEL_SIZE(3),
        .C_IN       (1),
        .C_OUT      (C_OUT_POOL1)
    ) u_conv1_pool1 (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (pe_compute_en),     // Nh?n trigger tr?c ti?p t? Scheduler
        .ready          (pe_ready),          // Báo Ready ra bên ngoài cho Scheduler/Window
        .done           (conv1_done),

        // Stream nh?n t? BRAM / Sliding Window
        .pixel_valid    (pixel_valid),
        .pixel_in       (pixel_in),

        // Stream b?n sang Conv2 (?? 6 channels)
        .pool_out_valid (pool1_out_valid),
        .pool_out_ch0   (pool1_ch[0]),
        .pool_out_ch1   (pool1_ch[1]),
        .pool_out_ch2   (pool1_ch[2]),
        .pool_out_ch3   (pool1_ch[3]),
        .pool_out_ch4   (pool1_ch[4]),
        .pool_out_ch5   (pool1_ch[5]),
        .pool_out_last  (pool1_out_last)
    );

    // =========================================================
    // 3. KH?I T?O T?NG 2: CONV2 (13x13x6) -> POOL2 (5x5x16)
    // =========================================================
    top_conv2_pooling2 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (13),
        .IMG_HEIGHT (13),
        .KERNEL_SIZE(3),
        .C_IN       (C_OUT_POOL1),           // 6 channels
        .C_OUT      (C_OUT_POOL2)            // 16 channels
    ) u_conv2_pool2 (
        .clk            (clk),
        .rst_n          (rst_n),
        // Conv2 t? ??ng ch?y khi Pool1 phát pixel_valid ??u tiên (Streaming)
        .start          (pe_compute_en), 
        .frame_clear    (1'b0),

        // Stream D? LI?U ?? 6 CHANNELS t? Pool1
        .pixel_valid    (pool1_out_valid),
        .pixel_in       (pool1_bus_flattened), // <-- ?Ã S?A: ??a toàn b? 48-bit (6 ch) vào Conv2

        // Output Stream ra cho FC Engine
        .pool_out_valid (pool2_out_valid),
        .pool_out_ch    (pool2_out_ch),
        .pool_out_last  (pool2_out_last)
    );

    // =========================================================
    // 4. TÍN HI?U PH?N H?I PE_DONE CHO SCHEDULER
    // =========================================================
    // Báo pe_done = 1 khi Pool2 phát ra xung last (x? lý xong pixel cu?i cùng)
    assign pe_done = pool2_out_last[0];

endmodule