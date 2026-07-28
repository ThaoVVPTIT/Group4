`timescale 1ns/1ps

/*
================================================================================
  UNIT TESTBENCH CHO CHANNEL_PATCH_BUFFER
  
  M?c tiêu ki?m th?:
  1. Ki?m tra tích l?y patch 3x3 t? Channel 0 -> (C_IN - 1).
  2. Ki?m tra zero-latency ? channel cu?i: patch_cin_valid gi?t lên = 1 ngay nh?p
     g?i channel cu?i cùng.
  3. Ki?m tra tính ?úng ??n c?a bus patch_cin_data (c? th? LSB -> MSB):
     - [DATA_WIDTH*9-1 : 0]                          = Channel 0
     - [DATA_WIDTH*9*2-1 : DATA_WIDTH*9]              = Channel 1
     ...
     - [DATA_WIDTH*9*C_IN-1 : DATA_WIDTH*9*(C_IN-1)] = Channel C_IN-1
================================================================================
*/

module tb_channel_patch_buffer;

    // =========================================================
    // PARAMETERS (??I C_IN = 1 HO?C C_IN = 6 T?I ?ÂY)
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter C_IN       = 6; // ??i C_IN = 1 cho Conv1, C_IN = 6 cho Conv2

    localparam CHAN_WIDTH = (C_IN <= 1) ? 1 : $clog2(C_IN);

    // =========================================================
    // SIGNALS FOR DUT
    // =========================================================
    reg                         clk;
    reg                         rst_n;

    reg                         patch_3x3_valid;
    reg  [DATA_WIDTH*9-1:0]     patch_3x3_data;
    reg  [CHAN_WIDTH-1:0]       channel_idx;

    wire [DATA_WIDTH*9*C_IN-1:0] patch_cin_data;
    wire                        patch_cin_valid;

    // =========================================================
    // DUT INSTANTIATION
    // =========================================================
    channel_patch_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_IN      (C_IN)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .patch_3x3_valid (patch_3x3_valid),
        .patch_3x3_data  (patch_3x3_data),
        .channel_idx     (channel_idx),
        .patch_cin_data  (patch_cin_data),
        .patch_cin_valid (patch_cin_valid)
    );

    // Clock 10ns
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
    // TASK B?M 1 PATCH 3x3 CHO C?P (CHANNEL, DATA)
    // =========================================================
    task send_single_channel_patch;
        input [CHAN_WIDTH-1:0] ch_id;
        input [DATA_WIDTH*9-1:0] data_3x3;
        begin
            @(posedge clk);
//            #1;
            patch_3x3_valid = 1'b1;
            channel_idx     = ch_id;
            patch_3x3_data  = data_3x3;
            
            $display("[TIME %0t ns] Injecting Patch -> Channel %0d | Data Hex = %h", 
                     $time, ch_id, data_3x3);
            
            @(posedge clk);
//            #1;
            patch_3x3_valid = 1'b0;
            patch_3x3_data  = 0;
        end
    endtask

    // Hàm t?o pattern patch 3x3 gi? l?p d? nh?n di?n theo channel index
    // Ví d?: Channel 0 -> 9 byte b?ng 8'h01
    //        Channel 1 -> 9 byte b?ng 8'h02...
    function [DATA_WIDTH*9-1:0] make_patch_pattern;
        input integer ch;
        reg [DATA_WIDTH-1:0] val;
        begin
            val = ch + 1; // 1, 2, 3, 4, 5, 6
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
        patch_3x3_valid = 1'b0;
        patch_3x3_data  = 0;
        channel_idx     = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("   START UNIT TEST: CHANNEL_PATCH_BUFFER (C_IN = %0d)", C_IN);
        $display("##################################################\n");

        // B?m tu?n t? t?ng channel t? 0 ??n C_IN - 1
        for (ch = 0; ch < C_IN; ch = ch + 1) begin
            send_single_channel_patch(ch, make_patch_pattern(ch));
            
            // Tùy ch?n: Ngh? vài clock gi?a các channel ?? test tính gi? b? ??m (Hold value)
            repeat (2) @(posedge clk);
        end

        repeat (5) @(posedge clk);

        // -----------------------------------------------------
        // TEST FRAME TH? 2 (KI?M TRA B?M L?N 2 D? LI?U M?I)
        // -----------------------------------------------------
        $display("\n---> TEST FRAME 2: B?M ??T D? LI?U M?I <---");
        for (ch = 0; ch < C_IN; ch = ch + 1) begin
            send_single_channel_patch(ch, make_patch_pattern(ch + 10)); // Giá tr? Hex khác ??t 1
        end

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("              SIMULATION COMPLETE");
        $display("##################################################");
        $finish;
    end

endmodule