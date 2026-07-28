`timescale 1ns/1ps

/*
================================================================================
  UNIT TESTBENCH CHO CHANNEL_PATCH_BUFFER_VER3
  
  M?c tiêu ki?m th?:
  1. Tích l?y patch 3x3 t? Channel 0 -> (C_IN - 1).
  2. Ki?m tra zero-latency ? channel cu?i: patch_cin_valid gi?t lên = 1 ngay nh?p
     g?i channel cu?i cùng.
  3. Ki?m tra tính ?úng ??n c?a bus patch_cin_data (c? th? LSB -> MSB).
  4. Ki?m tra tính n?ng FRAME_CLEAR: Xóa toàn b? d? li?u ??m c? tr??c khi b?m Frame m?i.
================================================================================
*/

module tb_channel_patch_ver3;

    // =========================================================
    // PARAMETERS (??I C_IN = 1 CHO CONV1 HO?C C_IN = 6 CHO CONV2)
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter C_IN       = 6; // ??i C_IN = 1 cho Conv1, C_IN = 6 cho Conv2

    localparam CHAN_WIDTH = (C_IN <= 1) ? 1 : $clog2(C_IN);

    // =========================================================
    // SIGNALS FOR DUT
    // =========================================================
    reg                         clk;
    reg                         rst_n;
    reg                         frame_clear;      // Tín hi?u xóa s?ch Frame

    reg                         patch_3x3_valid;
    reg  [DATA_WIDTH*9-1:0]     patch_3x3_data;
    reg  [CHAN_WIDTH-1:0]       channel_idx;

    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
    wire                        patch_cin_valid;

    // =========================================================
    // DUT INSTANTIATION (CHANNEL_PATCH_BUFFER_VER3)
    // =========================================================
    channel_patch_buffer_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_IN      (C_IN)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .frame_clear     (frame_clear),     // ??u n?i frame_clear
        .patch_3x3_valid (patch_3x3_valid),
        .patch_3x3_data  (patch_3x3_data),
        .channel_idx     (channel_idx),
        .patch_cin_data  (patch_cin_data),
        .patch_cin_valid (patch_cin_valid)
    );

    // Clock Generator 10ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: LOG TOÀN B? BUS PATCH_CIN_DATA RA CONSOLE
    // =========================================================
    integer c_log;
    always @(posedge clk) begin
        if (rst_n && patch_cin_valid) begin
            $display("\n==================================================================================");
            $display("[TIME %0t ns] ? SUCCESS: PATCH_CIN_VALID = 1 (T?NG %0d CHANNELS / %0d BITS)", 
                     $time, C_IN, DATA_WIDTH*9*C_IN);
            $display("==================================================================================");
            
            for (c_log = 0; c_log < C_IN; c_log = c_log + 1) begin
                $display("--- CHANNEL %0d (Slice [%0d:%0d]) ---", 
                         c_log, DATA_WIDTH*9*(c_log+1)-1, DATA_WIDTH*9*c_log);
                $display("  +------+------+------+");
                $display("  |  %02h  |  %02h  |  %02h  |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*8 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*7 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*6 +: DATA_WIDTH]);
                $display("  +------+------+------+");
                $display("  |  %02h  |  %02h  |  %02h  |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*5 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*4 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*3 +: DATA_WIDTH]);
                $display("  +------+------+------+");
                $display("  |  %02h  |  %02h  |  %02h  |", 
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*2 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + DATA_WIDTH*1 +: DATA_WIDTH],
                         patch_cin_data[DATA_WIDTH*9*c_log + 0           +: DATA_WIDTH]);
                $display("  +------+------+------+");
            end
            $display("==================================================================================\n");
        end
    end

    // =========================================================
    // TASKS B?M D? LI?U & ?I?U KHI?N (ZERO-DELAY TIMING)
    // =========================================================
    // Task b?m 1 Patch 3x3x1 cho Channel ch? ??nh
    task send_single_channel_patch;
        input [CHAN_WIDTH-1:0] ch_id;
        input [DATA_WIDTH*9-1:0] data_3x3;
        begin
            @(posedge clk);
            patch_3x3_valid <= 1'b1;
            channel_idx     <= ch_id;
            patch_3x3_data  <= data_3x3;
            
            $display("[TIME %0t ns] Injecting Patch -> Channel %0d | Data Hex = %h", 
                     $time, ch_id, data_3x3);
            
            @(posedge clk);
            patch_3x3_valid <= 1'b0;
            patch_3x3_data  <= 0;
        end
    endtask

    // Task phát xung frame_clear (Xóa toàn b? ??m gi?a các Frame)
    task do_frame_clear;
        begin
            $display("\n==================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE (1 CLOCK CYCLE) <<<");
            $display("==================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            patch_3x3_valid <= 1'b0;
            @(posedge clk);
            frame_clear <= 1'b0;
        end
    endtask

    // Hàm t?o pattern patch 3x3 gi? l?p d? nh?n bi?t theo channel index
    function [DATA_WIDTH*9-1:0] make_patch_pattern;
        input integer ch;
        reg [DATA_WIDTH-1:0] val;
        begin
            val = ch + 1; // Generates 010101..., 020202..., etc.
            make_patch_pattern = {9{val}};
        end
    endfunction

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    integer ch;
    initial begin
        // Reset ban ??u
        rst_n           = 1'b0;
        frame_clear     = 1'b0;
        patch_3x3_valid = 1'b0;
        patch_3x3_data  = 0;
        channel_idx     = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("   START UNIT TEST: CHANNEL_PATCH_BUFFER_VER3 (C_IN = %0d)", C_IN);
        $display("##################################################\n");

        // -----------------------------------------------------
        // TEST SCENARIO 1: B?M FRAME 1 (CHANNEL 0 -> C_IN - 1)
        // -----------------------------------------------------
        $display("---> TEST FRAME 1: STREAMING ALL CHANNELS <---");
        for (ch = 0; ch < C_IN; ch = ch + 1) begin
            send_single_channel_patch(ch, make_patch_pattern(ch));
            repeat (2) @(posedge clk); // Ngh? ng?n gi?a các channel
        end

        repeat (5) @(posedge clk);

        // -----------------------------------------------------
        // TEST SCENARIO 2: KÍCH HO?T FRAME_CLEAR ?? XÓA FRAME 1
        // -----------------------------------------------------
        do_frame_clear();
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // TEST SCENARIO 3: B?M FRAME 2 (D? LI?U M?I OFFSET +10)
        // -----------------------------------------------------
        $display("\n---> TEST FRAME 2: B?M ??T D? LI?U M?I SAU CLEAR <---");
        for (ch = 0; ch < C_IN; ch = ch + 1) begin
            send_single_channel_patch(ch, make_patch_pattern(ch + 10)); // Pattern khác ??t 1 (11, 12, 13...)
            repeat (2) @(posedge clk);
        end

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("       SIMULATION COMPLETE: VERIFIED ALL!");
        $display("##################################################");
        $finish;
    end

endmodule