`timescale 1ns / 1ps

// ============================================================================
// TESTBENCH: tb_conv1_top_ver4
// Ch?c n?ng: Test ??c l?p module conv1_top_ver4 (AXI-Stream Out, Zero-BRAM)
// ============================================================================

module tb_conv1_pool1;

    // =========================================================
    // 1. PARAMETERS CONFIGURATION
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter IMG_WIDTH   = 6;  // Kích th??c test nhanh: 6x6 (Ho?c ??i thành 28 cho chu?n)
    parameter IMG_HEIGHT  = 6;
    parameter KERNEL_SIZE = 3;
    parameter C_IN        = 1;
    parameter C_OUT       = 6;

    localparam OUTPUT_WIDTH  = IMG_WIDTH - KERNEL_SIZE + 1; // 6-3+1 = 4
    localparam OUTPUT_HEIGHT = IMG_HEIGHT - KERNEL_SIZE + 1; // 4
    localparam PATCH_COUNT   = OUTPUT_WIDTH * OUTPUT_HEIGHT; // 16 patches

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg clk;
    reg rst_n;
    reg start;

    wire ready;
    wire done;

    reg pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    // Các tín hi?u ngõ ra Stream c?a Conv1
    wire m_axis_valid;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch0;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch1;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch2;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch3;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch4;
    wire signed [DATA_WIDTH-1:0] m_axis_data_ch5;
    wire m_axis_frame_clear;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    conv1_top_ver4 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT)
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .ready              (ready),
        .done               (done),

        .pixel_valid        (pixel_valid),
        .pixel_in           (pixel_in),

        .m_axis_valid       (m_axis_valid),
        .m_axis_data_ch0    (m_axis_data_ch0),
        .m_axis_data_ch1    (m_axis_data_ch1),
        .m_axis_data_ch2    (m_axis_data_ch2),
        .m_axis_data_ch3    (m_axis_data_ch3),
        .m_axis_data_ch4    (m_axis_data_ch4),
        .m_axis_data_ch5    (m_axis_data_ch5),
        .m_axis_frame_clear (m_axis_frame_clear)
    );

    // =========================================================
    // 4. CLOCK GENERATOR (100MHz = 10ns)
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 5. MÔ PH?NG N?P TR?NG S? M?C ??NH KHI CH?A LOAD HEX
    // =========================================================
    integer i_w;
    initial begin
        for (i_w = 0; i_w < C_OUT * 9; i_w = i_w + 1) begin
            u_dut.c1_kernel[i_w] = 8'sd1;
        end
        for (i_w = 0; i_w < C_OUT; i_w = i_w + 1) begin
            u_dut.c1_bias[i_w]  = 32'sd0;
            u_dut.c1_mult[i_w]  = 32'sd1;
            u_dut.c1_shift[i_w] = 8'd0;
        end
    end

    // =========================================================
    // 6. TASK: B?M D? LI?U PIXEL ??U VÀO
    // =========================================================
    task send_full_image;
        integer r, c, val;
        begin
            $display("\n---- B?M ?NH STREAM %0dx%0d ----", IMG_WIDTH, IMG_HEIGHT);

            // Phát l?nh Start (1 clock)
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // B?m t?ng Pixel
            for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
                for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                    val = r * IMG_WIDTH + c + 1; // T?o giá tr? pixel t?ng d?n

                    @(posedge clk);
                    pixel_valid <= 1'b1;
                    pixel_in    <= val;
                end
            end

            // Flush 3 nh?p dummy ?? x? h?t tr? pipeline
            repeat (3) begin
                @(posedge clk);
                pixel_valid <= 1'b1;
                pixel_in    <= 8'sd0;
            end

            // H? valid
            @(posedge clk);
            pixel_valid <= 1'b0;
            pixel_in    <= 8'sd0;

            $display("[%0t ns] B?M XONG D? LI?U ??U VÀO", $time);
        end
    endtask

    // =========================================================
    // 7. MONITOR STREAMING OUTPUT (B?T STREAM C?A 6 CHANNELS)
    // =========================================================
    integer out_cnt = 0;

    always @(posedge clk) begin
        if (m_axis_valid) begin
            $display("[%0t ns] [STREAM OUT %0d/%0d] CH0=%d | CH1=%d | CH2=%d | CH3=%d | CH4=%d | CH5=%d",
                     $time, out_cnt, PATCH_COUNT - 1,
                     m_axis_data_ch0, m_axis_data_ch1, m_axis_data_ch2,
                     m_axis_data_ch3, m_axis_data_ch4, m_axis_data_ch5);
            out_cnt = out_cnt + 1;
        end
    end

    // =========================================================
    // 8. MAIN SIMULATION PROCESS
    // =========================================================
    integer timeout_cycles = 0;

    initial begin
        rst_n       = 1'b0;
        start       = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 8'sd0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n==============================================");
        $display("       TESTBENCH CONV1 TOP VER4 STREAMING     ");
        $display("==============================================");
        $display("Input Image : %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
        $display("Output Map  : %0dx%0d", OUTPUT_WIDTH, OUTPUT_HEIGHT);
        $display("Total Patch : %0d", PATCH_COUNT);
        $display("==============================================");

        // Ch?y b?m ?nh
        send_full_image();

        // Ch? c? DONE t? module Conv1
        while ((done !== 1'b1) && (timeout_cycles < 100000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (done === 1'b1) begin
            repeat (2) @(posedge clk);
            $display("\n==============================================");
            $display("   SUCCESS: HOÀN THÀNH CONV1 (NH?N ?? %0d PATCHES)", out_cnt);
            $display("==============================================");
        end else begin
            $display("\n==============================================");
            $display("   ERROR: TIMEOUT! KHÔNG NH?N ???C TÍN HI?U DONE");
            $display("==============================================");
        end

        #50;
        $finish;
    end

endmodule