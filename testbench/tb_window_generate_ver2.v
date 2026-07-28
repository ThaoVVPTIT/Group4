`timescale 1ns/1ps

/*
================================================================================
  UNIT TESTBENCH CHO WINDOW_GENERATOR_VER2 (SINGLE CHANNEL ONLY)
  
  M?c tiêu:
  1. Ki?m tra chính xác timing: 2 c?t ??u KHÔNG phát valid, c?t th? 3 phát VALID = 1.
  2. Ki?m tra tính n?ng d?ch tr??t ngang (Shift Window) liên t?c.
  3. Ki?m tra tính n?ng reset c?a s? ngang (col_window_clear) khi sang hàng m?i.
  4. Ki?m tra ma tr?n Patch 3x3 xu?t ra có chu?n giá tr? Hex hay không.
================================================================================
*/

module tb_window_generator_ver2;

    // =========================================================
    // PARAMETERS
    // =========================================================
    parameter DATA_WIDTH = 8;
    
    // =========================================================
    // SIGNALS FOR DUT
    // =========================================================
    reg                     clk;
    reg                     rst_n;
    reg                     pixel_valid;
    reg                     col_window_clear;
    reg                     window_clear;

    reg  [DATA_WIDTH-1:0]   row0_pixel;
    reg  [DATA_WIDTH-1:0]   row1_pixel;
    reg  [DATA_WIDTH-1:0]   row2_pixel;

    wire [DATA_WIDTH*9-1:0] patch_3x3_data;
    wire                    patch_3x3_valid;

    // =========================================================
    // DUT INSTANTIATION
    // =========================================================
    window_generator_ver2 #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pixel_valid      (pixel_valid),
        .col_window_clear (col_window_clear),
        .window_clear     (window_clear),
        .row0_pixel       (row0_pixel),
        .row1_pixel       (row1_pixel),
        .row2_pixel       (row2_pixel),
        .patch_3x3_data   (patch_3x3_data),
        .patch_3x3_valid  (patch_3x3_valid)
    );

    // Clock 10ns
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
    // TASKS B?M D? LI?U
    // =========================================================
    // Task b?m 1 c?t (g?m 3 pixel cùng c?t)
    task send_column;
        input [DATA_WIDTH-1:0] r0;
        input [DATA_WIDTH-1:0] r1;
        input [DATA_WIDTH-1:0] r2;
        begin
            @(posedge clk);
            #1;
            pixel_valid = 1'b1;
            row0_pixel  = r0;
            row1_pixel  = r1;
            row2_pixel  = r2;
        end
    endtask

    // Task d?ng b?m
    task stop_stream;
        begin
            @(posedge clk);
            #1;
            pixel_valid = 1'b0;
            row0_pixel  = 8'h00;
            row1_pixel  = 8'h00;
            row2_pixel  = 8'h00;
        end
    endtask

    // Task reset c?a s? tr??t ngang (New Row)
    task clear_col_window;
        begin
            @(posedge clk);
            #1;
            col_window_clear = 1'b1;
            pixel_valid      = 1'b0;
            @(posedge clk);
            #1;
            col_window_clear = 1'b0;
        end
    endtask

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    initial begin
        // Reset ban ??u
        rst_n            = 1'b0;
        pixel_valid      = 1'b0;
        col_window_clear = 1'b0;
        window_clear     = 1'b0;
        row0_pixel       = 8'h00;
        row1_pixel       = 8'h00;
        row2_pixel       = 8'h00;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("    START UNIT TEST: WINDOW_GENERATOR_VER2");
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
        $display("\n---> TEST 2: SANG HÀNG B (KÍCH HO?T COL_WINDOW_CLEAR) <---");
        clear_col_window(); // Gi? l?p c? new_row t? Line Buffer g?i sang

        // C?t 0 hàng B: (0A, 14, 1E) -> Expected: valid = 0
        send_column(8'h0A, 8'h14, 8'h1E);

        // C?t 1 hàng B: (0B, 15, 1F) -> Expected: valid = 0
        send_column(8'h0B, 8'h15, 8'h1F);

        // C?t 2 hàng B: (0C, 16, 20) -> Expected: valid = 1 (Patch 0 c?a hàng B)
        send_column(8'h0C, 8'h16, 8'h20);

        stop_stream();
        repeat (5) @(posedge clk);

        $display("\n##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");
        $finish;
    end

endmodule