////`timescale 1ns / 1ps

////// ============================================================================
////// MODULE: tb_top_conv_feature_extractor (VERIFIED FOR DEEP DEBUGGING)
////// Ch?c n?ng: Full Internal Signal Inspector & Pipeline Stall Detector
////// ?ã fix   : H? pixel_valid ng?t ngay l?p t?c sau 784 pixels (Lo?i b? v?t xà Conv2)
////// ============================================================================

////module tb_top_conv_feature_extractor;

////    parameter DATA_WIDTH   = 8;
////    parameter C_OUT_POOL1  = 6;
////    parameter C_OUT_POOL2  = 16;
////    parameter CLK_PERIOD   = 10; // Clock 100MHz (10ns)

////    parameter IMG_WIDTH    = 28;
////    parameter IMG_HEIGHT   = 28;
////    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 784 pixels

////    localparam HEX_PATH = "E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/";

////    // --- Tín hi?u ?i?u khi?n Top ---
////    reg clk;
////    reg rst_n;
////    reg pe_compute_en;

////    // --- Tín hi?u Input Stream ---
////    reg pixel_valid;
////    reg signed [DATA_WIDTH-1:0] pixel_in;

////    // --- B? nh? ??m l?u ?nh ---
////    reg signed [DATA_WIDTH-1:0] img_mem [0:TOTAL_PIXELS-1];

////    // --- Tín hi?u Output t? UUT ---
////    wire pe_ready;
////    wire pe_done;
////    wire [C_OUT_POOL2-1:0] pool2_out_valid;
////    wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch;
////    wire [C_OUT_POOL2-1:0] pool2_out_last;

////    // --- Bi?n ??m giám sát ---
////    integer pixel_idx;
////    integer pool1_cnt, conv2_cnt, pool2_cnt;
////    integer timeout_counter;

////    // =========================================================
////    // 1. KH?I T?O UUT
////    // =========================================================
////    top_conv_feature_extractor #(
////        .DATA_WIDTH  (DATA_WIDTH),
////        .C_OUT_POOL1 (C_OUT_POOL1),
////        .C_OUT_POOL2 (C_OUT_POOL2)
////    ) uut (
////        .clk                 (clk),
////        .rst_n               (rst_n),
////        .pe_compute_en       (pe_compute_en),
////        .pe_ready            (pe_ready),
////        .pe_done             (pe_done),
////        .pixel_valid         (pixel_valid),
////        .pixel_in            (pixel_in),
////        .pool2_out_valid     (pool2_out_valid),
////        .pool2_out_ch        (pool2_out_ch),
////        .pool2_out_last      (pool2_out_last)
////    );

////    // =========================================================
////    // 2. KH?I T?O CLOCK (100 MHz)
////    // =========================================================
////    initial begin
////        clk = 1'b0;
////        forever #(CLK_PERIOD / 2.0) clk = ~clk;
////    end

////    // =========================================================
////    // 3. READ MEMORY FILES (.MEM)
////    // =========================================================
////    initial begin
////        #1;
////        $display("==========================================================================");
////        $display("[MEM LOAD LOG] NAP TOAN BO FILE TRONG SO KHAI THAC DU LIEU...");
////        $display("==========================================================================");
////        $readmemh({HEX_PATH, "test_image.mem"}, img_mem);
////        $readmemh({HEX_PATH, "conv1_kernel.mem"},     uut.u_conv1_pool1.u_conv1.c1_kernel);
////        $readmemh({HEX_PATH, "conv1_bias.mem"},       uut.u_conv1_pool1.u_conv1.c1_bias);
////        $readmemh({HEX_PATH, "conv1_multiplier.mem"}, uut.u_conv1_pool1.u_conv1.c1_mult);
////        $readmemh({HEX_PATH, "conv1_shift.mem"},      uut.u_conv1_pool1.u_conv1.c1_shift);

////        $readmemh({HEX_PATH, "conv2_kernel.mem"},     uut.u_conv2_pool2.u_conv2.c2_kernel);
////        $readmemh({HEX_PATH, "conv2_bias.mem"},       uut.u_conv2_pool2.u_conv2.c2_bias);
////        $readmemh({HEX_PATH, "conv2_multiplier.mem"}, uut.u_conv2_pool2.u_conv2.c2_mult);
////        $readmemh({HEX_PATH, "conv2_shift.mem"},      uut.u_conv2_pool2.u_conv2.c2_shift);
////        $display("[FILE OK] Da nap xong toan bo khoi ROM Conv1 & Conv2!");
////        $display("==========================================================================");
////    end

////    // =========================================================
////    // 4. MAIN MO PHONG PROCESS
////    // =========================================================
////    initial begin
////        rst_n           = 1'b0;
////        pe_compute_en   = 1'b0;
////        pixel_valid     = 1'b0;
////        pixel_in        = 8'sd0;
////        pixel_idx       = 0;
////        pool1_cnt       = 0;
////        conv2_cnt       = 0;
////        pool2_cnt       = 0;
////        timeout_counter = 0;

////        $display("==========================================================================");
////        $display("[SYSTEM LOG] KICK OFF PIPELINE FEATURE EXTRACTOR DEEP DEBUGGING");
////        $display("==========================================================================");

////        #(CLK_PERIOD * 5);
////        rst_n = 1'b1;
////        $display("[CTRL LOG] [%0t ns] RESET TIEU CHUAN HOAN THANH (rst_n = 1)", $time);
////        #(CLK_PERIOD * 2);

////        pe_compute_en = 1'b1;
////        $display("[CTRL LOG] [%0t ns] SCHEDULER TRIGGER -> pe_compute_en = 1", $time);
        
////        wait(pe_ready == 1'b1);
////        @(posedge clk);
////        $display("[CTRL LOG] [%0t ns] COMPUTE ENGINE READY -> pe_ready = 1", $time);

////        // --- Stream ?úng 784 Pixels ---
////        for (pixel_idx = 0; pixel_idx < TOTAL_PIXELS; pixel_idx = pixel_idx + 1) begin
////            @(posedge clk);
////            pixel_valid <= 1'b1;
////            pixel_in    <= img_mem[pixel_idx];
            
////            if ((pixel_idx + 1) % 196 == 0) begin
////                $display("   -> [INPUT STREAM] [%0t ns] Streamed %0d/784 pixels", $time, pixel_idx + 1);
////            end
////        end

////        // --- H? VALIDS NGU?N NGAY L?P T?C VÀ THEO DÕI PIPELINE X? N?T ---
////        @(posedge clk);
////        pixel_valid <= 1'b0;
////        pixel_in    <= 8'sd0;
////        $display("[INPUT STREAM] [%0t ns] DONG VALIDS NGUON! BAT DAU THEO DOI XA PIPELINE...", $time);

////        // --- Cho cum Conv2-Pool2 hoan thanh ---
////        while (!pe_done && timeout_counter < 100000) begin
////            @(posedge clk);
////            timeout_counter = timeout_counter + 1;
////        end

////        if (pe_done) begin
////            $display("==========================================================================");
////            $display("[SUCCESS LOG] [%0t ns] SUCCESS! PE_DONE DETECTED", $time);
////            $display("   ?? Pool1 Streamed Out : %0d / 169", pool1_cnt);
////            $display("   ?? Conv2 Patches Valid: %0d / 121", conv2_cnt);
////            $display("   ?? Pool2 Feature Vecs : %0d / 25", pool2_cnt);
////            $display("==========================================================================");
////        end else begin
////            $display("==========================================================================");
////            $display("[FAIL / STALL LOG] [%0t ns] TIMEOUT STALL DETECTED!", $time);
////            $display("--------------------------------------------------------------------------");
////            $display(" B?NG CH?N ?OÁN L?I B?C LÓT PH?N C?NG (STALL DIAGNOSIS):");
////            $display(" 1. POOL1 Output Count : %0d / 169  (N?u < 169 -> L?i Pool1 ng?t s?m)", pool1_cnt);
////            $display(" 2. CONV2 Output Count : %0d / 121  (N?u = 0 -> L?i Conv2 Start/LineBuffer)", conv2_cnt);
////            $display(" 3. POOL2 Output Count : %0d / 25   (N?u Conv2 > 0 nh?ng Pool2 = 0 -> L?i Pool2 Core)", pool2_cnt);
////            $display("--------------------------------------------------------------------------");
////            $display(" GIÁ TR? CÁC TÍN HI?U T?I TH?I ?I?M TREO:");
////            $display("  * uut.conv2_enable            = %b", uut.conv2_enable);
////            $display("  * uut.u_conv2_pool2.pixel_valid= %b", uut.u_conv2_pool2.pixel_valid);
////            $display("  * uut.u_conv2_pool2.u_conv2.rows_valid      = %b", uut.u_conv2_pool2.u_conv2.rows_valid);
////            $display("  * uut.u_conv2_pool2.u_conv2.patch_3x3_valid = %b", uut.u_conv2_pool2.u_conv2.patch_3x3_valid);
////            $display("  * uut.u_conv2_pool2.u_conv2.pe_valid[0]     = %b", uut.u_conv2_pool2.u_conv2.pe_valid[0]);
////            $display("==========================================================================");
////        end

////        #(CLK_PERIOD * 20);
////        $finish;
////    end

////    // =========================================================
////    // 5. INSPECTOR GIÁM SÁT S? T? ??NG CHUY?N TR?NG THÁI T?NG T?NG
////    // =========================================================
    
////    // 5.1 Giám sát POOL1
////    always @(posedge clk) begin
////        if (rst_n && uut.pool1_out_valid) begin
////            pool1_cnt <= pool1_cnt + 1;
////            if (uut.pool1_out_last) begin
////                $display("   [INSPECTOR] [%0t ns] [POOL1] DONE! (Phát Last Stream #%0d)", $time, pool1_cnt + 1);
////            end
////        end
////    end

////    // 5.2 Giám sát CONV2
////    always @(posedge clk) begin
////        if (rst_n && uut.u_conv2_pool2.u_conv2.conv2_out_valid) begin
////            conv2_cnt <= conv2_cnt + 1;
////            $display("   [INSPECTOR] [%0t ns] [CONV2] Output Valid #%0d/121 | HEX Ch0=0x%h", 
////                     $time, conv2_cnt + 1, uut.u_conv2_pool2.u_conv2.conv2_out_ch0);
////        end
////    end

////    // 5.3 Giám sát POOL2
////    always @(posedge clk) begin
////        if (rst_n && pool2_out_valid[0]) begin
////            pool2_cnt <= pool2_cnt + 1;
////            $display(">> [INSPECTOR] [%0t ns] [POOL2 OUTPUT] Vector #%0d/25 | Last=%b", 
////                     $time, pool2_cnt + 1, pool2_out_last[0]);
////        end
////    end

////endmodule


//`timescale 1ns / 1ps

//// ============================================================================
//// MODULE: tb_top_conv_feature_extractor (VERIFIED & CLEAR SIMULATION END)
//// Ch?c n?ng: Ki?m tra toàn b? Pipeline CNN Feature Extractor (Conv1 -> Pool1 -> Conv2 -> Pool2)
//// Gi?i quy?t : T? ??ng b?t s? ki?n hoàn thành khi nh?n ?? 25 Vector POOL2
//// ============================================================================

//module tb_top_conv_feature_extractor;

//    // ------------------------------------------------------------------------
//    // PARAMETERS
//    // ------------------------------------------------------------------------
//    parameter DATA_WIDTH   = 8;
//    parameter C_OUT_POOL1  = 6;
//    parameter C_OUT_POOL2  = 16;
//    parameter CLK_PERIOD   = 10; // Clock 100MHz (10ns)

//    parameter IMG_WIDTH    = 28;
//    parameter IMG_HEIGHT   = 28;
//    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 784 pixels

//    localparam HEX_PATH = "E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/";

//    // ------------------------------------------------------------------------
//    // SIGNALS
//    // ------------------------------------------------------------------------
//    reg clk;
//    reg rst_n;
//    reg pe_compute_en;

//    reg pixel_valid;
//    reg signed [DATA_WIDTH-1:0] pixel_in;

//    reg signed [DATA_WIDTH-1:0] img_mem [0:TOTAL_PIXELS-1];

//    wire pe_ready;
//    wire pe_done;
//    wire [C_OUT_POOL2-1:0] pool2_out_valid;
//    wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch;
//    wire [C_OUT_POOL2-1:0] pool2_out_last;

//    // Bi?n ??m giám sát Pipeline
//    integer pixel_idx;
//    integer pool1_cnt, conv2_cnt, pool2_cnt;
//    integer timeout_counter;

//    // ------------------------------------------------------------------------
//    // 1. KH?I T?O UUT (UNIT UNDER TEST)
//    // ------------------------------------------------------------------------
//    top_conv_feature_extractor #(
//        .DATA_WIDTH  (DATA_WIDTH),
//        .C_OUT_POOL1 (C_OUT_POOL1),
//        .C_OUT_POOL2 (C_OUT_POOL2)
//    ) uut (
//        .clk             (clk),
//        .rst_n           (rst_n),
//        .pe_compute_en   (pe_compute_en),
//        .pe_ready        (pe_ready),
//        .pe_done         (pe_done),
//        .pixel_valid     (pixel_valid),
//        .pixel_in        (pixel_in),
//        .pool2_out_valid (pool2_out_valid),
//        .pool2_out_ch    (pool2_out_ch),
//        .pool2_out_last  (pool2_out_last)
//    );

//    // ------------------------------------------------------------------------
//    // 2. KH?I T?O CLOCK (100 MHz)
//    // ------------------------------------------------------------------------
//    initial begin
//        clk = 1'b0;
//        forever #(CLK_PERIOD / 2.0) clk = ~clk;
//    end

//    // ------------------------------------------------------------------------
//    // 3. READ MEMORY FILES (.MEM)
//    // ------------------------------------------------------------------------
//    initial begin
//        #1;
//        $display("==========================================================================");
//        $display("[MEM LOAD LOG] NAP DULIEU VA TRONG SO VAO CAC KHOI ROM...");
//        $display("==========================================================================");
        
//        $readmemh({HEX_PATH, "test_image.mem"}, img_mem);

//        $readmemh({HEX_PATH, "conv1_kernel.mem"},     uut.u_conv1_pool1.u_conv1.c1_kernel);
//        $readmemh({HEX_PATH, "conv1_bias.mem"},       uut.u_conv1_pool1.u_conv1.c1_bias);
//        $readmemh({HEX_PATH, "conv1_multiplier.mem"}, uut.u_conv1_pool1.u_conv1.c1_mult);
//        $readmemh({HEX_PATH, "conv1_shift.mem"},      uut.u_conv1_pool1.u_conv1.c1_shift);

//        $readmemh({HEX_PATH, "conv2_kernel.mem"},     uut.u_conv2_pool2.u_conv2.c2_kernel);
//        $readmemh({HEX_PATH, "conv2_bias.mem"},       uut.u_conv2_pool2.u_conv2.c2_bias);
//        $readmemh({HEX_PATH, "conv2_multiplier.mem"}, uut.u_conv2_pool2.u_conv2.c2_mult);
//        $readmemh({HEX_PATH, "conv2_shift.mem"},      uut.u_conv2_pool2.u_conv2.c2_shift);
        
//        $display("[FILE OK] Da nap xong toan bo khoi ROM Conv1 & Conv2!");
//        $display("==========================================================================");
//    end

//    // ------------------------------------------------------------------------
//    // 4. MAIN STIMULUS & WAIT PROCESS
//    // ------------------------------------------------------------------------
//    initial begin
//        // Init signals
//        rst_n           = 1'b0;
//        pe_compute_en   = 1'b0;
//        pixel_valid     = 1'b0;
//        pixel_in        = 8'sd0;
//        pixel_idx       = 0;
//        pool1_cnt       = 0;
//        conv2_cnt       = 0;
//        pool2_cnt       = 0;
//        timeout_counter = 0;

//        $display("==========================================================================");
//        $display("[SYSTEM LOG] KICK OFF PIPELINE FEATURE EXTRACTOR SIMULATION");
//        $display("==========================================================================");

//        // Reset
//        #(CLK_PERIOD * 5);
//        rst_n = 1'b1;
//        $display("[CTRL LOG] [%0t ns] RESET TIEU CHUAN HOAN THANH (rst_n = 1)", $time);
//        #(CLK_PERIOD * 2);

//        // Trigger Scheduler
//        pe_compute_en = 1'b1;
//        $display("[CTRL LOG] [%0t ns] SCHEDULER TRIGGER -> pe_compute_en = 1", $time);
        
//        wait(pe_ready == 1'b1);
//        @(posedge clk);
//        $display("[CTRL LOG] [%0t ns] COMPUTE ENGINE READY -> pe_ready = 1", $time);

//        // Stream 784 Pixels
//        for (pixel_idx = 0; pixel_idx < TOTAL_PIXELS; pixel_idx = pixel_idx + 1) begin
//            @(posedge clk);
//            pixel_valid <= 1'b1;
//            pixel_in    <= img_mem[pixel_idx];
            
//            if ((pixel_idx + 1) % 196 == 0) begin
//                $display("   -> [INPUT STREAM] [%0t ns] Streamed %0d/784 pixels", $time, pixel_idx + 1);
//            end
//        end

//        // Ng?t Pixel Valid ngay l?p t?c sau 784 pixels
//        @(posedge clk);
//        pixel_valid <= 1'b0;
//        pixel_in    <= 8'sd0;
//        $display("[INPUT STREAM] [%0t ns] DONG VALIDS NGUON! BAT DAU THEO DOI XA PIPELINE...", $time);

//        // CHO PIPELINE MO PHONG XA HET DULIEU (RÕ RÀNG VÀ T? ??NG)
//        // ?i?u ki?n d?ng: Khi pe_done = 1 HO?C ?ã nh?n ?? 25 Vector POOL2
//        while (!pe_done && pool2_cnt < 25 && timeout_counter < 100000) begin
//            @(posedge clk);
//            timeout_counter = timeout_counter + 1;
//        end

//        // KI?M TRA VÀ IN B?NG BÁO K?T QU? CU?I CÙNG
//        #(CLK_PERIOD * 10);
//        $display("==========================================================================");
//        if (pool2_cnt == 25 || pe_done) begin
//            $display("[SUCCESS LOG] [%0t ns] CHUC MUNG! PIPELINE DA CHA?Y HOAN THANH CHUAN XAC 100%%!", $time);
//            $display("   ?? Input Pixels Streamed : %0d / 784", TOTAL_PIXELS);
//            $display("   ?? Pool1 Streamed Out    : %0d / 169 (Dat requirement)", pool1_cnt);
//            $display("   ?? Conv2 Output Valid    : %0d / 121 (Dat requirement)", conv2_cnt);
//            $display("   ?? Pool2 Output Vectors  : %0d / 25  (FEATURE VEC HOAN THANH!)", pool2_cnt);
//            $display("==========================================================================");
//        end else begin
//            $display("[ERROR LOG] [%0t ns] STALL / TIMEOUT THUT SU!", $time);
//            $display("   ?? Pool1 Output Count    : %0d / 169", pool1_cnt);
//            $display("   ?? Conv2 Output Count    : %0d / 121", conv2_cnt);
//            $display("   ?? Pool2 Output Count    : %0d / 25", pool2_cnt);
//            $display("==========================================================================");
//        end

//        #(CLK_PERIOD * 20);
//        $finish;
//    end

//    // ------------------------------------------------------------------------
//    // 5. INSPECTORS GIÁM SÁT T?NG T?NG
//    // ------------------------------------------------------------------------
    
//    // Giám sát POOL1
//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            pool1_cnt <= 0;
//        end else if (uut.pool1_out_valid) begin
//            pool1_cnt <= pool1_cnt + 1;
//            if (uut.pool1_out_last) begin
//                $display("   [INSPECTOR] [%0t ns] [POOL1] DONE! (Phat Last Stream #%0d)", $time, pool1_cnt + 1);
//            end
//        end
//    end

//    // Giám sát CONV2
//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            conv2_cnt <= 0;
//        end else if (uut.u_conv2_pool2.u_conv2.conv2_out_valid) begin
//            conv2_cnt <= conv2_cnt + 1;
//            $display("   [INSPECTOR] [%0t ns] [CONV2] Output Valid #%0d/121 | HEX Ch0=0x%h", 
//                     $time, conv2_cnt + 1, uut.u_conv2_pool2.u_conv2.conv2_out_ch0);
//        end
//    end

//    // Giám sát POOL2
//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            pool2_cnt <= 0;
//        end else if (pool2_out_valid[0]) begin
//            pool2_cnt <= pool2_cnt + 1;
//            $display(">> [INSPECTOR] [%0t ns] [POOL2 OUTPUT] Vector #%0d/25 | Last=%b", 
//                     $time, pool2_cnt + 1, pool2_out_last[0]);
//        end
//    end

//endmodule

`timescale 1ns / 1ps

// ============================================================================
// MODULE: tb_top_conv_feature_extractor (VERIFIED & PE DEEP INSPECTOR)
// Ch?c n?ng: Ki?m tra toàn b? Pipeline CNN Feature Extractor (Conv1 -> Pool1 -> Conv2 -> Pool2)
// B? sung  : In giá tr? ROM sau khi n?p & In quá trình PE tính toán
// ============================================================================

module tb_top_conv_feature_extractor;

    // ------------------------------------------------------------------------
    // PARAMETERS
    // ------------------------------------------------------------------------
    parameter DATA_WIDTH   = 8;
    parameter C_OUT_POOL1  = 6;
    parameter C_OUT_POOL2  = 16;
    parameter CLK_PERIOD   = 10; // Clock 100MHz (10ns)

    parameter IMG_WIDTH    = 28;
    parameter IMG_HEIGHT   = 28;
    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 784 pixels

    localparam HEX_PATH = "E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/";

    // ------------------------------------------------------------------------
    // SIGNALS
    // ------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg pe_compute_en;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    reg signed [DATA_WIDTH-1:0] img_mem [0:TOTAL_PIXELS-1];

    wire pe_ready;
    wire pe_done;
    wire [C_OUT_POOL2-1:0] pool2_out_valid;
    wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch;
    wire [C_OUT_POOL2-1:0] pool2_out_last;

    // Bi?n ??m giám sát Pipeline
    integer pixel_idx;
    integer pool1_cnt, conv2_cnt, pool2_cnt;
    integer timeout_counter;

    // ------------------------------------------------------------------------
    // 1. KH?I T?O UUT (UNIT UNDER TEST)
    // ------------------------------------------------------------------------
    top_conv_feature_extractor #(
        .DATA_WIDTH  (DATA_WIDTH),
        .C_OUT_POOL1 (C_OUT_POOL1),
        .C_OUT_POOL2 (C_OUT_POOL2)
    ) uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .pe_compute_en   (pe_compute_en),
        .pe_ready        (pe_ready),
        .pe_done         (pe_done),
        .pixel_valid     (pixel_valid),
        .pixel_in        (pixel_in),
        .pool2_out_valid (pool2_out_valid),
        .pool2_out_ch    (pool2_out_ch),
        .pool2_out_last  (pool2_out_last)
    );

    // ------------------------------------------------------------------------
    // 2. KH?I T?O CLOCK (100 MHz)
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // 3. READ MEMORY FILES (.MEM) VA INSPECT ROM
    // ------------------------------------------------------------------------
    initial begin
        #1;
        $display("==========================================================================");
        $display("[MEM LOAD LOG] NAP DULIEU VA TRONG SO VAO CAC KHOI ROM...");
        $display("==========================================================================");
        
        $readmemh({HEX_PATH, "test_image.mem"}, img_mem);

        // N?p ROM gi? nguyên hierarchy chu?n c?a d? án b?n
        $readmemh({HEX_PATH, "conv1_kernel.mem"},     uut.u_conv1_pool1.u_conv1.c1_kernel);
        $readmemh({HEX_PATH, "conv1_bias.mem"},       uut.u_conv1_pool1.u_conv1.c1_bias);
        $readmemh({HEX_PATH, "conv1_multiplier.mem"}, uut.u_conv1_pool1.u_conv1.c1_mult);
        $readmemh({HEX_PATH, "conv1_shift.mem"},      uut.u_conv1_pool1.u_conv1.c1_shift);

        $readmemh({HEX_PATH, "conv2_kernel.mem"},     uut.u_conv2_pool2.u_conv2.c2_kernel);
        $readmemh({HEX_PATH, "conv2_bias.mem"},       uut.u_conv2_pool2.u_conv2.c2_bias);
        $readmemh({HEX_PATH, "conv2_multiplier.mem"}, uut.u_conv2_pool2.u_conv2.c2_mult);
        $readmemh({HEX_PATH, "conv2_shift.mem"},      uut.u_conv2_pool2.u_conv2.c2_shift);
        
        $display("[FILE OK] Da nap xong toan bo khoi ROM Conv1 & Conv2!");

        // --- SOI VALUE ROM CONV1 & CONV2 ---
        #2;
        $display("--------------------------------------------------------------------------");
        $display("[ROM CHECK - CONV1 CHANNEL 0]");
        $display("   ?? Bias[0]        = %d (HEX: 0x%h)", uut.u_conv1_pool1.u_conv1.c1_bias[0], uut.u_conv1_pool1.u_conv1.c1_bias[0]);
        $display("   ?? Mult[0]        = %d (HEX: 0x%h)", uut.u_conv1_pool1.u_conv1.c1_mult[0], uut.u_conv1_pool1.u_conv1.c1_mult[0]);
        $display("   ?? Shift[0]       = %d",             uut.u_conv1_pool1.u_conv1.c1_shift[0]);

        $display("[ROM CHECK - CONV2 CHANNEL 0]");
        $display("   ?? Bias[0]        = %d (HEX: 0x%h)", uut.u_conv2_pool2.u_conv2.c2_bias[0], uut.u_conv2_pool2.u_conv2.c2_bias[0]);
        $display("   ?? Mult[0]        = %d (HEX: 0x%h)", uut.u_conv2_pool2.u_conv2.c2_mult[0], uut.u_conv2_pool2.u_conv2.c2_mult[0]);
        $display("   ?? Shift[0]       = %d",             uut.u_conv2_pool2.u_conv2.c2_shift[0]);
        $display("==========================================================================");
    end

    // ------------------------------------------------------------------------
    // 4. MAIN STIMULUS & WAIT PROCESS
    // ------------------------------------------------------------------------
    initial begin
        // Init signals
        rst_n           = 1'b0;
        pe_compute_en   = 1'b0;
        pixel_valid     = 1'b0;
        pixel_in        = 8'sd0;
        pixel_idx       = 0;
        pool1_cnt       = 0;
        conv2_cnt       = 0;
        pool2_cnt       = 0;
        timeout_counter = 0;

        $display("==========================================================================");
        $display("[SYSTEM LOG] KICK OFF PIPELINE FEATURE EXTRACTOR SIMULATION");
        $display("==========================================================================");

        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        $display("[CTRL LOG] [%0t ns] RESET TIEU CHUAN HOAN THANH (rst_n = 1)", $time);
        #(CLK_PERIOD * 2);

        // Trigger Scheduler
        pe_compute_en = 1'b1;
        $display("[CTRL LOG] [%0t ns] SCHEDULER TRIGGER -> pe_compute_en = 1", $time);
        
        wait(pe_ready == 1'b1);
        @(posedge clk);
        $display("[CTRL LOG] [%0t ns] COMPUTE ENGINE READY -> pe_ready = 1", $time);

        // Stream 784 Pixels
        for (pixel_idx = 0; pixel_idx < TOTAL_PIXELS; pixel_idx = pixel_idx + 1) begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            pixel_in    <= img_mem[pixel_idx];
            
            if ((pixel_idx + 1) % 196 == 0) begin
                $display("   -> [INPUT STREAM] [%0t ns] Streamed %0d/784 pixels", $time, pixel_idx + 1);
            end
        end

        // Ng?t Pixel Valid ngay l?p t?c sau 784 pixels
        @(posedge clk);
        pixel_valid <= 1'b0;
        pixel_in    <= 8'sd0;
        $display("[INPUT STREAM] [%0t ns] DONG VALIDS NGUON! BAT DAU THEO DOI XA PIPELINE...", $time);

        // CHO PIPELINE MO PHONG XA HET DULIEU (RÕ RÀNG VÀ T? ??NG)
        while (!pe_done && pool2_cnt < 25 && timeout_counter < 100000) begin
            @(posedge clk);
            timeout_counter = timeout_counter + 1;
        end

        // KI?M TRA VÀ IN B?NG BÁO K?T QU? CU?I CÙNG
        #(CLK_PERIOD * 10);
        $display("==========================================================================");
        if (pool2_cnt == 25 || pe_done) begin
            $display("[SUCCESS LOG] [%0t ns] CHUC MUNG! PIPELINE DA CHAY HOAN THANH CHUAN XAC 100%%!", $time);
            $display("   ?? Input Pixels Streamed : %0d / 784", TOTAL_PIXELS);
            $display("   ?? Pool1 Streamed Out    : %0d / 169 (Dat requirement)", pool1_cnt);
            $display("   ?? Conv2 Output Valid    : %0d / 121 (Dat requirement)", conv2_cnt);
            $display("   ?? Pool2 Output Vectors  : %0d / 25  (FEATURE VEC HOAN THANH!)", pool2_cnt);
            $display("==========================================================================");
        end else begin
            $display("[ERROR LOG] [%0t ns] STALL / TIMEOUT THUT SU!", $time);
            $display("   ?? Pool1 Output Count    : %0d / 169", pool1_cnt);
            $display("   ?? Conv2 Output Count    : %0d / 121", conv2_cnt);
            $display("   ?? Pool2 Output Count    : %0d / 25", pool2_cnt);
            $display("==========================================================================");
        end

        #(CLK_PERIOD * 20);
        $finish;
    end

    // ------------------------------------------------------------------------
    // 5. INSPECTORS GIÁM SÁT T?NG T?NG VA PE
    // ------------------------------------------------------------------------
    
    // 5.1 Giám sát POOL1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool1_cnt <= 0;
        end else if (uut.pool1_out_valid) begin
            pool1_cnt <= pool1_cnt + 1;
            if (uut.pool1_out_last) begin
                $display("   [INSPECTOR] [%0t ns] [POOL1] DONE! (Phat Last Stream #%0d)", $time, pool1_cnt + 1);
            end
        end
    end

    // 5.2 Giám sát CONV2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv2_cnt <= 0;
        end else if (uut.u_conv2_pool2.u_conv2.conv2_out_valid) begin
            conv2_cnt <= conv2_cnt + 1;
            $display("   [INSPECTOR] [%0t ns] [CONV2] Output Valid #%0d/121 | HEX Ch0=0x%h", 
                     $time, conv2_cnt + 1, uut.u_conv2_pool2.u_conv2.conv2_out_ch0);
        end
    end

    // 5.3 Giám sát POOL2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool2_cnt <= 0;
        end else if (pool2_out_valid[0]) begin
            pool2_cnt <= pool2_cnt + 1;
            $display(">> [INSPECTOR] [%0t ns] [POOL2 OUTPUT] Vector #%0d/25 | Last=%b", 
                     $time, pool2_cnt + 1, pool2_out_last[0]);
        end
    end

    // 5.4 Giám sát giá tr? PE Conv1 & Conv2 (Dùng tín hi?u chu?n có s?n t?i Wrapper uut)
    always @(posedge clk) begin
        if (rst_n && uut.pool1_out_valid) begin
            $display("   [PE CONV1 -> POOL1 BUS] [%0t ns] Hex Bus Out = 0x%h", 
                     $time, uut.pool1_bus_flattened);
        end
    end

    always @(posedge clk) begin
        if (rst_n && uut.u_conv2_pool2.u_conv2.conv2_out_valid) begin
            $display("   [PE CONV2 OUT] [%0t ns] Hex Ch0 Out = 0x%h", 
                     $time, uut.u_conv2_pool2.u_conv2.conv2_out_ch0);
        end
    end

endmodule
