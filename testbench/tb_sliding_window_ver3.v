`timescale 1ns/1ps

/*
================================================================================
   FULL PIPELINE TESTBENCH FOR TOP_SLIDING_WINDOW WITH FRAME_CLEAR
   
   C?u trúc tích h?p:
   Line Buffer (v3) -> Window Generator (v3) -> Channel Patch Buffer (v3)
================================================================================
*/

module tb_top_sliding_window_ver3;

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
    reg                         frame_clear;    // Tín hi?u xóa Frame m?i b? sung
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
    top_sliding_window_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_top (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_clear     (frame_clear),      // K?t n?i tín hi?u frame_clear
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

    // Clock Generator 10ns
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
    // 5. DRIVER TASKS (FIXED TIMING + MULTI-FRAME SUPPORT)
    // =========================================================
    task send_pixel;
        input integer ch;
        input integer row;
        input integer col;
        input integer offset_val;
        begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            pixel_in    <= offset_val + ch * 100 + row * 10 + col;
        end
    endtask

    task send_channel;
        input integer ch;
        input integer offset_val;
        integer r, c;
        begin
            $display("\n----------------------------------------------------------------------------------");
            $display("---> START STREAMING CHANNEL %0d / %0d (Offset = %0d) <---", ch, C_IN - 1, offset_val);
            $display("----------------------------------------------------------------------------------");
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    send_pixel(ch, r, c, offset_val);
                end
                
                // End of Row: H? pixel_valid
                @(posedge clk);
                pixel_valid <= 1'b0;
                pixel_in    <= 0;
                
                // Nh?p ngh? gi?a các hàng
                repeat (2) @(posedge clk);
            end
        end
    endtask

    // Task phát xung frame_clear 1 clock
    task do_frame_clear;
        begin
            $display("\n==================================================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE TO RESET PIPELINE FOR NEW FRAME <<<");
            $display("==================================================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            pixel_valid <= 1'b0;
            pixel_in    <= 0;
            @(posedge clk);
            frame_clear <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    // Task g?i tr?n v?n 1 Frame
    task send_full_frame;
        input integer frame_num;
        input integer offset_val;
        integer c_idx;
        begin
            $display("\n################################################################");
            $display("   START FRAME #%0d PIPELINE SIMULATION (Offset = %0d)", frame_num, offset_val);
            $display("################################################################\n");

            for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
                send_channel(c_idx, offset_val);
            end
        end
    endtask

    // =========================================================
    // 6. MAIN SIMULATION FLOW
    // =========================================================
    initial begin
        rst_n       = 1'b0;
        frame_clear = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // TEST 1: CH?Y FRAME 1 (D? li?u g?c)
        // -----------------------------------------------------
        send_full_frame(1, 0);

        repeat (5) @(posedge clk);

        // -----------------------------------------------------
        // TEST 2: KÍCH HO?T FRAME_CLEAR ?? LÀM S?CH PIPELINE
        // -----------------------------------------------------
        do_frame_clear();

        // Reset b? ??m tensor thu ???c ?? ki?m tra ??c l?p Frame 2
        total_tensor_cnt = 0;

        // -----------------------------------------------------
        // TEST 3: CH?Y FRAME 2 (D? li?u m?i có Offset = +200)
        // -----------------------------------------------------
        send_full_frame(2, 200);

        repeat (10) @(posedge clk);

        // =========================================================
        // FULL SYSTEM VERIFICATION SUMMARY
        // =========================================================
        $display("\n################################################################");
        $display("                    FULL PIPELINE REPORT");
        $display("################################################################");
        $display(" Expected Tensors Output per Frame : %0d", EXPECTED_PATCHES);
        $display(" Actual Tensors Output for Frame 2  : %0d", total_tensor_cnt);
        
        if (total_tensor_cnt == EXPECTED_PATCHES) begin
            $display(" STATUS                            : ? TEST PASSED 100%! Frame Clear & Pipeline worked!");
        end else begin
            $display(" STATUS                            : ? TEST FAILED!");
        end
        $display("################################################################\n");

        $finish;
    end

endmodule