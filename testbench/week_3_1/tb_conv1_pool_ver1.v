`timescale 1ns / 1ps

module tb_conv1_pool1_top;

    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH  = 28;
    parameter IMG_HEIGHT = 28;

    reg clk, rst_n, start, pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    wire ready, done;
    wire pool_out_valid, pool_out_last;
    wire signed [DATA_WIDTH-1:0] ch0, ch1, ch2, ch3, ch4, ch5;

    // Instantiate Top Module
    conv1_pool_ver1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_top (
        .clk(clk), .rst_n(rst_n), .start(start), .ready(ready), .done(done),
        .pixel_valid(pixel_valid), .pixel_in(pixel_in),
        .pool_out_valid(pool_out_valid),
        .pool_out_ch0(ch0), .pool_out_ch1(ch1), .pool_out_ch2(ch2),
        .pool_out_ch3(ch3), .pool_out_ch4(ch4), .pool_out_ch5(ch5),
        .pool_out_last(pool_out_last)
    );

    // Clock 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Monitor Output
    integer out_cnt = 0;
    always @(posedge clk) begin
        if (pool_out_valid) begin
            $display("[%0t ns] POOL1 OUT #%0d | CH0=%d | CH1=%d | CH2=%d | CH3=%d | CH4=%d | CH5=%d", 
                     $time, out_cnt, ch0, ch1, ch2, ch3, ch4, ch5);
            out_cnt = out_cnt + 1;
        end
    end

    // Test Process
    integer r, c;
    initial begin
        rst_n = 0; start = 0; pixel_valid = 0; pixel_in = 0;
        #20 rst_n = 1;
        repeat(2) @(posedge clk);

        // Phát l?nh Start
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        // B?m 28x28 = 784 pixels
        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                @(posedge clk);
                pixel_valid = 1;
                pixel_in    = (r * IMG_WIDTH + c + 1) % 127;
            end
        end

        // Flush
        repeat(3) @(posedge clk);
        pixel_valid = 0;

        // Ch? tín hi?u DONE t? Pooling
        wait(done == 1'b1);
        repeat(5) @(posedge clk);
        
        $display("\n=======================================================");
        $display("   SUCCESS: HOÀN THÀNH T?O POOLING %0d PIXELS (13x13)!", out_cnt);
        $display("=======================================================");
        $finish;
    end

endmodule