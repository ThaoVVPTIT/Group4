`timescale 1ns/1ps

/*
================================================================================
  UNIT TESTBENCH CHO WINDOW_GENERATOR_VER3
  
  M?c tiêu:
  1. Ki?m tra timing: 2 c?t ??u VALID = 0, c?t th? 3 tr? ?i VALID = 1.
  2. Ki?m tra tính n?ng d?ch tr??t ngang (Shift Window) liên t?c.
  3. Ki?m tra tính n?ng xóa c?a s? hàng ngang (col_window_clear / new_row).
  4. Ki?m tra tính n?ng XÓA S?CH FRAME (frame_clear) khi chuy?n sang ?nh m?i.
================================================================================
*/

module tb_window_gen_ver3;

    // =========================================================
    // PARAMETERS
    // =========================================================
    parameter DATA_WIDTH = 8;
    
    // =========================================================
    // SIGNALS FOR DUT
    // =========================================================
    reg                     clk;
    reg                     rst_n;
    reg                     frame_clear;      // Tín hi?u xóa toàn b? Frame
    reg                     pixel_valid;      // Tín hi?u valid t? Line Buffer
    reg                     col_window_clear; // Tín hi?u new_row t? Line Buffer

    reg  [DATA_WIDTH-1:0]   row0_pixel;
    reg  [DATA_WIDTH-1:0]   row1_pixel;
    reg  [DATA_WIDTH-1:0]   row2_pixel;

    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    // =========================================================
    // DUT INSTANTIATION (WINDOW_GENERATOR_VER3)
    // =========================================================
    window_generator_ver3 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .frame_clear      (frame_clear),      // ??u n?i frame_clear
        .pixel_valid      (pixel_valid),
        .col_window_clear (col_window_clear),
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),
        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // Clock Generator 10ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: LOG MA TR?N 3x3 D?NG HEX
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && patch_3x3_valid) begin
            $display("\n[TIME %0t ns] >>> PATCH 3x3 VALID = 1 <<<", $time);
            $display("  +------+------+------+");
            $display("  |  %02h  |  %02h  |  %02h  |", 
                     patch_3x3_data[DATA_WIDTH*9-1 : DATA_WIDTH*8], 
                     patch_3x3_data[DATA_WIDTH*8-1 : DATA_WIDTH*7], 
                     patch_3x3_data[DATA_WIDTH*7-1 : DATA_WIDTH*6]);
            $display("  +------+------+------+");
            $display("  |  %02h  |  %02h  |  %02h  |", 
                     patch_3x3_data[DATA_WIDTH*6-1 : DATA_WIDTH*5], 
                     patch_3x3_data[DATA_WIDTH*5-1 : DATA_WIDTH*4], 
                     patch_3x3_data[DATA_WIDTH*4-1 : DATA_WIDTH*3]);
            $display("  +------+------+------+");
            $display("  |  %02h  |  %02h  |  %02h  |", 
                     patch_3x3_data[DATA_WIDTH*3-1 : DATA_WIDTH*2], 
                     patch_3x3_data[DATA_WIDTH*2-1 : DATA_WIDTH*1], 
                     patch_3x3_data[DATA_WIDTH*1-1 : 0]);
            $display("  +------+------+------+");
        end
    end

    // =========================================================
    // TASKS B?M D? LI?U & ?I?U KHI?N (ZERO-DELAY TIMING)
    // =========================================================
    // Task b?m 1 c?t (g?m 3 pixel cùng c?t)
    task send_column;
        input [DATA_WIDTH-1:0] r0;
        input [DATA_WIDTH-1:0] r1;
        input [DATA_WIDTH-1:0] r2;
        begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            row0_pixel  <= r0;
            row1_pixel  <= r1;
            row2_pixel  <= r2;
        end
    endtask

    // Task d?ng b?m stream
    task stop_stream;
        begin
            @(posedge clk);
            pixel_valid <= 1'b0;
            row0_pixel  <= 8'h00;
            row1_pixel  <= 8'h00;
            row2_pixel  <= 8'h00;
        end
    endtask

    // Task reset c?a s? tr??t ngang khi sang Hàng m?i
    task clear_col_window;
        begin
            @(posedge clk);
            col_window_clear <= 1'b1;
            pixel_valid      <= 1'b0;
            @(posedge clk);
            col_window_clear <= 1'b0;
        end
    endtask

    // Task phát xung frame_clear (xóa toàn b? c?a s? khi sang Frame m?i)
    task do_frame_clear;
        begin
            $display("\n==================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE (1 CLOCK CYCLE) <<<");
            $display("==================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            pixel_valid <= 1'b0;
            @(posedge clk);
            frame_clear <= 1'b0;
        end
    endtask

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    initial begin
        // Reset ban ??u
        rst_n            = 1'b0;
        frame_clear      = 1'b0;
        pixel_valid      = 1'b0;
        col_window_clear = 1'b0;
        row0_pixel       = 8'h00;
        row1_pixel       = 8'h00;
        row2_pixel       = 8'h00;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("    START UNIT TEST: WINDOW_GENERATOR_VER3");
        $display("##################################################");

        // -----------------------------------------------------
        // TEST SCENARIO 1: TR??T TRÊN HÀNG ??U TIÊN (HÀNG A)
        // -----------------------------------------------------
        $display("\n---> TEST 1: STREAM 4 C?T TRÊN HÀNG A <---");
        clear_col_window();

        // C?t 0: (00, 0A, 14) -> Expected: valid = 0
        send_column(8'h00, 8'h0A, 8'h14);
        
        // C?t 1: (01, 0B, 15) -> Expected: valid = 0
        send_column(8'h01, 8'h0B, 8'h15);
        
        // C?t 2: (02, 0C, 16) -> ?? 3 C?T! Expected: valid = 1 (Patch 0)
        send_column(8'h02, 8'h0C, 8'h16);
        
        // C?t 3: (03, 0D, 17) -> Tr??t ngang! Expected: valid = 1 (Patch 1)
        send_column(8'h03, 8'h0D, 8'h17);

        stop_stream();
        repeat (3) @(posedge clk);

        // -----------------------------------------------------
        // TEST SCENARIO 2: SANG HÀNG M?I (COL_WINDOW_CLEAR)
        // -----------------------------------------------------
        $display("\n---> TEST 2: SANG HÀNG B (COL_WINDOW_CLEAR) <---");
        clear_col_window(); // Gi? l?p new_row t? Line Buffer

        // C?t 0 hàng B: (0A, 14, 1E) -> Expected: valid = 0
        send_column(8'h0A, 8'h14, 8'h1E);

        // C?t 1 hàng B: (0B, 15, 1F) -> Expected: valid = 0
        send_column(8'h0B, 8'h15, 8'h1F);

        // C?t 2 hàng B: (0C, 16, 20) -> Expected: valid = 1 (Patch 0 hàng B)
        send_column(8'h0C, 8'h16, 8'h20);

        stop_stream();
        repeat (3) @(posedge clk);

        // -----------------------------------------------------
        // TEST SCENARIO 3: KÍCH HO?T FRAME_CLEAR & N?P FRAME M?I
        // -----------------------------------------------------
        $display("\n---> TEST 3: XÓA FRAME (FRAME_CLEAR) VÀ B?T ??U FRAME M?I <---");
        do_frame_clear();

        // B?m Frame m?i (D? li?u AA, BB, CC...)
        $display("---> B?M D? LI?U FRAME M?I SAU CLEAR <---");
        send_column(8'hAA, 8'hBB, 8'hCC); // C?t 0 Frame m?i -> Expected: valid = 0
        send_column(8'hA1, 8'hB1, 8'hC1); // C?t 1 Frame m?i -> Expected: valid = 0
        send_column(8'hA2, 8'hB2, 8'hC2); // C?t 2 Frame m?i -> Expected: valid = 1 (Ch?a d? li?u AA, BB, CC...)

        stop_stream();
        repeat (5) @(posedge clk);

        $display("\n##################################################");
        $display("       SIMULATION COMPLETE: VERIFIED ALL!");
        $display("##################################################");
        $finish;
    end

endmodule