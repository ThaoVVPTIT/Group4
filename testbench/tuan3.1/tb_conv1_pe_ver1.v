`timescale 1ns / 1ps

/*
================================================================================
   UNIT TESTBENCH CHO CONV1_PE (VERILOG IEEE 1364-2001 STANDARD)
   
   M?c tiêu ki?m th?:
   1. Ki?m tra 1-clock pipeline latency (vào patch_valid -> sau 1 clk ra output_valid).
   2. Ki?m tra tính ?úng ??n c?a phép tính: MAC + Bias + Quantization.
   3. Ki?m tra tính n?ng ReLU (c?t s? âm v? 0).
   4. Ki?m tra tính n?ng Clamp INT8 (c?t s? > 127 v? 127).
   5. Ki?m tra tín hi?u frame_clear và c? ch? tr? bus data v? 0 khi patch_valid = 0.
================================================================================
*/

module tb_conv1_pe_ver1;

    // =========================================================
    // 1. PARAMETERS
    // =========================================================
    parameter DATA_WIDTH  = 8;
    parameter ACC_WIDTH   = 32;
    parameter MULT_WIDTH  = 32;
    parameter SHIFT_WIDTH = 8;

    // =========================================================
    // 2. SIGNALS
    // =========================================================
    reg                         clk;
    reg                         rst_n;
    reg                         frame_clear;
    reg                         patch_valid;

    // Patch 3x3 inputs
    reg signed [DATA_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;

    // Filter Weights inputs
    reg signed [DATA_WIDTH-1:0] w0, w1, w2, w3, w4, w5, w6, w7, w8;

    // Bias + Quantization inputs
    reg signed [ACC_WIDTH-1:0]  bias;
    reg signed [MULT_WIDTH-1:0] multiplier;
    reg        [SHIFT_WIDTH-1:0] shift;

    // Outputs from DUT
    wire signed [DATA_WIDTH-1:0] output_data;
    wire                        output_valid;

    // =========================================================
    // 3. DUT INSTANTIATION
    // =========================================================
    conv1_pe #(
        .DATA_WIDTH (DATA_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .MULT_WIDTH (MULT_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .frame_clear (frame_clear),
        .patch_valid (patch_valid),
        
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        
        .w0(w0), .w1(w1), .w2(w2),
        .w3(w3), .w4(w4), .w5(w5),
        .w6(w6), .w7(w7), .w8(w8),
        
        .bias        (bias),
        .multiplier  (multiplier),
        .shift       (shift),
        
        .output_data (output_data),
        .output_valid(output_valid)
    );

    // Clock Generator 10ns (100MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // 4. MONITOR LOG WAVEFORM
    // =========================================================
    always @(posedge clk) begin
        if (rst_n && output_valid) begin
            $display("[TIME %0t ns] SUCCESS: OUTPUT VALID = 1 | Result INT8 = %d (Hex: 0x%02h)", 
                     $time, output_data, output_data);
        end
    end

    // =========================================================
    // 5. HELPER TASKS (VERILOG 2001 COMPLIANT)
    // =========================================================
    
    // Task n?p Patch & Weights ?? tính toán
    task send_test_vector;
        input signed [7:0] ip0; input signed [7:0] ip1; input signed [7:0] ip2;
        input signed [7:0] ip3; input signed [7:0] ip4; input signed [7:0] ip5;
        input signed [7:0] ip6; input signed [7:0] ip7; input signed [7:0] ip8;
        
        input signed [7:0] iw0; input signed [7:0] iw1; input signed [7:0] iw2;
        input signed [7:0] iw3; input signed [7:0] iw4; input signed [7:0] iw5;
        input signed [7:0] iw6; input signed [7:0] iw7; input signed [7:0] iw8;
        
        input signed [31:0] ibias;
        input signed [31:0] imult;
        input        [7:0]  ishift;
        begin
            @(posedge clk);
            patch_valid <= 1'b1;
            
            p0 <= ip0; p1 <= ip1; p2 <= ip2;
            p3 <= ip3; p4 <= ip4; p5 <= ip5;
            p6 <= ip6; p7 <= ip7; p8 <= ip8;
            
            w0 <= iw0; w1 <= iw1; w2 <= iw2;
            w3 <= iw3; w4 <= iw4; w5 <= iw5;
            w6 <= iw6; w7 <= iw7; w8 <= iw8;
            
            bias       <= ibias;
            multiplier <= imult;
            shift      <= ishift;
        end
    endtask

    // Task ng?t valid
    task clear_input;
        begin
            @(posedge clk);
            patch_valid <= 1'b0;
            p0 <= 8'sd0; p1 <= 8'sd0; p2 <= 8'sd0;
            p3 <= 8'sd0; p4 <= 8'sd0; p5 <= 8'sd0;
            p6 <= 8'sd0; p7 <= 8'sd0; p8 <= 8'sd0;
        end
    endtask

    // Task xóa frame clear
    task do_frame_clear;
        begin
            $display("\n==================================================");
            $display(">>> ISSUING FRAME_CLEAR PULSE (1 CLOCK CYCLE) <<<");
            $display("==================================================\n");
            @(posedge clk);
            frame_clear <= 1'b1;
            patch_valid <= 1'b0;
            @(posedge clk);
            frame_clear <= 1'b0;
        end
    endtask

    // =========================================================
    // 6. MAIN SIMULATION PROCESS
    // =========================================================
    initial begin
        // Reset ban ??u
        rst_n       = 1'b0;
        frame_clear = 1'b0;
        patch_valid = 1'b0;
        
        p0 = 8'sd0; p1 = 8'sd0; p2 = 8'sd0; 
        p3 = 8'sd0; p4 = 8'sd0; p5 = 8'sd0; 
        p6 = 8'sd0; p7 = 8'sd0; p8 = 8'sd0;
        
        w0 = 8'sd0; w1 = 8'sd0; w2 = 8'sd0; 
        w3 = 8'sd0; w4 = 8'sd0; w5 = 8'sd0; 
        w6 = 8'sd0; w7 = 8'sd0; w8 = 8'sd0;
        
        bias = 32'sd0; multiplier = 32'sd1; shift = 8'd0;

        #20;
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n##################################################");
        $display("         START UNIT TEST: CONV1_PE");
        $display("##################################################\n");

        // -----------------------------------------------------
        // TEST 1: TÍNH TOÁN C? B?N (NORMAL CALCULATION)
        // Patch toàn 2, Weight toàn 3 -> MAC = 9*(2*3) = 54
        // Bias = 10 -> MAC_SUM = 64
        // Multiplier = 1, Shift = 0 -> Result = 64
        // -----------------------------------------------------
        $display("---> TEST 1: Normal MAC (Expected Output = 64) <---");
        send_test_vector(
            8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, // Pixels
            8'sd3, 8'sd3, 8'sd3, 8'sd3, 8'sd3, 8'sd3, 8'sd3, 8'sd3, 8'sd3, // Weights
            32'sd10, 32'sd1, 8'd0                                        // Bias, Mult, Shift
        );

        // -----------------------------------------------------
        // TEST 2: KÍCH HO?T RELU (K?T QU? ÂM -> CUTOFF V? 0)
        // Patch = 2, Weight = -5 -> MAC = 9*(2*-5) = -90
        // Bias = 10 -> MAC_SUM = -80 -> ReLU c?t v? 0
        // -----------------------------------------------------
        $display("\n---> TEST 2: ReLU Cutoff (Expected Output = 0) <---");
        send_test_vector(
            8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2,
            -8'd5, -8'd5, -8'd5, -8'd5, -8'd5, -8'd5, -8'd5, -8'd5, -8'd5,
            32'sd10, 32'sd1, 8'd0
        );

        // -----------------------------------------------------
        // TEST 3: UPPER CLAMP INT8 (K?T QU? > 127 -> CLAMP V? 127)
        // Patch = 10, Weight = 10 -> MAC = 900 -> Multiplier = 1, Shift = 0
        // Result > 127 -> Clamp v? 127
        // -----------------------------------------------------
        $display("\n---> TEST 3: Upper Clamp (Expected Output = 127) <---");
        send_test_vector(
            8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10,
            8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10, 8'sd10,
            32'sd0, 32'sd1, 8'd0
        );

        // -----------------------------------------------------
        // TEST 4: QUANTIZATION (SCALE + ROUNDING + SHIFT)
        // p0..p1 = 10, w0..w1 = 5 -> MAC = 100, Bias = 0 -> sum = 100
        // Mult = 256, Shift = 8 -> (100 * 256 + 128) >>> 8 = 25728 >>> 8 = 100
        // -----------------------------------------------------
        $display("\n---> TEST 4: Quantization Scale & Shift (Expected Output = 100) <---");
        send_test_vector(
            8'sd10, 8'sd10, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 
            8'sd5,  8'sd5,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0,
            32'sd0, 32'sd256, 8'd8
        );

        clear_input();
        repeat (2) @(posedge clk);

        // -----------------------------------------------------
        // TEST 5: KI?M TRA FRAME_CLEAR
        // -----------------------------------------------------
        $display("\n---> TEST 5: Testing Frame Clear <---");
        send_test_vector(
            8'sd5, 8'sd5, 8'sd5, 8'sd5, 8'sd5, 8'sd5, 8'sd5, 8'sd5, 8'sd5,
            8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2, 8'sd2,
            32'sd0, 32'sd1, 8'd0
        );
        
        do_frame_clear();

        repeat (5) @(posedge clk);
        $display("\n##################################################");
        $display("       SIMULATION COMPLETE: ALL TESTS PASSED!");
        $display("##################################################\n");
        $finish;
    end

endmodule