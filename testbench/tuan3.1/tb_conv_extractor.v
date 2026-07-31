`timescale 1ns / 1ps

module tb_top_conv_feature_extractor;

    // =========================================================
    // 1. THAM S? C?U HÌNH & KHAI BÁO TÍN HI?U
    // =========================================================
    parameter DATA_WIDTH   = 8;
    parameter C_OUT_POOL2  = 16;
    parameter IMG_W        = 28;
    parameter IMG_H        = 28;
    parameter TOTAL_PIXELS = IMG_W * IMG_H; // 784 pixels

    reg clk;
    reg rst_n;
    reg start;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    wire ready;
    wire feature_extractor_done;

    wire [C_OUT_POOL2-1:0] pool2_out_valid;
    wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch; // Bus 128-bit
    wire [C_OUT_POOL2-1:0] pool2_out_last;

    // M?ng ch?a d? li?u ?nh ??u vào
    reg signed [DATA_WIDTH-1:0] test_image [0:TOTAL_PIXELS-1];

    // =========================================================
    // 2. KH?I T?O CLOCK (100MHz - Period = 10ns)
    // =========================================================
    always #5 clk = ~clk;

    // =========================================================
    // 3. INSTANTIATE MODULE UUT (Direct Feature Extractor)
    // =========================================================
    top_conv_feature_extractor #(
        .DATA_WIDTH  (DATA_WIDTH),
        .C_OUT_POOL2 (C_OUT_POOL2)
    ) uut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .start                  (start),
        .pixel_valid            (pixel_valid),
        .pixel_in               (pixel_in),
        .ready                  (ready),
        .feature_extractor_done (feature_extractor_done),
        .pool2_out_valid        (pool2_out_valid),
        .pool2_out_ch           (pool2_out_ch),
        .pool2_out_last         (pool2_out_last)
    );

    // =========================================================
    // 4. KH?I T?O T? ??NG CÁC THAM S? KERNEL, BIAS, MULT, SHIFT
    //    (GÁN TR?C TI?P TRONG CODE - KHÔNG C?N FILE .HEX)
    // =========================================================
    integer ch, k;

    initial begin
        #1; // ??i 1ns ?? các module con s?n sàng gán giá tr?

        // --- GÁN THAM S? CHO CONV1 (6 Channels) ---
        for (ch = 0; ch < 6; ch = ch + 1) begin
            for (k = 0; k < 9; k = k + 1) begin
                // Gán Kernel Conv1 = 1 (ho?c thay b?ng công th?c tùy ý)
                uut.u_conv1_pool1.u_conv1.c1_kernel[ch*9 + k] = 8'sd1; 
            end
            uut.u_conv1_pool1.u_conv1.c1_bias[ch]       = 32'sd0; // Bias = 0
            uut.u_conv1_pool1.u_conv1.c1_mult[ch]       = 32'sd1; // Multiplier = 1
            uut.u_conv1_pool1.u_conv1.c1_shift[ch]      = 8'd0;   // Shift = 0
        end

        // --- GÁN THAM S? CHO CONV2 (16 Channels) ---
        for (ch = 0; ch < 16; ch = ch + 1) begin
            for (k = 0; k < 54; k = k + 1) begin // 6 channels x 9 = 54
                // Gán Kernel Conv2 = 1
                uut.u_conv2_pool2.u_conv2.c2_kernel[ch*54 + k] = 8'sd1;
            end
            uut.u_conv2_pool2.u_conv2.c2_bias[ch]       = 32'sd0; // Bias = 0
            uut.u_conv2_pool2.u_conv2.c2_mult[ch]       = 32'sd1; // Multiplier = 1
            uut.u_conv2_pool2.u_conv2.c2_shift[ch]      = 8'd0;   // Shift = 0
        end

        $display("[TB INIT] Da khoi tao xong toàn bo Parameter Kernel, Bias, Multiplier, Shift!");
    end

    // =========================================================
    // 5. MAIN TEST SEQUENCE
    // =========================================================
    integer i;

    initial begin
        // Kh?i t?o tr?ng thái ban ??u
        clk         = 0;
        rst_n       = 0;
        start       = 0;
        pixel_valid = 0;
        pixel_in    = 0;

        // T? t?o d? li?u ?nh gi? l?p (pixel_val = 1 ?? d? tính nh?m ki?m tra)
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            test_image[i] = 8'sd1;
        end

        // Gi?i phóng Reset
        #50;
        rst_n = 1;
        #20;

        $display("---------------------------------------------------------");
        $display("[TB DIRECT] STARTING TEST WITH IN-CODE HARDCODED PARAMETERS");
        $display("---------------------------------------------------------");

        // STEP 1: Kích ho?t xung START (1 clock)
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // STEP 2: N?p liên t?c 784 ?i?m ?nh d?ng Streaming (1 pixel / clock)
        $display("[TB DIRECT] Streaming 784 pixels (28x28) into Conv1...");
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            pixel_in    <= test_image[i];
        end

        // T?t pixel_valid sau khi n?p xong
        @(posedge clk);
        pixel_valid <= 1'b0;
        pixel_in    <= 0;
        $display("[TB DIRECT] Done streaming input image!");

        // STEP 3: Ch? cho t?i khi c? feature_extractor_done nh?y lên 1
        $display("[TB DIRECT] Waiting for feature_extractor_done signal...");
        wait (feature_extractor_done == 1'b1);

        $display("---------------------------------------------------------");
        $display("[TB DIRECT] SUCCESS! Feature Extractor DONE!");
        $display("---------------------------------------------------------");

        #100;
        $finish;
    end

    // =========================================================
    // 6. MONITOR K?T QU? ??U RA KHI CÓ POOL2 VALID
    // =========================================================
    always @(posedge clk) begin
        if (pool2_out_valid[0]) begin
            $display("[OUTPUT @ %0tns] Pool2 Out 128-bit Bus = 0x%032X", $time, pool2_out_ch);
            $display("  -> Ch0=%d, Ch1=%d, Ch2=%d, Ch3=%d, Ch4=%d, Ch5=%d, Ch6=%d, Ch7=%d",
                     $signed(pool2_out_ch[7:0]),   $signed(pool2_out_ch[15:8]), 
                     $signed(pool2_out_ch[23:16]), $signed(pool2_out_ch[31:24]),
                     $signed(pool2_out_ch[39:32]), $signed(pool2_out_ch[47:40]), 
                     $signed(pool2_out_ch[55:48]), $signed(pool2_out_ch[63:56]));
            $display("  -> Ch8=%d, Ch9=%d, Ch10=%d, Ch11=%d, Ch12=%d, Ch13=%d, Ch14=%d, Ch15=%d",
                     $signed(pool2_out_ch[71:64]),  $signed(pool2_out_ch[79:72]), 
                     $signed(pool2_out_ch[87:80]),  $signed(pool2_out_ch[95:88]),
                     $signed(pool2_out_ch[103:96]), $signed(pool2_out_ch[111:104]), 
                     $signed(pool2_out_ch[119:112]),$signed(pool2_out_ch[127:120]));
        end
    end

endmodule