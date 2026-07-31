`timescale 1ns / 1ps

/*
================================================================================
    TESTBENCH CHU?N CHO CONV2 + POOL2 TOP LEVEL (conv2_pool2_top)
    
    Tính n?ng:
    - B?m lu?ng d? li?u Feature Map 13x13x6 (1014 pixels) vào CONV2.
    - CONV2 x? lý cho ra Feature Map 11x11x16 (121 pixels/ch).
    - POOL2 (2x2, Stride 2) gi?m kích th??c còn 5x5x16 (25 pixels/ch).
    - T? ??ng ??m, giám sát Realtime và ?ánh giá PASS/FAIL (K? v?ng: 25 pixels/ch).
================================================================================
*/

module tb_conv2_pooling2_top;

    // =========================================================
    // 1. PARAMETERS & LOCALPARAMS
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter IMG_WIDTH   = 13; // Kích th??c ngõ vào 13x13x6
    parameter IMG_HEIGHT  = 13;
    parameter KERNEL_SIZE = 3;
    parameter C_IN        = 6;  // 6 Channel vào
    parameter C_OUT       = 16; // 16 Channel ra

    // Thông s? tính toán kích th??c Output
    localparam CONV_OUT_W = IMG_WIDTH - KERNEL_SIZE + 1; // 11
    localparam CONV_OUT_H = IMG_HEIGHT - KERNEL_SIZE + 1; // 11
    
    localparam POOL_OUT_W = CONV_OUT_W / 2; // 5
    localparam POOL_OUT_H = CONV_OUT_H / 2; // 5
    localparam EXPECTED_POOL_PATCHES = POOL_OUT_W * POOL_OUT_H; // 25 pixels / channel

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg clk;
    reg rst_n;
    reg start;
    reg frame_clear;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    wire [C_OUT-1:0] pool_out_valid;
    wire signed [DATA_WIDTH*C_OUT-1:0] pool_out_ch; // Bus 128-bit
    wire [C_OUT-1:0] pool_out_last;

    // Trích xu?t các channel ra wire l? ?? d? quan sát trên Waveform
    wire signed [DATA_WIDTH-1:0] ch_out [0:C_OUT-1];
    genvar g;
    generate
        for (g = 0; g < C_OUT; g = g + 1) begin : gen_ch_unpack
            assign ch_out[g] = pool_out_ch[DATA_WIDTH*g +: DATA_WIDTH];
        end
    endgenerate

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    top_conv2_pooling2 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .frame_clear    (frame_clear),
        .pixel_valid    (pixel_valid),
        .pixel_in       (pixel_in),

        .pool_out_valid (pool_out_valid),
        .pool_out_ch    (pool_out_ch),
        .pool_out_last  (pool_out_last)
    );

    // =========================================================
    // 4. CLOCK GENERATOR (100 MHz)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 5. LOAD TR?NG S? VÀ BIAS ?O CHO CONV2
    // =========================================================
    integer ch_o, k;
    initial begin
        for (ch_o = 0; ch_o < C_OUT; ch_o = ch_o + 1) begin
            for (k = 0; k < 9 * C_IN; k = k + 1) begin
                u_dut.u_conv2.c2_kernel[ch_o * 54 + k] = (k % (ch_o + 2) == 0) ? 8'sd1 : 8'sd0;
            end
            u_dut.u_conv2.c2_bias[ch_o]   = ch_o; // Bias khác nhau cho t?ng CH
            u_dut.u_conv2.c2_mult[ch_o]   = 32'sd1;
            u_dut.u_conv2.c2_shift[ch_o]  = 8'd0;
        end
    end

    // =========================================================
    // 6. MONITOR OUTPUT STREAM REALTIME (THEO DÕI CHANNEL 0)
    // =========================================================
    integer out_cnt_ch0 = 0;
    always @(posedge clk) begin
        if (rst_n && pool_out_valid[0]) begin
            out_cnt_ch0 = out_cnt_ch0 + 1;
            $display("[TIME %0t ns] POOL2 OUT #%0d | LAST=%b | CH0=%d, CH1=%d, CH2=%d, CH15=%d",
                     $time, out_cnt_ch0, pool_out_last[0],
                     ch_out[0], ch_out[1], ch_out[2], ch_out[15]);
        end
    end

    // =========================================================
    // 7. TASKS
    // =========================================================
    task trigger_start;
        begin
            $display("\n==============================================");
            $display("[%0t ns] START CONV2 + POOL2 FRAME PIPELINE", $time);
            $display("==============================================");
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    task send_image_stream;
        integer r, c, ch;
        integer val;
        begin
            $display("\n---- STREAMING %0dx%0dx%0d IMAGE (1014 PIXELS) ----", IMG_WIDTH, IMG_HEIGHT, C_IN);

            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    for (ch = 0; ch < C_IN; ch = ch + 1) begin
                        val = ((r * IMG_WIDTH + c + 1) + ch) % 15;

                        @(posedge clk);
                        pixel_valid <= 1'b1;
                        pixel_in    <= val[7:0];
                    end
                end
            end

            @(posedge clk);
            pixel_valid <= 1'b0;
            pixel_in    <= 8'sd0;

            $display("[%0t ns] FINISHED STREAMING ALL 1014 PIXELS TO CONV2", $time);
        end
    endtask

    // =========================================================
    // 8. MAIN SIMULATION PROCESS
    // =========================================================
    integer timeout_cycles;
    reg stop_waiting;

    initial begin
        // Kh?i t?o tín hi?u
        rst_n        = 1'b0;
        start        = 1'b0;
        frame_clear  = 1'b0;
        pixel_valid  = 1'b0;
        pixel_in     = 8'sd0;
        out_cnt_ch0  = 0;
        stop_waiting = 1'b0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Hi?n th? c?u hình
        $display("\n==============================================");
        $display("     CONV2 + POOL2 TOP TESTBENCH CONFIG");
        $display("==============================================");
        $display("Input Image        : %0dx%0dx%0d", IMG_WIDTH, IMG_HEIGHT, C_IN);
        $display("CONV2 Output Map   : %0dx%0dx%0d (121 px/ch)", CONV_OUT_W, CONV_OUT_H, C_OUT);
        $display("POOL2 Output Map   : %0dx%0dx%0d (5x5)", POOL_OUT_W, POOL_OUT_H, C_OUT);
        $display("Expected Output/CH : %0d Pixels", EXPECTED_POOL_PATCHES);
        $display("Total Expected Out : %0d Pixels (All 16 CHs)", EXPECTED_POOL_PATCHES * C_OUT);
        $display("==============================================");

        // B?t ??u ch?y
        trigger_start();
        send_image_stream();

        // Ch? k?t qu? tính toán
        $display("\nWaiting for POOL2 output stream...");
        timeout_cycles = 0;

        while ((timeout_cycles < 500000) && !stop_waiting) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
            
            // Phát hi?n lu?ng d? li?u x? xong (Valid h? > 100 chu k? sau khi ?ã có data)
            if (out_cnt_ch0 > 0 && !pool_out_valid[0]) begin
                repeat(100) @(posedge clk);
                if (!pool_out_valid[0]) begin
                    stop_waiting = 1'b1;
                end
            end
        end

        // Ki?m tra và ?ánh giá K?t qu?
        $display("\n==============================================");
        $display("     SIMULATION COMPLETED AT %0t ns", $time);
        $display("     Channel 0 Received : %0d / Expected: %0d Pixels", out_cnt_ch0, EXPECTED_POOL_PATCHES);
        $display("==============================================");

        if (out_cnt_ch0 == EXPECTED_POOL_PATCHES) begin
            $display(">> [PASS]: CONV2 + POOL2 CH?Y HOÀN H?O! Xu?t ?? %0d pixels (5x5) / channel!", out_cnt_ch0);
        end else if (out_cnt_ch0 > EXPECTED_POOL_PATCHES) begin
            $display(">> [FAIL]: RTL X? TH?A %0d PIXELS! (Nh?n %0d / C?n %0d)", 
                     out_cnt_ch0 - EXPECTED_POOL_PATCHES, out_cnt_ch0, EXPECTED_POOL_PATCHES);
        end else begin
            $display(">> [FAIL]: RTL THI?U %0d PIXELS! (Nh?n %0d / C?n %0d)", 
                     EXPECTED_POOL_PATCHES - out_cnt_ch0, out_cnt_ch0, EXPECTED_POOL_PATCHES);
        end

        #100;
        $display("==============================================");
        $finish;
    end

endmodule