////`timescale 1ns / 1ps

////// ============================================================================
////// TESTBENCH: tb_conv1_top_ver1
////// Chu?n: Verilog-2001 Pure (?ã b? sung 1-clock flush x? Patch 15 cu?i cùng)
////// ============================================================================

////module tb_conv1_top_ver1;

////    // =========================================================
////    // 1. PARAMETERS
////    // =========================================================
////    parameter DATA_WIDTH  = 8;
////    parameter IMG_WIDTH   = 6;  // Kích th??c test nhanh 6x6
////    parameter IMG_HEIGHT  = 6;
////    parameter KERNEL_SIZE = 3;
////    parameter C_IN        = 1;
////    parameter C_OUT       = 6;

////    localparam OUTPUT_WIDTH  = IMG_WIDTH  - KERNEL_SIZE + 1; // 4
////    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1; // 4

////    localparam PATCH_COUNT = OUTPUT_WIDTH * OUTPUT_HEIGHT;   // 16
////    localparam OUTPUT_SIZE  = C_OUT * PATCH_COUNT;           // 96

////    localparam OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE);

////    // =========================================================
////    // 2. SIGNALS
////    // =========================================================
////    reg clk;
////    reg rst_n;
////    reg start;

////    wire ready;
////    wire done;

////    reg pixel_valid;
////    reg signed [DATA_WIDTH-1:0] pixel_in;

////    reg [OUTPUT_ADDR_WIDTH-1:0] out_rd_addr;
////    wire signed [DATA_WIDTH-1:0] out_rd_data;

////    // =========================================================
////    // 3. DUT INSTANTIATION
////    // =========================================================
////    conv1_top_ver1 #(
////        .DATA_WIDTH  (DATA_WIDTH),
////        .IMG_WIDTH   (IMG_WIDTH),
////        .IMG_HEIGHT  (IMG_HEIGHT),
////        .KERNEL_SIZE (KERNEL_SIZE),
////        .C_IN        (C_IN),
////        .C_OUT       (C_OUT)
////    ) u_dut (
////        .clk         (clk),
////        .rst_n       (rst_n),

////        .start       (start),
////        .ready       (ready),
////        .done        (done),

////        .pixel_valid (pixel_valid),
////        .pixel_in    (pixel_in),

////        .out_rd_addr (out_rd_addr),
////        .out_rd_data (out_rd_data)
////    );

////    // =========================================================
////    // 4. CLOCK GENERATOR (10ns = 100MHz)
////    // =========================================================
////    initial begin
////        clk = 1'b0;
////        forever #5 clk = ~clk;
////    end

////    // =========================================================
////    // 5. LOAD TEST WEIGHTS (M?u m?c ??nh khi ch?a n?p HEX)
////    // =========================================================
////    integer i_w;

////    initial begin
////        for (i_w = 0; i_w < C_OUT * 9; i_w = i_w + 1) begin
////            u_dut.c1_kernel[i_w] = 8'sd1;
////        end

////        for (i_w = 0; i_w < C_OUT; i_w = i_w + 1) begin
////            u_dut.c1_bias[i_w]  = 32'sd0;
////            u_dut.c1_mult[i_w]  = 32'sd1;
////            u_dut.c1_shift[i_w] = 8'd0;
////        end
////    end

////    // =========================================================
////    // 6. TASK: START FRAME
////    // =========================================================
////    task trigger_start;
////        begin
////            $display("\n==============================================");
////            $display("[%0t ns] START FRAME", $time);
////            $display("==============================================");

////            // ??t start tr??c c?nh lên (? negedge)
////            @(negedge clk);
////            start = 1'b1;

////            // DUT nh?n start ? posedge
////            @(posedge clk);

////            // H? start ? negedge
////            @(negedge clk);
////            start = 1'b0;

////            // Ch? 1 clock cho frame_clear k?t thúc
////            @(posedge clk);
////        end
////    endtask

////    // =========================================================
////    // 7. TASK: SEND IMAGE STREAM
////    // =========================================================
////    task send_full_image;
////        integer r;
////        integer c;
////        integer pixel_value;

////        begin
////            $display("\n---- STREAMING %0dx%0d IMAGE ----", IMG_WIDTH, IMG_HEIGHT);

////            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
////                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
////                    pixel_value = r * IMG_WIDTH + c + 1;

////                    // ??t d? li?u t?i negedge clk
////                    @(negedge clk);
////                    pixel_valid = 1'b1;
////                    pixel_in    = pixel_value;

////                    // DUT nh?n t?i posedge clk
////                    @(posedge clk);

////                    $display("[%0t ns] Pixel[%0d][%0d] = %0d", $time, r, c, pixel_value);
////                end
////            end

                       
////            // -----------------------------------------------------------------
////            // THÊM 2 CLOCKS FLUSH ?? TRÔI H?T LATENCY 2 T?NG PIPELINE
////            // -----------------------------------------------------------------
////            repeat (3) begin
////                @(negedge clk);
////                pixel_valid = 1'b1;
////                pixel_in    = 8'sd0; // Dummy pixel x? n?t pipeline
////                @(posedge clk);
////            end

////            // H? valid hoàn toàn sau khi x? ?? 2 clock
////            @(negedge clk);
////            pixel_valid = 1'b0;
////            pixel_in    = 8'sd0;

////            $display("[%0t ns] FINISHED STREAMING %0d PIXELS", $time, IMG_WIDTH * IMG_HEIGHT);
////        end
////    endtask 

////    // =========================================================
////    // 8. MAIN SIMULATION PROCESS
////    // =========================================================
////    integer rd_idx;
////    integer timeout_cycles;

////    initial begin
////        // -----------------------------------------------------
////        // INITIAL SIGNALS (Tránh sóng ?? XX)
////        // -----------------------------------------------------
////        rst_n          = 1'b0;
////        start          = 1'b0;
////        pixel_valid    = 1'b0;
////        pixel_in       = 8'sd0;
////        out_rd_addr    = {OUTPUT_ADDR_WIDTH{1'b0}};
////        rd_idx         = 0;
////        timeout_cycles = 0;

////        // -----------------------------------------------------
////        // RESET SYSTEM
////        // -----------------------------------------------------
////        #20;
////        rst_n = 1'b1;
////        repeat (3) @(posedge clk);

////        // -----------------------------------------------------
////        // DISPLAY CONFIGURATION
////        // -----------------------------------------------------
////        $display("\n==============================================");
////        $display("          CONV1 TESTBENCH CONFIG");
////        $display("==============================================");
////        $display("Input Image  : %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
////        $display("Kernel       : %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
////        $display("C_IN         : %0d", C_IN);
////        $display("C_OUT        : %0d", C_OUT);
////        $display("Output Map   : %0dx%0d", OUTPUT_WIDTH, OUTPUT_HEIGHT);
////        $display("Patch Count  : %0d", PATCH_COUNT);
////        $display("Output Size  : %0d", OUTPUT_SIZE);
////        $display("==============================================");

////        // -----------------------------------------------------
////        // TRIGGER FRAME & STREAM DATA
////        // -----------------------------------------------------
////        trigger_start();
////        send_full_image();

////        // -----------------------------------------------------
////        // WAIT FOR DONE
////        // -----------------------------------------------------
////        $display("\nWaiting for DONE signal...");

////        timeout_cycles = 0; 

////        while ((done !== 1'b1) && (timeout_cycles < 100000)) begin
////            @(posedge clk);
////            timeout_cycles = timeout_cycles + 1;
////        end

////        if (done === 1'b1) begin
////            $display("\n==============================================");
////            $display("       SUCCESS: DONE RECEIVED AT TIME %0t ns", $time);
////            $display("==============================================");
////        end else begin
////            $display("\n==============================================");
////            $display("       ERROR: TIMEOUT! DONE NOT RECEIVED");
////            $display("==============================================");
////            $finish;
////        end

////        // Ch? 5 nh?p clock ?? BRAM ch?t ghi hoàn toàn Patch 15
////        repeat (5) @(posedge clk);

////        // -----------------------------------------------------
////        // CHECK BRAM CHANNEL 0 (??c ?? 16 Patches: 0 -> 15)
////        // -----------------------------------------------------
////        $display("\n==============================================");
////        $display("       BRAM CHANNEL 0 OUTPUT CHECK");
////        $display("==============================================");

////        for (rd_idx = 0; rd_idx < PATCH_COUNT; rd_idx = rd_idx + 1) begin
////            @(negedge clk);
////            out_rd_addr = rd_idx;

////            @(posedge clk);
////            #1;

////            $display("CH0[%0d] (Addr %0d) = %0d (Hex: 0x%02h)", 
////                     rd_idx, out_rd_addr, out_rd_data, out_rd_data);
////        end

////        // -----------------------------------------------------
////        // FINISH SIMULATION
////        // -----------------------------------------------------
////        #50;
////        $display("\n==============================================");
////        $display("       TESTBENCH FINISHED SUCCESSFULLY");
////        $display("==============================================");
////        $finish;
////    end

////endmodule

//`timescale 1ns / 1ps

//// ============================================================================
//// TESTBENCH: tb_conv1_top_ver1 (B?N CHU?N ?Ã TEST THÀNH CÔNG ?? 16 Patches)
//// ============================================================================

//module tb_conv1_top_ver1;

//    // =========================================================
//    // 1. PARAMETERS
//    // =========================================================
//    parameter DATA_WIDTH  = 8;
//    parameter IMG_WIDTH   = 6;  // Kích th??c test nhanh 6x6
//    parameter IMG_HEIGHT  = 6;
//    parameter KERNEL_SIZE = 3;
//    parameter C_IN        = 1;
//    parameter C_OUT       = 6;

//    localparam OUTPUT_WIDTH  = IMG_WIDTH  - KERNEL_SIZE + 1; // 4
//    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1; // 4

//    localparam PATCH_COUNT = OUTPUT_WIDTH * OUTPUT_HEIGHT;   // 16
//    localparam OUTPUT_SIZE  = C_OUT * PATCH_COUNT;           // 96

//    localparam OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE);

//    // =========================================================
//    // 2. SIGNALS
//    // =========================================================
//    reg clk;
//    reg rst_n;
//    reg start;

//    wire ready;
//    wire done;

//    reg pixel_valid;
//    reg signed [DATA_WIDTH-1:0] pixel_in;

//    reg [OUTPUT_ADDR_WIDTH-1:0] out_rd_addr;
//    wire signed [DATA_WIDTH-1:0] out_rd_data;

//    // =========================================================
//    // 3. DUT INSTANTIATION
//    // =========================================================
//    conv1_top_ver1 #(
//        .DATA_WIDTH  (DATA_WIDTH),
//        .IMG_WIDTH   (IMG_WIDTH),
//        .IMG_HEIGHT  (IMG_HEIGHT),
//        .KERNEL_SIZE (KERNEL_SIZE),
//        .C_IN        (C_IN),
//        .C_OUT       (C_OUT)
//    ) u_dut (
//        .clk         (clk),
//        .rst_n       (rst_n),

//        .start       (start),
//        .ready       (ready),
//        .done        (done),

//        .pixel_valid (pixel_valid),
//        .pixel_in    (pixel_in),

//        .out_rd_addr (out_rd_addr),
//        .out_rd_data (out_rd_data)
//    );

//    // =========================================================
//    // 4. CLOCK GENERATOR (10ns = 100MHz)
//    // =========================================================
//    initial begin
//        clk = 1'b0;
//        forever #5 clk = ~clk;
//    end

//    // =========================================================
//    // 5. LOAD TEST WEIGHTS (M?u m?c ??nh khi ch?a n?p HEX)
//    // =========================================================
//    integer i_w;

//    initial begin
//        for (i_w = 0; i_w < C_OUT * 9; i_w = i_w + 1) begin
//            u_dut.c1_kernel[i_w] = 8'sd1;
//        end

//        for (i_w = 0; i_w < C_OUT; i_w = i_w + 1) begin
//            u_dut.c1_bias[i_w]  = 32'sd0;
//            u_dut.c1_mult[i_w]  = 32'sd1;
//            u_dut.c1_shift[i_w] = 8'd0;
//        end
//    end

//    // =========================================================
//    // 6. TASK: START FRAME
//    // =========================================================
//    task trigger_start;
//        begin
//            $display("\n==============================================");
//            $display("[%0t ns] START FRAME", $time);
//            $display("==============================================");

//            // ??t start tr??c c?nh lên (? negedge)
//            @(negedge clk);
//            start = 1'b1;

//            // DUT nh?n start ? posedge
//            @(posedge clk);

//            // H? start ? negedge
//            @(negedge clk);
//            start = 1'b0;

//            // Ch? 1 clock cho frame_clear k?t thúc
//            @(posedge clk);
//        end
//    endtask

//    // =========================================================
//    // 7. TASK: SEND IMAGE STREAM (Có 3 nh?p flush an toàn cho Latency)
//    // =========================================================
//    task send_full_image;
//        integer r;
//        integer c;
//        integer pixel_value;

//        begin
//            $display("\n---- STREAMING %0dx%0d IMAGE ----", IMG_WIDTH, IMG_HEIGHT);

//            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
//                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
//                    pixel_value = r * IMG_WIDTH + c + 1;

//                    // ??t d? li?u t?i negedge clk
//                    @(negedge clk);
//                    pixel_valid = 1'b1;
//                    pixel_in    = pixel_value;

//                    // DUT nh?n t?i posedge clk
//                    @(posedge clk);

//                    $display("[%0t ns] Pixel[%0d][%0d] = %0d", $time, r, c, pixel_value);
//                end
//            end

//            // -----------------------------------------------------------------
//            // B?M THÊM 3 NH?P FLUSH DUMMY ?? X? H?T 16 PATCHES HOÀN CH?NH
//            // -----------------------------------------------------------------
//            repeat (3) begin
//                @(negedge clk);
//                pixel_valid = 1'b1;
//                pixel_in    = 8'sd0;
//                @(posedge clk);
//            end

//            // H? valid h?n sau khi x? xong
//            @(negedge clk);
//            pixel_valid = 1'b0;
//            pixel_in    = 8'sd0;

//            $display("[%0t ns] FINISHED STREAMING %0d PIXELS", $time, IMG_WIDTH * IMG_HEIGHT);
//        end
//    endtask

//    // =========================================================
//    // 8. MAIN SIMULATION PROCESS (Timing ??ng b? chu?n 100%)
//    // =========================================================
//    integer rd_idx;
//    integer timeout_cycles;

//    initial begin
//        // -----------------------------------------------------
//        // INITIAL SIGNALS
//        // -----------------------------------------------------
//        rst_n          = 1'b0;
//        start          = 1'b0;
//        pixel_valid    = 1'b0;
//        pixel_in       = 8'sd0;
//        out_rd_addr    = {OUTPUT_ADDR_WIDTH{1'b0}};
//        rd_idx         = 0;
//        timeout_cycles = 0;

//        // -----------------------------------------------------
//        // RESET SYSTEM
//        // -----------------------------------------------------
//        #20;
//        rst_n = 1'b1;
//        repeat (1) @(posedge clk);

//        // -----------------------------------------------------
//        // DISPLAY CONFIGURATION
//        // -----------------------------------------------------
//        $display("\n==============================================");
//        $display("          CONV1 TESTBENCH CONFIG");
//        $display("==============================================");
//        $display("Input Image  : %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
//        $display("Kernel       : %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
//        $display("C_IN         : %0d", C_IN);
//        $display("C_OUT        : %0d", C_OUT);
//        $display("Output Map   : %0dx%0d", OUTPUT_WIDTH, OUTPUT_HEIGHT);
//        $display("Patch Count  : %0d", PATCH_COUNT);
//        $display("Output Size  : %0d", OUTPUT_SIZE);
//        $display("==============================================");

//        // -----------------------------------------------------
//        // TRIGGER FRAME & STREAM DATA
//        // -----------------------------------------------------
//        trigger_start();
//        send_full_image();

//        // -----------------------------------------------------
//        // WAIT FOR DONE
//        // -----------------------------------------------------
//        $display("\nWaiting for DONE signal...");

//        timeout_cycles = 0; 

//        while ((done !== 1'b1) && (timeout_cycles < 100000)) begin
//            @(posedge clk);
//            timeout_cycles = timeout_cycles + 1;
//        end

//        if (done === 1'b1) begin
//            $display("\n==============================================");
//            $display("       SUCCESS: DONE RECEIVED AT TIME %0t ns", $time);
//            $display("==============================================");
//        end else begin
//            $display("\n==============================================");
//            $display("       ERROR: TIMEOUT! DONE NOT RECEIVED");
//            $display("==============================================");
//            $finish;
//        end

//        // -----------------------------------------------------
//        // ?? TR? ?N ??NH CH?NG TRÔI TIMING (Ch? BRAM ch?t ghi)
//        // -----------------------------------------------------
//        @(posedge clk);
//        #2;

//        // -----------------------------------------------------
//        // CHECK BRAM CHANNEL 0 (??c tr?n v?n t? Addr 0 -> 15)
//        // -----------------------------------------------------
//        $display("\n==============================================");
//        $display("       BRAM CHANNEL 0 OUTPUT CHECK");
//        $display("==============================================");

//        for (rd_idx = 0; rd_idx < PATCH_COUNT; rd_idx = rd_idx + 1) begin
//            // ??t ??a ch? t?i c?nh xu?ng
//            @(negedge clk);
//            out_rd_addr = rd_idx;

//            // Ch? c?nh lên ?? BRAM tr? d? li?u ra ?n ??nh
//            @(posedge clk);
//            #1;

//            $display("CH0[%0d] (Addr %0d) = %0d (Hex: 0x%02h)", 
//                     rd_idx, out_rd_addr, out_rd_data, out_rd_data);
//        end

//        // -----------------------------------------------------
//        // FINISH SIMULATION
//        // -----------------------------------------------------
//        #50;
//        $display("\n==============================================");
//        $display("       TESTBENCH FINISHED SUCCESSFULLY");
//        $display("==============================================");
//        $finish;
//    end

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_conv1_top_ver1
// Chu?n: ??ng b? hoàn toàn theo S??N LÊN (posedge clk) + Clock-to-Out delay (#1)
// ============================================================================

module tb_conv1_top_ver1;

    // =========================================================
    // 1. PARAMETERS
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter IMG_WIDTH   = 6;  // Kích th??c test nhanh 6x6
    parameter IMG_HEIGHT  = 6;
    parameter KERNEL_SIZE = 3;
    parameter C_IN        = 1;
    parameter C_OUT       = 6;

    localparam OUTPUT_WIDTH  = IMG_WIDTH  - KERNEL_SIZE + 1; // 4
    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1; // 4

    localparam PATCH_COUNT = OUTPUT_WIDTH * OUTPUT_HEIGHT;   // 16
    localparam OUTPUT_SIZE  = C_OUT * PATCH_COUNT;           // 96

    localparam OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE);

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg clk;
    reg rst_n;
    reg start;

    wire ready;
    wire done;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    reg [OUTPUT_ADDR_WIDTH-1:0] out_rd_addr;
    wire signed [DATA_WIDTH-1:0] out_rd_data;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    conv1_top_ver2 #(
        .DATA_WIDTH  (DATA_WIDTH),
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .KERNEL_SIZE (KERNEL_SIZE),
        .C_IN        (C_IN),
        .C_OUT       (C_OUT)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .start       (start),
        .ready       (ready),
        .done        (done),

        .pixel_valid (pixel_valid),
        .pixel_in    (pixel_in),

        .out_rd_addr (out_rd_addr),
        .out_rd_data (out_rd_data)
    );

    // =========================================================
    // 4. CLOCK GENERATOR (10ns = 100MHz)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 5. LOAD TEST WEIGHTS (M?u m?c ??nh khi ch?a n?p HEX)
    // =========================================================
    integer i_w;

    initial begin
        for (i_w = 0; i_w < C_OUT * 9; i_w = i_w + 1) begin
            u_dut.c1_kernel[i_w] = 8'sd1;
        end

        for (i_w = 0; i_w < C_OUT; i_w = i_w + 1) begin
            u_dut.c1_bias[i_w]  = 32'sd0;
            u_dut.c1_mult[i_w]  = 32'sd1;
            u_dut.c1_shift[i_w] = 8'd0;
        end
    end

    // =========================================================
    // 6. TASK: START FRAME (??ng b? posedge clk)
    // =========================================================
    task trigger_start;
        begin
            $display("\n==============================================");
            $display("[%0t ns] START FRAME", $time);
            $display("==============================================");

            // Gán start ??ng b? theo posedge clk
            @(posedge clk);
            start <= 1'b1;

            @(posedge clk);
            start <= 1'b0; // B?t ??u b?m data ngay chu k? k? ti?p, không ch? d?
        end
    endtask

    // =========================================================
    // 7. TASK: SEND IMAGE STREAM (??ng b? posedge clk)
    // =========================================================
    task send_full_image;
        integer r;
        integer c;
        integer pixel_value;

        begin
            $display("\n---- STREAMING %0dx%0d IMAGE ----", IMG_WIDTH, IMG_HEIGHT);

            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    pixel_value = r * IMG_WIDTH + c + 1;

                    // Dùng gán phi tu?n t? (Non-blocking <=) t?i posedge clk
                    // Xóa b? hoàn toàn #1 ?? ???ng sóng gióng th?ng ??ng 100%!
                    @(posedge clk);
                    pixel_valid <= 1'b1;
                    pixel_in    <= pixel_value;

                    $display("[%0t ns] Pixel[%0d][%0d] = %0d", $time, r, c, pixel_value);
                end
            end

            // Flush 3 nh?p dummy
            repeat (3) begin
                @(posedge clk);
                pixel_valid <= 1'b1;
                pixel_in    <= 8'sd0;
            end

            // H? valid h?n
            @(posedge clk);
            pixel_valid <= 1'b0;
            pixel_in    <= 8'sd0;

            $display("[%0t ns] FINISHED STREAMING %0d PIXELS", $time, IMG_WIDTH * IMG_HEIGHT);
        end
    endtask

    // =========================================================
    // 8. MAIN SIMULATION PROCESS
    // =========================================================
    integer rd_idx;
    integer timeout_cycles;

    initial begin
        // -----------------------------------------------------
        // INITIAL SIGNALS
        // -----------------------------------------------------
        rst_n          = 1'b0;
        start          = 1'b0;
        pixel_valid    = 1'b0;
        pixel_in       = 8'sd0;
        out_rd_addr    = {OUTPUT_ADDR_WIDTH{1'b0}};
        rd_idx         = 0;
        timeout_cycles = 0;

        // -----------------------------------------------------
        // RESET SYSTEM
        // -----------------------------------------------------
        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // DISPLAY CONFIGURATION
        // -----------------------------------------------------
        $display("\n==============================================");
        $display("          CONV1 TESTBENCH CONFIG");
        $display("==============================================");
        $display("Input Image  : %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
        $display("Kernel       : %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
        $display("C_IN         : %0d", C_IN);
        $display("C_OUT        : %0d", C_OUT);
        $display("Output Map   : %0dx%0d", OUTPUT_WIDTH, OUTPUT_HEIGHT);
        $display("Patch Count  : %0d", PATCH_COUNT);
        $display("Output Size  : %0d", OUTPUT_SIZE);
        $display("==============================================");

        // -----------------------------------------------------
        // TRIGGER FRAME & STREAM DATA
        // -----------------------------------------------------
        trigger_start();
        send_full_image();

        // -----------------------------------------------------
        // WAIT FOR DONE
        // -----------------------------------------------------
        $display("\nWaiting for DONE signal...");

        timeout_cycles = 0; 

        while ((done !== 1'b1) && (timeout_cycles < 100000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (done === 1'b1) begin
            $display("\n==============================================");
            $display("       SUCCESS: DONE RECEIVED AT TIME %0t ns", $time);
            $display("==============================================");
        end else begin
            $display("\n==============================================");
            $display("       ERROR: TIMEOUT! DONE NOT RECEIVED");
            $display("==============================================");
            $finish;
        end

        // Ch? 2 nh?p clock cho BRAM ?n ??nh
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // CHECK BRAM CHANNEL 0 (X? lý tr? 1-clock Read Latency)
        // -----------------------------------------------------
        $display("\n==============================================");
        $display("       BRAM CHANNEL 0 OUTPUT CHECK");
        $display("==============================================");

        for (rd_idx = 0; rd_idx < PATCH_COUNT; rd_idx = rd_idx + 1) begin
            @(posedge clk);
            out_rd_addr <= rd_idx; // Gán ??ng b? qua <=

            @(posedge clk); // BRAM 1-clock read latency

            $display("CH0[%0d] (Addr %0d) = %0d (Hex: 0x%02h)", 
                     rd_idx, rd_idx, out_rd_data, out_rd_data);
        end

        // -----------------------------------------------------
        // FINISH SIMULATION
        // -----------------------------------------------------
        #50;
        $display("\n==============================================");
        $display("       TESTBENCH FINISHED SUCCESSFULLY");
        $display("==============================================");
        $finish;
    end

endmodule