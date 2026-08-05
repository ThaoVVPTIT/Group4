`timescale 1ns / 1ps

// ============================================================================
// MODULE: tb_top_conv_feature_extractor
// Ch?c n?ng: Full Logging & Quantization Visualizer n?p file .MEM chu?n ???ng d?n
// Th? m?c  : E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/
// ============================================================================

module tb_top_extractor;

    // --- Tham s? mô ph?ng ---
    parameter DATA_WIDTH   = 8;
    parameter C_OUT_POOL1  = 6;
    parameter C_OUT_POOL2  = 16;
    parameter CLK_PERIOD   = 10; // Clock 100MHz (10ns)

    parameter IMG_WIDTH    = 28;
    parameter IMG_HEIGHT   = 28;
    parameter TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 784 pixels

    // --- ???ng d?n tuy?t ??i chu?n xác ??n Folder ch?a file .MEM ---
    localparam HEX_PATH = "E:/2_Intern_PTIT/testbench/4_conv_pool/scheduler.sim/sim_1/behav/xsim/hex/";

    // --- Tín hi?u ?i?u khi?n ---
    reg clk;
    reg rst_n;
    reg pe_compute_en;

    // --- Tín hi?u Stream vào ---
    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    // --- B? nh? ??m l?u d? li?u ?nh 28x28 ---
    reg signed [DATA_WIDTH-1:0] img_mem [0:TOTAL_PIXELS-1];

    // --- Tín hi?u ??u ra t? UUT ---
    wire pe_ready;
    wire pe_done;
    wire [C_OUT_POOL2-1:0] pool2_out_valid;
    wire signed [DATA_WIDTH*C_OUT_POOL2-1:0] pool2_out_ch; // Bus 128-bit
    wire [C_OUT_POOL2-1:0] pool2_out_last;

    // --- Bi?n ??m ph?c v? ki?m th? ---
    integer pixel_idx;
    integer pool1_cnt, pool2_cnt;
    integer timeout_counter;

    // =========================================================
    // 1. KH?I T?O UNIT UNDER TEST (UUT)
    // =========================================================
    top_conv_feature_extractor #(
        .DATA_WIDTH  (DATA_WIDTH),
        .C_OUT_POOL1 (C_OUT_POOL1),
        .C_OUT_POOL2 (C_OUT_POOL2)
    ) uut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .pe_compute_en       (pe_compute_en),
        .pe_ready            (pe_ready),
        .pe_done             (pe_done),
        .pixel_valid         (pixel_valid),
        .pixel_in            (pixel_in),
        .pool2_out_valid     (pool2_out_valid),
        .pool2_out_ch        (pool2_out_ch),
        .pool2_out_last      (pool2_out_last)
    );

    // =========================================================
    // 2. KH?I T?O XUNG CLOCK (100 MHz)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // =========================================================
    // 3. B??C N?P T?T C? FILE .MEM VÀO TESTBENCH & RTL
    // =========================================================
    initial begin
        #1;
        $display("==========================================================================");
        $display("[MEM LOAD LOG] DANG NAP CAC FILE .MEM TU THU MUC XSIM/HEX...");
        $display("==========================================================================");

        // 3.1. ??c ?nh th? nghi?m (test_image.mem)
        $readmemh({HEX_PATH, "test_image.mem"}, img_mem);
        $display("[FILE OK] test_image.mem -> Loaded 784 pixels.");

        // 3.2. N?p Tham s? Conv1
        // (Chú ý: ??m b?o các bi?n c1_kernel/c1_bias... kh?p v?i tên reg trong Conv1 c?a b?n)
        $readmemh({HEX_PATH, "conv1_kernel.mem"},     uut.u_conv1_pool1.u_conv1.c1_kernel);
        $readmemh({HEX_PATH, "conv1_bias.mem"},       uut.u_conv1_pool1.u_conv1.c1_bias);
        $readmemh({HEX_PATH, "conv1_multiplier.mem"}, uut.u_conv1_pool1.u_conv1.c1_mult);
        $readmemh({HEX_PATH, "conv1_shift.mem"},      uut.u_conv1_pool1.u_conv1.c1_shift);
        $display("[FILE OK] Conv1 .mem Files Loaded Successfully!");

        // 3.3. N?p Tham s? Conv2
        $readmemh({HEX_PATH, "conv2_kernel.mem"},     uut.u_conv2_pool2.u_conv2.c2_kernel);
        $readmemh({HEX_PATH, "conv2_bias.mem"},       uut.u_conv2_pool2.u_conv2.c2_bias);
        $readmemh({HEX_PATH, "conv2_multiplier.mem"}, uut.u_conv2_pool2.u_conv2.c2_mult);
        $readmemh({HEX_PATH, "conv2_shift.mem"},      uut.u_conv2_pool2.u_conv2.c2_shift);
        $display("[FILE OK] Conv2 .mem Files Loaded Successfully!");

        // 3.4. DUMP CÁC THAM S? CONV1 RA LOG ?? D? DÒ S? H?C
        $display("--------------------------------------------------------------------------");
        $display("[PARAM DUMP - CONV1]");
        $display("  -> Bias       (Ch0..5): %d, %d, %d, %d, %d, %d", 
                 $signed(uut.u_conv1_pool1.u_conv1.c1_bias[0]), $signed(uut.u_conv1_pool1.u_conv1.c1_bias[1]),
                 $signed(uut.u_conv1_pool1.u_conv1.c1_bias[2]), $signed(uut.u_conv1_pool1.u_conv1.c1_bias[3]),
                 $signed(uut.u_conv1_pool1.u_conv1.c1_bias[4]), $signed(uut.u_conv1_pool1.u_conv1.c1_bias[5]));
        $display("  -> Multiplier (Ch0..5): %d, %d, %d, %d, %d, %d", 
                 uut.u_conv1_pool1.u_conv1.c1_mult[0], uut.u_conv1_pool1.u_conv1.c1_mult[1],
                 uut.u_conv1_pool1.u_conv1.c1_mult[2], uut.u_conv1_pool1.u_conv1.c1_mult[3],
                 uut.u_conv1_pool1.u_conv1.c1_mult[4], uut.u_conv1_pool1.u_conv1.c1_mult[5]);
        $display("  -> Shift      (Ch0..5): %d, %d, %d, %d, %d, %d", 
                 uut.u_conv1_pool1.u_conv1.c1_shift[0], uut.u_conv1_pool1.u_conv1.c1_shift[1],
                 uut.u_conv1_pool1.u_conv1.c1_shift[2], uut.u_conv1_pool1.u_conv1.c1_shift[3],
                 uut.u_conv1_pool1.u_conv1.c1_shift[4], uut.u_conv1_pool1.u_conv1.c1_shift[5]);
        $display("--------------------------------------------------------------------------");
    end

    // =========================================================
    // 4. MAIN TEST PROCESS (??Y D? LI?U test_image.mem VÀO CONV1)
    // =========================================================
    initial begin
        rst_n           = 1'b0;
        pe_compute_en   = 1'b0;
        pixel_valid     = 1'b0;
        pixel_in        = 8'sd0;
        pixel_idx       = 0;
        pool1_cnt       = 0;
        pool2_cnt       = 0;
        timeout_counter = 0;

        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        $display("[CTRL LOG] [%0t ns] SYSTEM RESET COMPLETED", $time);
        #(CLK_PERIOD * 2);

        pe_compute_en = 1'b1;
        $display("[CTRL LOG] [%0t ns] SCHEDULER TRIGGER -> pe_compute_en = 1", $time);
        
        wait(pe_ready == 1'b1);
        @(posedge clk);
        $display("[CTRL LOG] [%0t ns] COMPUTE ENGINE READY -> pe_ready = 1", $time);

        // N?p 784 Pixels t? file test_image.mem
        for (pixel_idx = 0; pixel_idx < TOTAL_PIXELS; pixel_idx = pixel_idx + 1) begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            pixel_in    <= img_mem[pixel_idx];
            
            if ((pixel_idx + 1) % 112 == 0) begin
                $display("   -> [INPUT LOG] [%0t ns] Streamed %0d/784 pixels from test_image.mem", $time, pixel_idx + 1);
            end
        end

        @(posedge clk);
        pixel_valid <= 1'b0;
        pixel_in    <= 8'sd0;
        $display("[INPUT LOG] [%0t ns] HOAN THANH STREAMING 784 PIXELS!", $time);

        // Ch? PE_DONE hoàn t?t
        while (!pe_done && timeout_counter < 2000000) begin
            @(posedge clk);
            timeout_counter = timeout_counter + 1;
        end

        if (pe_done) begin
            $display("==========================================================================");
            $display("[CTRL LOG] [%0t ns] SUCCESS! PE_DONE DETECTED", $time);
            $display("[SUMMARY LOG] Total Pool2 128-bit Output Vectors: %0d / 25", pool2_cnt);
            $display("[SUMMARY LOG] Total Pool1 48-bit Stream Cycles   : %0d / 169", pool1_cnt);
            $display("==========================================================================");
        end else begin
            $display("==========================================================================");
            $display("[ERROR LOG] TIMEOUT ERROR! pe_done khong nhat len sau %0d chu ky.", timeout_counter);
            $display("==========================================================================");
        end

        #(CLK_PERIOD * 50);
        $finish;
    end

    // =========================================================
    // 5. LOG DETAILED GIÁM SÁT POOL1 (6 CHANNELS S? NGUYÊN DEC)
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && uut.pool1_out_valid) begin
            pool1_cnt <= pool1_cnt + 1;
            $display("   [POOL1->CONV2 Stream #%0d] [%0t ns] Last=%b | Values(Ch0..5): %d, %d, %d, %d, %d, %d", 
                     pool1_cnt + 1, $time, uut.pool1_out_last,
                     $signed(uut.pool1_bus_flattened[7:0]),
                     $signed(uut.pool1_bus_flattened[15:8]),
                     $signed(uut.pool1_bus_flattened[23:16]),
                     $signed(uut.pool1_bus_flattened[31:24]),
                     $signed(uut.pool1_bus_flattened[39:32]),
                     $signed(uut.pool1_bus_flattened[47:40]));
        end
    end

    // =========================================================
    // 6. LOG DETAILED GIÁM SÁT POOL2 (16 CHANNELS S? NGUYÊN DEC)
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && pool2_out_valid[0]) begin
            pool2_cnt <= pool2_cnt + 1;
            $display(">> [POOL2->FC Output #%0d/25] [%0t ns] Last=%b | HEX=0x%h", 
                     pool2_cnt + 1, $time, pool2_out_last[0], pool2_out_ch);
            $display("   ??> Dec Values(Ch0..15): %d, %d, %d, %d, %d, %d, %d, %d | %d, %d, %d, %d, %d, %d, %d, %d",
                     $signed(pool2_out_ch[7:0]),    $signed(pool2_out_ch[15:8]),   $signed(pool2_out_ch[23:16]),  $signed(pool2_out_ch[31:24]),
                     $signed(pool2_out_ch[39:32]),  $signed(pool2_out_ch[47:40]),  $signed(pool2_out_ch[55:48]),  $signed(pool2_out_ch[63:56]),
                     $signed(pool2_out_ch[71:64]),  $signed(pool2_out_ch[79:72]),  $signed(pool2_out_ch[87:80]),  $signed(pool2_out_ch[95:88]),
                     $signed(pool2_out_ch[103:96]), $signed(pool2_out_ch[111:104]),$signed(pool2_out_ch[119:112]),$signed(pool2_out_ch[127:120]));
        end
    end

endmodule