`timescale 1ns / 1ps

module tb_top_conv1_pooling_ver1();

    parameter DATA_WIDTH  = 8;
    parameter IMG_WIDTH   = 10;  // Kích th??c tùy ý (8x8, 10x10, 28x28)
    parameter IMG_HEIGHT  = 10;
    parameter KERNEL_SIZE = 3;  
    parameter C_IN        = 1;
    parameter C_OUT       = 6;  

    localparam CONV1_OUT_W = IMG_WIDTH - KERNEL_SIZE + 1;        
    localparam CONV1_OUT_H = IMG_HEIGHT - KERNEL_SIZE + 1;       
    localparam POOL1_OUT_W = CONV1_OUT_W / 2;                    
    localparam POOL1_OUT_H = CONV1_OUT_H / 2;
    localparam EXPECTED_POOL_PIXELS = POOL1_OUT_W * POOL1_OUT_H; 

    reg clk, rst_n, start, pixel_valid;
    reg signed [DATA_WIDTH-1:0] pixel_in;

    wire ready, done;
    wire pool_out_valid, pool_out_last;
    wire signed [DATA_WIDTH-1:0] ch0, ch1, ch2, ch3, ch4, ch5;

    // DUT Instantiation
    top_conv1_pooling_ver1 #(
        .DATA_WIDTH (DATA_WIDTH),
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .C_IN       (C_IN),
        .C_OUT      (C_OUT)
    ) u_top (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .ready          (ready),
        .done           (done),

        .pixel_valid    (pixel_valid),
        .pixel_in       (pixel_in),

        .pool_out_valid (pool_out_valid),
        .pool_out_ch0   (ch0),
        .pool_out_ch1   (ch1),
        .pool_out_ch2   (ch2),
        .pool_out_ch3   (ch3),
        .pool_out_ch4   (ch4),
        .pool_out_ch5   (ch5),
        .pool_out_last  (pool_out_last)
    );

    // Clock Generator (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Monitor Output
    integer out_cnt = 0;
    always @(posedge clk) begin
        if (pool_out_valid) begin
            $display("[%0t ns] POOL1 OUT #%0d/%0d | CH0=%3d | CH1=%3d | CH2=%3d | CH3=%3d | CH4=%3d | CH5=%3d | Last=%b", 
                     $time, out_cnt, EXPECTED_POOL_PIXELS - 1,
                     ch0, ch1, ch2, ch3, ch4, ch5, pool_out_last);
            out_cnt = out_cnt + 1;
        end
    end

    // Process Main
    integer r, c, pixel_value;
    integer i_w;

    initial begin
        // -----------------------------------------------------
        // STEP 1: GÁN WEIGHT NGAY T?I TH?I ?I?M T = 0 NS
        // -----------------------------------------------------
        rst_n       = 1'b0;
        start       = 1'b0;
        pixel_valid = 1'b0;
        pixel_in    = 8'sd0;

        for (i_w = 0; i_w < C_OUT * 9; i_w = i_w + 1) begin
            u_top.u_conv1.c1_kernel[i_w] = 8'sd1; 
        end
        for (i_w = 0; i_w < C_OUT; i_w = i_w + 1) begin
            u_top.u_conv1.c1_bias[i_w]  = 32'sd0; 
            u_top.u_conv1.c1_mult[i_w]  = 32'sd1; 
            u_top.u_conv1.c1_shift[i_w] = 8'd0;   
        end

        // -----------------------------------------------------
        // STEP 2: GI? RESET DÀI H?N VÀ ?? CHO MEMORY CH?T ?I?M D? LI?U
        // -----------------------------------------------------
        #100;
        rst_n = 1'b1; 
        
        // ??i 20 nh?p clock ?? Line Buffer và PE t?nh hoàn toàn
        repeat(20) @(posedge clk);

        $display("\n=======================================================");
        $display("   CONV1 (%0dx%0d) -> POOL1 (%0dx%0d) STREAMING TEST", 
                 IMG_WIDTH, IMG_HEIGHT, POOL1_OUT_W, POOL1_OUT_H);
        $display("   T?NG PIXEL ??U VÀO : %0d", IMG_WIDTH * IMG_HEIGHT);
        $display("   MONGB ??I POOLING  : %0d Pixels", EXPECTED_POOL_PIXELS);
        $display("=======================================================");

        // -----------------------------------------------------
        // STEP 3: PHÁT START VÀ B?M PIXEL
        // -----------------------------------------------------
        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;

        $display("\n---- B?M %0d PIXELS ??U VÀO ----", IMG_HEIGHT * IMG_WIDTH);
        for (r = 0; r < IMG_HEIGHT; r = r + 1) begin
            for (c = 0; c < IMG_WIDTH; c = c + 1) begin
                pixel_value = ((r * IMG_WIDTH + c + 1) % 10); // Pixel ch? t? 0 -> 9 

                @(posedge clk);
                pixel_valid <= 1'b1;
                pixel_in    <= pixel_value;
            end
        end

        // Flush Pipeline
        repeat(3) begin
            @(posedge clk);
            pixel_valid <= 1'b1;
            pixel_in    <= 8'sd0;
        end

        @(posedge clk);
        pixel_valid <= 1'b0;
        pixel_in    <= 8'sd0;
        $display("[%0t ns] B?M XONG D? LI?U ??U VÀO", $time);

        // -----------------------------------------------------
        // STEP 4: WAIT DONE
        // -----------------------------------------------------
        wait(done == 1'b1);
        repeat(5) @(posedge clk);
        
        $display("\n=======================================================");
        $display("   SUCCESS: HOÀN THÀNH POOLING %0d PIXELS (%0dx%0d)!", 
                 out_cnt, POOL1_OUT_W, POOL1_OUT_H);
        $display("=======================================================");
        $finish;
    end

endmodule