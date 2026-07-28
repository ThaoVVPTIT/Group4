////`timescale 1ns/1ps

/////*
////================================================================================
////  FULL PIPELINE VISUALIZATION TESTBENCH FOR TOP_SLIDING_WINDOW_VER1
  
////  Tính n?ng ??c bi?t:
////  - S? d?ng Hierarchical Path (u_top.u_line_buffer...) ?? quan sát tr?c ti?p
////    dòng ch?y d? li?u qua t?ng Module 1 -> Module 2 -> Module 3.
////  - T? ??ng th?ng kê & ki?m tra ?? chính xác c?a toàn b? chu?i Pipeline.
////================================================================================
////*/

////module tb_top_sliding_window_ver21;

////    // =========================================================
////    // 1. PARAMETERS (Mô ph?ng 6x6, 6 channels)
////    // =========================================================
////    parameter DATA_WIDTH = 8;
////    parameter IMG_WIDTH  = 6;
////    parameter IMG_HEIGHT = 6;
////    parameter C_IN       = 6;

////    localparam CHAN_WIDTH       = (C_IN <= 1) ? 1 : $clog2(C_IN);
////    localparam EXPECTED_PATCHES = (IMG_WIDTH - 3 + 1) * (IMG_HEIGHT - 3 + 1); // (6-3+1)*(6-3+1) = 16 patches / channel

////    // =========================================================
////    // 2. SIGNALS & TOP INSTANTIATION
////    // =========================================================
////    reg                         clk;
////    reg                         rst_n;
////    reg                         pixel_valid;
////    reg  [DATA_WIDTH-1:0]       pixel_in;

////    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
////    wire                        patch_cin_valid;
////    wire [CHAN_WIDTH-1:0]       channel_idx;
////    wire                        frame_c_done;

////    top_sliding_window_ver1 #(
////        .DATA_WIDTH(DATA_WIDTH),
////        .IMG_WIDTH (IMG_WIDTH),
////        .IMG_HEIGHT(IMG_HEIGHT),
////        .C_IN      (C_IN)
////    ) u_top (
////        .clk             (clk),
////        .rst_n           (rst_n),
////        .pixel_valid     (pixel_valid),
////        .pixel_in        (pixel_in),
////        .patch_cin_data  (patch_cin_data),
////        .patch_cin_valid (patch_cin_valid),
////        .channel_idx     (channel_idx),
////        .frame_c_done    (frame_c_done)
////    );

////    // Clock Generator (10ns)
////    initial begin
////        clk = 1'b0;
////        forever #5 clk = ~clk;
////    end

////    // =========================================================
////    // 3. PIPELINE MONITORING LOGIC (SOI T?NG STAGE M?CH)
////    // =========================================================
    
////    // --- STAGE 1: LINE BUFFER MONITOR ---
////    // Soi kho?nh kh?c Line Buffer tích ?? 3 hàng và phát 3 pixel cùng c?t
////    always @(posedge clk) begin
////        if (rst_n && u_top.rows_valid) begin
////            $display("[TIME %0t ns] [STAGE 1: LINE_BUFFER] ? Channel %0d | Column 3-Pixels Ready: Row0=%02h, Row1=%02h, Row2=%02h", 
////                     $time, channel_idx, u_top.row0_pixel, u_top.row1_pixel, u_top.row2_pixel);
////        end
////    end

////    // --- STAGE 2: WINDOW GENERATOR MONITOR ---
////    // Soi kho?nh kh?c C?a s? tr??t 3x3 ??n kênh hoàn thành 1 Patch 72-bit
////    always @(posedge clk) begin
////        if (rst_n && u_top.patch_3x3_valid) begin
////            $display("   ??? [STAGE 2: WINDOW_GEN] ? Single 3x3 Patch Created for Channel %0d", channel_idx);
////            $display("   ?   | %02h %02h %02h |", u_top.patch_3x3_data[64 +: 8], u_top.patch_3x3_data[56 +: 8], u_top.patch_3x3_data[48 +: 8]);
////            $display("   ?   | %02h %02h %02h |", u_top.patch_3x3_data[40 +: 8], u_top.patch_3x3_data[32 +: 8], u_top.patch_3x3_data[24 +: 8]);
////            $display("   ?   | %02h %02h %02h |", u_top.patch_3x3_data[16 +: 8], u_top.patch_3x3_data[8  +: 8], u_top.patch_3x3_data[0  +: 8]);
////        end
////    end

////    // --- STAGE 3 & TOP: FULL TENSOR 3x3xC_IN OUTPUT MONITOR ---
////    integer total_tensor_cnt;
////    integer c_log;

////    initial total_tensor_cnt = 0;

////    always @(posedge clk) begin
////        if (rst_n && patch_cin_valid) begin
////            total_tensor_cnt = total_tensor_cnt + 1;
////            $display("\n==================================================================================");
////            $display("[TIME %0t ns] ? [STAGE 3: TOP OUTPUT] TENSOR #%0d FULLY PACKED FOR PE ARRAY (3x3x%0d)!", 
////                     $time, total_tensor_cnt, C_IN);
////            $display("==================================================================================");
////            for (c_log = 0; c_log < C_IN; c_log = c_log + 1) begin
////                $display("  --- CHANNEL %0d ---", c_log);
////                $display("  | %02h  %02h  %02h |", 
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*8 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*7 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*6 +: DATA_WIDTH]);
////                $display("  | %02h  %02h  %02h |", 
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*5 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*4 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*3 +: DATA_WIDTH]);
////                $display("  | %02h  %02h  %02h |", 
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*2 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*1 +: DATA_WIDTH],
////                         patch_cin_data[DATA_WIDTH*9*c_log + 0           +: DATA_WIDTH]);
////            end
////            $display("==================================================================================\n");
////        end
////    end

////    // =========================================================
////    // 4. DRIVER TASKS (TIMING T?I ?U C?NH CLOCK)
////    // =========================================================
////    task send_pixel;
////        input integer ch;
////        input integer row;
////        input integer col;
////        begin
////            @(posedge clk);
////            #1; // Offset nh? ?? sóng ??p m?t trên Waveform
////            pixel_valid = 1'b1;
////            pixel_in    = ch * 100 + row * 10 + col;
////        end
////    endtask

////    task send_channel;
////        input integer ch;
////        integer r, c;
////        begin
////            $display("\n----------------------------------------------------------------------------------");
////            $display("---> START STREAMING CHANNEL %0d / %0d <---", ch, C_IN - 1);
////            $display("----------------------------------------------------------------------------------");
////            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
////                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
////                    send_pixel(ch, r, c);
////                end
                
////                // End of Row: Ng?t nh? 1 cycle báo chuy?n hàng
////                @(posedge clk); #1;
////                pixel_valid = 1'b0;
////                pixel_in    = 0;
////            end
////        end
////    endtask

////    // =========================================================
////    // 5. MAIN SIMULATION FLOW & VERIFICATION
////    // =========================================================
////    integer c_idx;

////    initial begin
////        // Signal Init
////        rst_n       = 1'b0;
////        pixel_valid = 1'b0;
////        pixel_in    = 0;

////        #20;
////        rst_n = 1'b1;
////        repeat (2) @(posedge clk);

////        $display("\n################################################################");
////        $display("   START FULL PIPELINE CONVOLUTION SIMULATION");
////        $display("   Image: %0dx%0d | C_IN: %0d | Expected Output Tensors: %0d", 
////                 IMG_WIDTH, IMG_HEIGHT, C_IN, EXPECTED_PATCHES);
////        $display("################################################################\n");

////        // Stream l?n l??t 6 Channels
////        for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
////            send_channel(c_idx);
////        end

////        // Ch? k?t thúc
////        repeat (10) @(posedge clk);

////        // =========================================================
////        // FULL SYSTEM VERIFICATION SUMMARY
////        // =========================================================
////        $display("\n################################################################");
////        $display("                    SIMULATION VERIFICATION REPORT");
////        $display("################################################################");
////        $display(" Expected Tensors Output : %0d", EXPECTED_PATCHES);
////        $display(" Actual Tensors Output   : %0d", total_tensor_cnt);
        
////        if (total_tensor_cnt == EXPECTED_PATCHES) begin
////            $display(" STATUS                  : ? TEST PASSED 100%! All 3 modules worked seamlessly!");
////        end else begin
////            $display(" STATUS                  : ? TEST FAILED! Missing or extra tensors detected.");
////        end
////        $display("################################################################\n");

////        $finish;
////    end

////endmodule

//`timescale 1ns/1ps

//module tb_top_sliding_window_ver21;

//    // =========================================================
//    // 1. PARAMETERS
//    // =========================================================
//    parameter DATA_WIDTH = 8;
//    parameter IMG_WIDTH  = 6;
//    parameter IMG_HEIGHT = 6;
//    parameter C_IN       = 6;

//    localparam CHAN_WIDTH       = (C_IN <= 1) ? 1 : $clog2(C_IN);
//    localparam EXPECTED_PATCHES = (IMG_WIDTH - 3 + 1) * (IMG_HEIGHT - 3 + 1); // 16 Tensors / Frame

//    // =========================================================
//    // 2. SIGNALS
//    // =========================================================
//    reg                         clk;
//    reg                         rst_n;
//    reg                         pixel_valid;
//    reg  [DATA_WIDTH-1:0]       pixel_in;

//    // Stage 1 Outputs
//    wire [DATA_WIDTH-1:0]       row0_pixel, row1_pixel, row2_pixel;
//    wire                        rows_valid;

//    // Stage 2 Outputs
//    wire [DATA_WIDTH*9-1:0]     patch_3x3_data;
//    wire                        patch_3x3_valid;

//    // Stage 3 Outputs
//    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
//    wire                        patch_cin_valid;

//    // Monitors
//    wire [CHAN_WIDTH-1:0]       channel_idx;
//    wire                        frame_c_done;

//    // =========================================================
//    // 3. DUT INSTANTIATION
//    // =========================================================
//    top_sliding_window_ver1 #(
//        .DATA_WIDTH(DATA_WIDTH),
//        .IMG_WIDTH (IMG_WIDTH),
//        .IMG_HEIGHT(IMG_HEIGHT),
//        .C_IN      (C_IN)
//    ) u_top (
//        .clk             (clk),
//        .rst_n           (rst_n),
//        .pixel_valid     (pixel_valid),
//        .pixel_in        (pixel_in),
        
//        .row0_pixel      (row0_pixel),
//        .row1_pixel      (row1_pixel),
//        .row2_pixel      (row2_pixel),
//        .rows_valid      (rows_valid),
        
//        .patch_3x3_data  (patch_3x3_data),
//        .patch_3x3_valid (patch_3x3_valid),
        
//        .patch_cin_data  (patch_cin_data),
//        .patch_cin_valid (patch_cin_valid),
        
//        .channel_idx     (channel_idx),
//        .frame_c_done    (frame_c_done)
//    );

//    // Clock Generator 10ns
//    initial begin
//        clk = 1'b0;
//        forever #5 clk = ~clk;
//    end

//    // =========================================================
//    // 4. FULL PIPELINE MONITORS
//    // =========================================================

//    // STEP 1: LINE BUFFER MONITOR
//    always @(posedge clk) begin
//        if (rst_n && rows_valid) begin
//            $display("[TIME %0t ns] ? [STAGE 1: LINE_BUFFER] CH=%0d | R0=%02h, R1=%02h, R2=%02h | ROWS_VALID=1", 
//                     $time, channel_idx, row0_pixel, row1_pixel, row2_pixel);
//        end
//    end

//    // STEP 2: WINDOW GENERATOR MONITOR
//    always @(posedge clk) begin
//        if (rst_n && patch_3x3_valid) begin
//            $display("   ??? ? [STAGE 2: WINDOW_GEN] Single 3x3 Patch Ready (Channel %0d)", channel_idx);
//        end
//    end

//    // STEP 3: CHANNEL BUFFER MONITOR
//    integer total_tensor_cnt;
//    integer c_log;
//    initial total_tensor_cnt = 0;

//    always @(posedge clk) begin
//        if (rst_n && patch_cin_valid) begin
//            total_tensor_cnt = total_tensor_cnt + 1;
//            $display("\n==================================================================================");
//            $display("[TIME %0t ns] ? [STAGE 3: TOP OUTPUT] TENSOR #%0d READY FOR PE ARRAY (3x3x%0d)!", 
//                     $time, total_tensor_cnt, C_IN);
//            $display("==================================================================================");
//            for (c_log = 0; c_log < C_IN; c_log = c_log + 1) begin
//                $display("  --- CHANNEL %0d ---", c_log);
//                $display("  | %02h  %02h  %02h |", 
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*8 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*7 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*6 +: DATA_WIDTH]);
//                $display("  | %02h  %02h  %02h |", 
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*5 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*4 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*3 +: DATA_WIDTH]);
//                $display("  | %02h  %02h  %02h |", 
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*2 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*1 +: DATA_WIDTH],
//                         patch_cin_data[DATA_WIDTH*9*c_log + 0           +: DATA_WIDTH]);
//            end
//            $display("==================================================================================\n");
//        end
//    end

//    // =========================================================
//    // 5. DRIVER TASKS (??NG B? CHU?N THEO TB_LINE_BUFFER_VER2)
//    // =========================================================
//    task send_pixel;
//        input integer ch;
//        input integer row;
//        input integer col;
//        begin
//            @(posedge clk);
//            #1;
//            pixel_valid = 1'b1;
//            pixel_in    = ch * 100 + row * 10 + col;
//        end
//    endtask

//    task send_channel;
//        input integer ch;
//        integer r, c;
//        begin
//            $display("\n----------------------------------------------------------------------------------");
//            $display("---> START STREAMING CHANNEL %0d / %0d <---", ch, C_IN - 1);
//            $display("----------------------------------------------------------------------------------");
//            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
//                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
//                    send_pixel(ch, r, c);
//                end
                
//                // End of Row: H? pixel_valid và t?o nh?p ngh? 2 cycles chu?n xác
//                @(posedge clk); #1;
//                pixel_valid = 1'b0;
//                pixel_in    = 0;
                
//                repeat (2) @(posedge clk); // ??m b?o nh?p ngh? chu?n theo tb_line_buffer_ver2
//            end
//        end
//    endtask

//    // =========================================================
//    // 6. MAIN SIMULATION FLOW
//    // =========================================================
//    integer c_idx;

//    initial begin
//        rst_n       = 1'b0;
//        pixel_valid = 1'b0;
//        pixel_in    = 0;

//        #20;
//        rst_n = 1'b1;
//        repeat (2) @(posedge clk);

//        $display("\n################################################################");
//        $display("   START TRIPLE-MODULE INTEGRATED PIPELINE SIMULATION");
//        $display("   Image: %0dx%0d | Channels: %0d", IMG_WIDTH, IMG_HEIGHT, C_IN);
//        $display("################################################################\n");

//        for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
//            send_channel(c_idx);
//        end

//        repeat (10) @(posedge clk);

//        $display("\n################################################################");
//        $display("                    FULL PIPELINE REPORT");
//        $display("################################################################");
//        $display(" Expected Tensors Output : %0d", EXPECTED_PATCHES);
//        $display(" Actual Tensors Output   : %0d", total_tensor_cnt);
        
//        if (total_tensor_cnt == EXPECTED_PATCHES) begin
//            $display(" STATUS                  : ? TEST PASSED 100%!");
//        end else begin
//            $display(" STATUS                  : ? TEST FAILED!");
//        end
//        $display("################################################################\n");

//        $finish;
//    end

//endmodule

`timescale 1ns/1ps

module tb_top_sliding_window_ver21;

    // =========================================================
    // 1. PARAMETERS
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;
    parameter IMG_HEIGHT = 6;
    parameter C_IN       = 6;

    localparam CHAN_WIDTH       = (C_IN <= 1) ? 1 : $clog2(C_IN);
    localparam EXPECTED_PATCHES = (IMG_WIDTH - 3 + 1) * (IMG_HEIGHT - 3 + 1); // 16 Tensors / Frame

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg                         clk;
    reg                         rst_n;
    reg                         pixel_valid;
    reg  [DATA_WIDTH-1:0]       pixel_in;

    // Stage 1 Outputs
    wire [DATA_WIDTH-1:0]       row0_pixel, row1_pixel, row2_pixel;
    wire                        rows_valid;

    // Stage 2 Outputs
    wire [DATA_WIDTH*9-1:0]     patch_3x3_data;
    wire                        patch_3x3_valid;

    // Stage 3 Outputs
    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
    wire                        patch_cin_valid;

    // Monitors
    wire [CHAN_WIDTH-1:0]       channel_idx;
    wire                        frame_c_done;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    top_sliding_window_ver1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_top (
        .clk             (clk),
        .rst_n           (rst_n),
        .pixel_valid     (pixel_valid),
        .pixel_in        (pixel_in),
        
        .row0_pixel      (row0_pixel),
        .row1_pixel      (row1_pixel),
        .row2_pixel      (row2_pixel),
        .rows_valid      (rows_valid),
        
        .patch_3x3_data  (patch_3x3_data),
        .patch_3x3_valid (patch_3x3_valid),
        
        .patch_cin_data  (patch_cin_data),
        .patch_cin_valid (patch_cin_valid),
        
        .channel_idx     (channel_idx),
        .frame_c_done    (frame_c_done)
    );

    // Clock Generator 10ns (S??n lên t?i 5ns, 15ns, 25ns, 35ns...)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 4. FULL PIPELINE MONITORS
    // =========================================================

    // STEP 1: LINE BUFFER MONITOR
    always @(posedge clk) begin
        if (rst_n && rows_valid) begin
            $display("[TIME %0t ns] ? [STAGE 1: LINE_BUFFER] CH=%0d | R0=%02h, R1=%02h, R2=%02h | ROWS_VALID=1", 
                     $time, channel_idx, row0_pixel, row1_pixel, row2_pixel);
        end
    end

    // STEP 2: WINDOW GENERATOR MONITOR
    always @(posedge clk) begin
        if (rst_n && patch_3x3_valid) begin
            $display("   ??? ? [STAGE 2: WINDOW_GEN] Single 3x3 Patch Ready (Channel %0d)", channel_idx);
        end
    end

    // STEP 3: CHANNEL BUFFER MONITOR
    integer total_tensor_cnt;
    integer c_log;
    initial total_tensor_cnt = 0;

    always @(posedge clk) begin
        if (rst_n && patch_cin_valid) begin
            total_tensor_cnt = total_tensor_cnt + 1;
            $display("\n==================================================================================");
            $display("[TIME %0t ns] ? [STAGE 3: TOP OUTPUT] TENSOR #%0d READY FOR PE ARRAY (3x3x%0d)!", 
                     $time, total_tensor_cnt, C_IN);
            $display("==================================================================================");
            for (c_log = 0; c_log < C_IN; c_log = c_log + 1) begin
                $display("  --- CHANNEL %0d ---", c_log);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*8 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*7 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*6 +: DATA_WIDTH]);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*5 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*4 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*3 +: DATA_WIDTH]);
                $display("  | %02h  %02h  %02h |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*2 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*1 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + 0           +: DATA_WIDTH]);
            end
            $display("==================================================================================\n");
        end
    end

    // =========================================================
    // 5. DRIVER TASKS (FIXED TIMING: ZERO DELAY UPON POS EDGE CLK)
    // =========================================================
    task send_pixel;
        input integer ch;
        input integer row;
        input integer col;
        begin
            @(posedge clk);
            // ?Ã XÓA #1;
            // Dùng Non-blocking <= ?? pixel_valid và pixel_in chuy?n ngay t?i c?nh posedge clk
            pixel_valid <= 1'b1;
            pixel_in    <= ch * 100 + row * 10 + col;
        end
    endtask

    task send_channel;
        input integer ch;
        integer r, c;
        begin
            $display("\n----------------------------------------------------------------------------------");
            $display("---> START STREAMING CHANNEL %0d / %0d <---", ch, C_IN - 1);
            $display("----------------------------------------------------------------------------------");
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    send_pixel(ch, r, c);
                end
                
                // End of Row: H? pixel_valid ngay ?úng nh?p posedge clk k? ti?p (XÓA #1)
                @(posedge clk);
                pixel_valid <= 1'b0;
                pixel_in    <= 0;
                
                // Gi? nh?p ngh? 2 chu k? ?? Line Buffer clear s?ch tr?ng thái new_row
                repeat (1) @(posedge clk);
            end
        end
    endtask

    // =========================================================
    // 6. MAIN SIMULATION FLOW
    // =========================================================
    integer c_idx;

    initial begin
        rst_n       = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n################################################################");
        $display("   START TRIPLE-MODULE INTEGRATED PIPELINE SIMULATION");
        $display("   Image: %0dx%0d | Channels: %0d", IMG_WIDTH, IMG_HEIGHT, C_IN);
        $display("################################################################\n");

        for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
            send_channel(c_idx);
        end

        repeat (10) @(posedge clk);

        $display("\n################################################################");
        $display("                    FULL PIPELINE REPORT");
        $display("################################################################");
        $display(" Expected Tensors Output : %0d", EXPECTED_PATCHES);
        $display(" Actual Tensors Output   : %0d", total_tensor_cnt);
        
        if (total_tensor_cnt == EXPECTED_PATCHES) begin
            $display(" STATUS                  : ? TEST PASSED 100%!");
        end else begin
            $display(" STATUS                  : ? TEST FAILED!");
        end
        $display("################################################################\n");

        $finish;
    end

endmodule