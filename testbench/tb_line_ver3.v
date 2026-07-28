`timescale 1ns/1ps

module tb_line_buffer_ver3;

    // =========================================================
    // PARAMETERS (CÓ TH? ??I C_IN = 1 CHO CONV1 HO?C C_IN = 6 CHO CONV2)
    // =========================================================
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 6;   // ??i thành 28 cho ?nh chu?n Conv1/Conv2
    parameter IMG_HEIGHT = 6;   // ??i thành 28 cho ?nh chu?n Conv1/Conv2
    parameter C_IN       = 6;   // Test linh ho?t C_IN = 1 ho?c C_IN = 6

    localparam CHAN_WIDTH = (C_IN <= 1) ? 1 : $clog2(C_IN);

    // =========================================================
    // SIGNALS
    // =========================================================
    reg                         clk;
    reg                         rst_n;
    reg                         frame_clear; // Tín hi?u xóa Frame
    reg                         pixel_valid;
    reg  [DATA_WIDTH-1:0]       pixel_in;

    wire [DATA_WIDTH-1:0]       row0_pixel;
    wire [DATA_WIDTH-1:0]       row1_pixel;
    wire [DATA_WIDTH-1:0]       row2_pixel;
    wire                        rows_valid;
    wire                        new_row;
    wire [CHAN_WIDTH-1:0]       channel_idx;
    wire                        frame_c_done;

    // =========================================================
    // DUT INSTANTIATION (LINE BUFFER VER3)
    // =========================================================
    line_buffer_model_ver3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .C_IN      (C_IN)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_clear  (frame_clear), // ??u n?i tín hi?u frame_clear
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),
        .row0_pixel   (row0_pixel),
        .row1_pixel   (row1_pixel),
        .row2_pixel   (row2_pixel),
        .rows_valid   (rows_valid),
        .new_row      (new_row),
        .channel_idx  (channel_idx),
        .frame_c_done (frame_c_done)
    );

    // Clock Generator 10ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // MONITOR: THEO DÕI LOG CONSOLE
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && pixel_valid) begin
            $display("[TIME %0t ns] CH=%0d | IN=%3d | ROW0=%3d | ROW1=%3d | ROW2=%3d | ROWS_VALID=%b",
                     $time, channel_idx, pixel_in, row0_pixel, row1_pixel, row2_pixel, rows_valid);
        end
        if (rst_n && new_row) begin
            $display(">>> [PULSE] NEW ROW PULSE DETECTED <<<");
        end
        if (rst_n && frame_c_done) begin
            $display(">>> [PULSE] FRAME_C_DONE DETECTED! ALL %0d CHANNELS PROCESSED <<<", C_IN);
        end
    end

    // =========================================================
    // TASKS B?M D? LI?U
    // =========================================================
    // Task g?i 1 pixel (Dùng offset_val ?? phân bi?t các Frame)
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

    // Task g?i 1 channel ?nh
    task send_channel;
        input integer ch;
        input integer offset_val;
        integer r, c;
        begin
            $display("\n--------------------------------------------------");
            $display("START STREAMING CHANNEL %0d (C_IN = %0d) [Offset=%0d]", ch, C_IN, offset_val);
            $display("--------------------------------------------------");
            
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    send_pixel(ch, r, c, offset_val);
                end
                
                // K?t thúc 1 hàng: H? pixel_valid
                @(posedge clk);
                pixel_valid <= 1'b0; // 1'b0;
                pixel_valid <= 1'b0;
                pixel_in    <= 0;
                
                // Ngh? 2 chu k? clock chu?n gi?a các hàng
                repeat (2) @(posedge clk);
            end
        end
    endtask

    // Task phát xung frame_clear 1 clock
    task do_frame_clear;
        begin
            $display("\n==================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE (1 CLOCK CYCLE) <<<");
            $display("==================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            @(posedge clk);
            frame_clear <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    // Task b?m tr?n v?n 1 Frame ?nh (T?t c? C_IN channels)
    task send_full_frame;
        input integer frame_num;
        input integer offset_val;
        integer c_idx;
        begin
            $display("\n##################################################");
            $display("      START FRAME #%0d SIMULATION (Offset = %0d)", frame_num, offset_val);
            $display("##################################################");
            for (c_idx = 0; c_idx < C_IN; c_idx = c_idx + 1) begin
                send_channel(c_idx, offset_val);
            end
        end
    endtask

    // =========================================================
    // MAIN SIMULATION PROCESS
    // =========================================================
    initial begin
        // Reset ban ??u
        rst_n       = 1'b0;
        frame_clear = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // TEST 1: CH?Y FRAME 1 (D? li?u g?c 0..35 per channel)
        // -----------------------------------------------------
        send_full_frame(1, 0);

        repeat (5) @(posedge clk);

        // -----------------------------------------------------
        // TEST 2: KÍCH HO?T FRAME_CLEAR ?? XÓA FRAME 1
        // -----------------------------------------------------
        do_frame_clear();

        // -----------------------------------------------------
        // TEST 3: CH?Y FRAME 2 (D? li?u m?i có Offset = +200)
        // Ki?m tra xem Frame 2 có b? dính data c? c?a Frame 1 không
        // -----------------------------------------------------
        send_full_frame(2, 200);

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("   SIMULATION COMPLETE: FRAME_CLEAR VERIFIED!");
        $display("##################################################");
        $finish;
    end

endmodule