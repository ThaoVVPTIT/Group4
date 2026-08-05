`timescale 1ns / 1ps

/*
================================================================================
    TESTBENCH CHUAN CHO CONV2 TOP LEVEL (top_conv2_ver1)
    
    Cap nhat va toi uu:
    - Fix loil VRFC 10-2989: Loai bo tu khoa 'break' (chuyen sang Verilog-2001).
    - Sua loi typo trong task send_conv2_stream.
    - Chuân hoa luong gui 1014 pixels (13x13x6) tu Pool1.
    - Tu dong Kiem tra va xac nhan xa du 121 outputs (11x11).
================================================================================
*/

module tb_top_conv2;

    // =========================================================
    // 1. PARAMETERS
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter IMG_WIDTH   = 13; // Kich thuoc ngo vao 13x13
    parameter IMG_HEIGHT  = 13;
    parameter KERNEL_SIZE = 3;
    parameter C_IN        = 6;  // 6 Kenh vao
    parameter C_OUT       = 16; // 16 Kenh ra
    parameter ACC_WIDTH   = 32;
    parameter MULT_WIDTH  = 32;
    parameter SHIFT_WIDTH = 8;

    localparam OUTPUT_WIDTH  = IMG_WIDTH  - KERNEL_SIZE + 1; // 11
    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1; // 11
    localparam PATCH_COUNT   = OUTPUT_WIDTH * OUTPUT_HEIGHT; // 121 pixels/channel

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg clk;
    reg rst_n;
    reg start;
    reg frame_clear;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    wire conv2_out_valid;
    wire conv2_out_last;
    wire signed [DATA_WIDTH-1:0] conv2_out_ch0,  conv2_out_ch1,  conv2_out_ch2,  conv2_out_ch3;
    wire signed [DATA_WIDTH-1:0] conv2_out_ch4,  conv2_out_ch5,  conv2_out_ch6,  conv2_out_ch7;
    wire signed [DATA_WIDTH-1:0] conv2_out_ch8,  conv2_out_ch9,  conv2_out_ch10, conv2_out_ch11;
    wire signed [DATA_WIDTH-1:0] conv2_out_ch12, conv2_out_ch13, conv2_out_ch14, conv2_out_ch15;
    wire conv2_done;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    top_conv2_ver1 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT),
        .ACC_WIDTH  (ACC_WIDTH),
        .MULT_WIDTH (MULT_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (start),
        .frame_clear     (frame_clear),
        .pixel_valid     (pixel_valid),
        .pixel_in        (pixel_in),

        .conv2_out_valid (conv2_out_valid),
        .conv2_out_last  (conv2_out_last),
        .conv2_out_ch0   (conv2_out_ch0),  .conv2_out_ch1 (conv2_out_ch1),
        .conv2_out_ch2   (conv2_out_ch2),  .conv2_out_ch3 (conv2_out_ch3),
        .conv2_out_ch4   (conv2_out_ch4),  .conv2_out_ch5 (conv2_out_ch5),
        .conv2_out_ch6   (conv2_out_ch6),  .conv2_out_ch7 (conv2_out_ch7),
        .conv2_out_ch8   (conv2_out_ch8),  .conv2_out_ch9 (conv2_out_ch9),
        .conv2_out_ch10  (conv2_out_ch10), .conv2_out_ch11(conv2_out_ch11),
        .conv2_out_ch12  (conv2_out_ch12), .conv2_out_ch13(conv2_out_ch13),
        .conv2_out_ch14  (conv2_out_ch14), .conv2_out_ch15(conv2_out_ch15),
        .conv2_done      (conv2_done)
    );

    // =========================================================
    // 4. CLOCK GENERATOR (10ns = 100MHz)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 5. LOAD MAU TRONG SO CHO CONV2
    // =========================================================
   // S?a l?i M?c 5 trong Testbench:
// =========================================================
// 5. LOAD MAU TRONG SO CHO CONV2 (FIX TRÀN S? 7F)
// =========================================================
integer ch_o, k;
initial begin
    // 1. Gán Weight nh? ?? t?ng tích ch?p không v??t quá 127
    for (ch_o = 0; ch_o < C_OUT; ch_o = ch_o + 1) begin
        for (k = 0; k < 9 * C_IN; k = k + 1) begin
            // Ch? dùng 0, 1, -1 ?? không b? overflow
            u_dut.c2_kernel[ch_o * 54 + k] = (k % (ch_o + 2) == 0) ? 8'sd1 : 8'sd0;
        end
        
        // 2. Cho m?i channel m?t Bias nh? khác nhau ?? phân bi?t rõ ràng
        u_dut.c2_bias[ch_o]   = ch_o; // Bias = 0, 1, 2, ..., 15
        u_dut.c2_mult[ch_o]   = 32'sd1;
        u_dut.c2_shift[ch_o]  = 8'd0;
    end
end

    // =========================================================
    // 6. MONITOR OUTPUT STREAM REALTIME
    // =========================================================
    integer out_cnt_tb = 0;
    always @(posedge clk) begin
        if (rst_n && conv2_out_valid) begin
            out_cnt_tb = out_cnt_tb + 1;
            $display("[TIME %0t ns] CONV2 OUT #%0d | LAST=%b | CH0=%d, CH1=%d, CH2=%d, CH15=%d",
                     $time, out_cnt_tb, conv2_out_last,
                     conv2_out_ch0, conv2_out_ch1, conv2_out_ch2, conv2_out_ch15);
        end
    end

    // =========================================================
    // 7. TASK: TRIGGER START
    // =========================================================
    task trigger_start;
        begin
            $display("\n==============================================");
            $display("[%0t ns] START CONV2 FRAME", $time);
            $display("==============================================");
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    // =========================================================
    // 8. TASK: STREAM MULTI-CHANNEL IMAGE (13x13x6 = 1014 Pixels)
    // =========================================================
    task send_conv2_stream;
        integer r, c, ch;
        integer val;
        begin
            $display("\n---- STREAMING %0dx%0dx%0d IMAGE STREAM ----", IMG_WIDTH, IMG_HEIGHT, C_IN);

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

            // Ket thuc du lieu anh, ha valid dong bo
            @(posedge clk);
            pixel_valid <= 1'b0;
            pixel_in    <= 8'sd0;

            $display("[%0t ns] FINISHED STREAMING EXACTLY %0d PIXELS TO CONV2", $time, IMG_WIDTH * IMG_HEIGHT * C_IN);
        end
    endtask

    // =========================================================
    // 9. MAIN SIMULATION PROCESS
    // =========================================================
    integer timeout_cycles;
    reg stop_waiting;

    initial begin
        // Khoi tao tin hieu ban dau
        rst_n        = 1'b0;
        start        = 1'b0;
        frame_clear  = 1'b0;
        pixel_valid  = 1'b0;
        pixel_in     = 8'sd0;
        out_cnt_tb   = 0;
        stop_waiting = 1'b0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Hien thi cau hinh
        $display("\n==============================================");
        $display("           CONV2 TOP TESTBENCH CONFIG");
        $display("==============================================");
        $display("Input Feature Map  : %0dx%0dx%0d", IMG_WIDTH, IMG_HEIGHT, C_IN);
        $display("Kernel Size        : %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
        $display("Output Channels    : %0d Filters", C_OUT);
        $display("Expected Output Map: %0dx%0d (%0d pixels/ch)", OUTPUT_WIDTH, OUTPUT_HEIGHT, PATCH_COUNT);
        $display("Total Input Stream : %0d Pixels", IMG_WIDTH * IMG_HEIGHT * C_IN);
        $display("==============================================");

        // Bat dau truyen Frame
        trigger_start();
        send_conv2_stream();

        // Cho tin hieu tinh toan hoan tat
        $display("\nWaiting for CONV2 calculation to complete...");
        timeout_cycles = 0;

        // Vong lap cho bang bien stop_waiting
        while ((conv2_done !== 1'b1) && (timeout_cycles < 500000) && !stop_waiting) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
            
            // Phat hien luong du lieu ngat (Valid ha xuong > 50 chu ky sau khi da co output)
            if (out_cnt_tb > 0 && !conv2_out_valid) begin
                repeat(50) @(posedge clk);
                if (!conv2_out_valid) begin
                    stop_waiting = 1'b1;
                end
            end
        end

        // Kiem tra va danh gia ket qua
        $display("\n==============================================");
        $display("       CONV2 STREAMING COMPLETED AT %0t ns", $time);
        $display("       Total Output Patches Received: %0d / Expected: %0d", out_cnt_tb, PATCH_COUNT);
        $display("==============================================");

        if (out_cnt_tb == PATCH_COUNT) begin
            $display(">> [PASS]: So luong Output Patch HOAN HAO (%0d/%0d)!", out_cnt_tb, PATCH_COUNT);
        end else if (out_cnt_tb > PATCH_COUNT) begin
            $display(">> [FAIL]: RTL XA THUA %0d PATCH! (Nhan %0d / Can %0d)", 
                     out_cnt_tb - PATCH_COUNT, out_cnt_tb, PATCH_COUNT);
        end else begin
            $display(">> [FAIL]: RTL THIEU %0d PATCH! (Nhan %0d / Can %0d)", 
                     PATCH_COUNT - out_cnt_tb, out_cnt_tb, PATCH_COUNT);
        end

        #100;
        $display("\n==============================================");
        $display("     CONV2 SIMULATION FINISHED");
        $display("==============================================");
        $finish;
    end

endmodule